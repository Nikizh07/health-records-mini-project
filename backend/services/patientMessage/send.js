// backend/services/patientMessage/send.js
// ============================================================
// Patient message orchestrator (Phase 5)
// ============================================================
// The complete pipeline: resolve language → build script → synthesize audio →
// build + rasterise pictogram → store assets → generate signed URLs → send →
// update the delivery record.
//
// Assets are stored as base64 in PatientMessage.payload.assets so the audit
// survives template edits and media expiry, and the backend needs no S3.
//
// FAIL CLOSED: a prescription whose schedule is unset blocks the send rather
// than being described vaguely. There is no literate reader downstream to
// catch a wrong instruction.
// ============================================================

'use strict';

const prisma = require('../../config/prisma');
const { buildScript } = require('./script');
const { buildSvg, rasterise } = require('./pictogram');
const { synthesize, isTtsEnabled } = require('../tts');
const { send: sendMessage, isMessagingEnabled } = require('../messaging');
const { generateMediaUrl } = require('../../utils/mediaToken');
const { parseDurationDays } = require('../../utils/prescriptionWindow');
const { normalisePhone } = require('../../utils/phone');

/**
 * Validate that a send can proceed. Returns an error code or null.
 */
function validateSendPreconditions(patient, record) {
  if (!patient.whatsapp_opt_in) {
    return { code: 'NO_WHATSAPP_CONSENT', message: 'Patient has not consented to WhatsApp messages' };
  }

  if (!patient.phone) {
    return { code: 'NO_PHONE', message: 'Patient has no phone number' };
  }

  const phone = normalisePhone(patient.phone);
  if (!phone) {
    return { code: 'INVALID_PHONE', message: 'Patient phone number is not valid E.164' };
  }

  if (!isMessagingEnabled()) {
    return { code: 'MESSAGING_DISABLED', message: 'Messaging provider is not configured' };
  }

  if (!isTtsEnabled()) {
    return { code: 'TTS_DISABLED', message: 'Text-to-speech provider is not configured' };
  }

  // Check for PUBLIC_BASE_URL if using twilio-sandbox
  const msgProvider = process.env.MSG_PROVIDER || 'log';
  if (msgProvider === 'twilio-sandbox' && !process.env.PUBLIC_BASE_URL) {
    return { code: 'PUBLIC_URL_REQUIRED', message: 'PUBLIC_BASE_URL is required for Twilio Sandbox' };
  }

  return null;
}

/**
 * Enrich prescriptions with parsed duration (days).
 */
function enrichPrescriptions(prescriptions) {
  return (prescriptions || []).map(rx => ({
    ...rx,
    days: parseDurationDays(rx.duration),
  }));
}

/**
 * Preview: build script and pictogram without storing or sending.
 *
 * @param {string} recordId - Medical record UUID
 * @param {string} [language] - Override patient's language_pref
 * @returns {Promise<{
 *   language_used: string,
 *   requested_language: string,
 *   supported: boolean,
 *   segments: Array,
 *   blockers: Array,
 *   chart: string|null,
 *   preconditions: {valid: boolean, error?: {code: string, message: string}}
 * }>}
 */
async function previewPatientMessage(recordId, language) {
  const record = await prisma.medicalRecord.findUnique({
    where: { id: recordId },
    include: {
      patient: true,
      doctor: true,
      prescriptions: { orderBy: { created_at: 'asc' } },
    },
  });

  if (!record) {
    throw new Error('Medical record not found');
  }

  // Enrich prescriptions with parsed days
  const enrichedRecord = {
    ...record,
    prescriptions: enrichPrescriptions(record.prescriptions),
  };

  // Build script
  const script = buildScript(enrichedRecord, language);

  // Build pictogram (SVG only, no rasterisation in preview)
  const svg = buildSvg(script.medicines);
  const chartDataUri = svg ? `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}` : null;

  // Validate preconditions
  const preconditionError = validateSendPreconditions(record.patient, record);

  return {
    language_used: script.language_used,
    requested_language: script.requested_language,
    supported: script.supported,
    segments: script.segments,
    blockers: script.blockers,
    chart: chartDataUri,
    preconditions: {
      valid: !preconditionError,
      ...(preconditionError && { error: preconditionError }),
    },
  };
}

/**
 * Send: complete pipeline from record to WhatsApp delivery.
 *
 * @param {string} recordId - Medical record UUID
 * @param {string} [language] - Override patient's language_pref
 * @returns {Promise<{
 *   messageId: string,
 *   status: string,
 *   providerMessageId: string|null,
 *   error: string|null
 * }>}
 */
async function sendPatientMessage(recordId, language) {
  // Fetch record with relations
  const record = await prisma.medicalRecord.findUnique({
    where: { id: recordId },
    include: {
      patient: true,
      doctor: true,
      prescriptions: { orderBy: { created_at: 'asc' } },
    },
  });

  if (!record) {
    throw new Error('Medical record not found');
  }

  // Validate preconditions
  const preconditionError = validateSendPreconditions(record.patient, record);
  if (preconditionError) {
    throw new Error(`Send precondition failed: ${preconditionError.message} (${preconditionError.code})`);
  }

  // Enrich prescriptions with parsed days
  const enrichedRecord = {
    ...record,
    prescriptions: enrichPrescriptions(record.prescriptions),
  };

  // Build script
  const script = buildScript(enrichedRecord, language);

  // FAIL CLOSED: block if any prescriptions have schedule issues
  if (script.blockers.length > 0) {
    const prescriptionIds = script.blockers.map(b => b.prescription_id).filter(Boolean);
    const error = `Schedule incomplete for prescription(s): ${prescriptionIds.join(', ')}`;
    
    throw Object.assign(new Error(error), {
      code: 'SCHEDULE_INCOMPLETE',
      blockers: script.blockers,
    });
  }

  // Guard: only block if a message is currently in-flight (QUEUED).
  // SENT records can be resent — the doctor may want to resend after edits
  // or for a follow-up. FAILED records should always be retried.
  const inFlight = await prisma.patientMessage.findFirst({
    where: { record_id: recordId, status: 'QUEUED' },
    select: { id: true },
  });
  if (inFlight) {
    throw Object.assign(
      new Error('A message is already being sent for this record. Please wait for it to complete.'),
      { code: 'DUPLICATE_SEND' }
    );
  }

  // Create QUEUED message row
  const message = await prisma.patientMessage.create({
    data: {
      record_id: recordId,
      patient_id: record.patient_id,
      doctor_id: record.doctor_id,
      language: script.language_used,
      status: 'QUEUED',
      payload: {
        script,
        assets: [],
      },
    },
  });

  try {
    // Synthesize audio for each segment
    const audioAssets = [];
    for (let i = 0; i < script.segments.length; i++) {
      const segment = script.segments[i];
      const filename = `audio-${i}.mp3`;
      
      const audioBuffer = await synthesize({
        text: segment.text,
        languageCode: script.language_used,
      });

      audioAssets.push({
        filename,
        base64Data: audioBuffer.toString('base64'),
        mimetype: 'audio/mpeg',
        segment: segment.key,
      });
    }

    // Build and rasterise pictogram
    const svg = buildSvg(script.medicines);
    const pngBuffer = await rasterise(svg);
    
    let chartAsset = null;
    if (pngBuffer) {
      chartAsset = {
        filename: 'chart.png',
        base64Data: pngBuffer.toString('base64'),
        mimetype: 'image/png',
      };
    }

    // Store assets in payload
    const assets = [...audioAssets];
    if (chartAsset) {
      assets.push(chartAsset);
    }

    // Generate signed media URLs
    const mediaForSend = assets.map(asset => ({
      buffer: Buffer.from(asset.base64Data, 'base64'),
      mimetype: asset.mimetype,
      filename: asset.filename,
      url: generateMediaUrl(recordId, message.id, asset.filename),
    }));

    // Build message body (text transcript for accessibility)
    const bodyParts = [
      `${record.patient.name}, here are your medication instructions:`,
      '',
    ];
    script.segments.forEach((seg, i) => {
      if (seg.key === 'prescription') {
        bodyParts.push(`${seg.index}. ${seg.gloss}`);
      }
    });
    const body = bodyParts.join('\n');

    // Send via messaging provider
    // TEMP TESTING OVERRIDE: Use hardcoded number for WhatsApp testing
    // In production, this would use: normalisePhone(record.patient.phone)
    const phone = '+919342060715'; // Hardcoded test number

    // Try with media first; if the provider rejects media (e.g. Twilio trial
    // account restriction), fall back to text-only so the message still lands.
    let sendResult;
    try {
      sendResult = await sendMessage({
        to: phone,
        body,
        media: mediaForSend,
      });
    } catch (mediaErr) {
      console.warn('⚠️  Media send failed, retrying text-only:', mediaErr.message);
      sendResult = await sendMessage({
        to: phone,
        body,
        media: [],
      });
    }

    // Update message row to SENT
    await prisma.patientMessage.update({
      where: { id: message.id },
      data: {
        status: 'SENT',
        provider: process.env.MSG_PROVIDER || 'log',
        provider_message_id: sendResult.providerMessageId,
        sent_at: new Date(),
        payload: {
          script,
          assets,
        },
      },
    });

    return {
      messageId: message.id,
      status: 'SENT',
      providerMessageId: sendResult.providerMessageId,
      error: null,
    };

  } catch (err) {
    // Update message row to FAILED
    await prisma.patientMessage.update({
      where: { id: message.id },
      data: {
        status: 'FAILED',
        error: err.message,
      },
    });

    throw err;
  }
}

/**
 * Get the latest message status for a record.
 *
 * @param {string} recordId
 * @returns {Promise<object|null>}
 */
async function getPatientMessageStatus(recordId) {
  const message = await prisma.patientMessage.findFirst({
    where: { record_id: recordId },
    orderBy: { created_at: 'desc' },
    select: {
      id: true,
      status: true,
      language: true,
      provider: true,
      provider_message_id: true,
      error: true,
      created_at: true,
      sent_at: true,
    },
  });

  return message;
}

module.exports = {
  previewPatientMessage,
  sendPatientMessage,
  getPatientMessageStatus,
  validateSendPreconditions, // exported for testing
};
