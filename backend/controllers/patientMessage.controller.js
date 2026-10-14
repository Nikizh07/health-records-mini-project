// backend/controllers/patientMessage.controller.js
// ============================================================
// Patient Message Controller (Smart Prescriptions Phase 5)
// ============================================================
// Handles:
// 1. POST  /api/records/:id/patient-message/preview  — Preview script + pictogram (no send)
// 2. POST  /api/records/:id/patient-message/send     — Send WhatsApp message
// 3. GET   /api/records/:id/patient-message          — Get latest message status
//
// All routes require:
// - requirePermission('message:send')
// - requirePatientAccess(<ACTION>, fromRecord)
//
// The permission check gates the feature to doctors. The patient access check
// ensures the doctor can see this patient's record (via CARE link, consent, or
// emergency). requirePatientAccess already handles the access log write.
// ============================================================

'use strict';

const {
  previewPatientMessage,
  sendPatientMessage,
  getPatientMessageStatus,
} = require('../services/patientMessage/send');

/**
 * POST /api/records/:id/patient-message/preview
 *
 * Build the script and pictogram without storing or sending. Returns the exact
 * segments that will be spoken, the chart as a data URI, and blockers if any.
 *
 * @param {object} req.params.id - Medical record UUID
 * @param {string} [req.body.language] - Override patient's language_pref
 */
async function preview(req, res, next) {
  try {
    const { id: recordId } = req.params;
    const { language } = req.body;

    const result = await previewPatientMessage(recordId, language);

    res.json({
      success: true,
      data: result,
    });
  } catch (err) {
    next(err);
  }
}

/**
 * POST /api/records/:id/patient-message/send
 *
 * Send the WhatsApp message. Creates a QUEUED row, synthesizes audio, builds
 * the pictogram, stores assets, sends, and updates the row to SENT or FAILED.
 *
 * Fail-closed: blocks if whatsapp_opt_in is false, phone is missing/invalid,
 * or any prescription's schedule is incomplete.
 *
 * @param {object} req.params.id - Medical record UUID
 * @param {string} [req.body.language] - Override patient's language_pref
 */
async function send(req, res, next) {
  try {
    const { id: recordId } = req.params;
    const { language } = req.body;

    const result = await sendPatientMessage(recordId, language);

    res.json({
      success: true,
      data: result,
    });
  } catch (err) {
    // Special handling for SCHEDULE_INCOMPLETE errors
    if (err.code === 'SCHEDULE_INCOMPLETE') {
      return res.status(400).json({
        success: false,
        error: {
          code: err.code,
          message: err.message,
          blockers: err.blockers,
        },
      });
    }

    // Precondition failures (NO_WHATSAPP_CONSENT, NO_PHONE, etc.)
    if (err.message && err.message.startsWith('Send precondition failed:')) {
      const match = err.message.match(/\(([A-Z_]+)\)$/);
      const code = match ? match[1] : 'PRECONDITION_FAILED';
      
      return res.status(409).json({
        success: false,
        error: {
          code,
          message: err.message.replace(/^Send precondition failed: /, '').replace(/ \([A-Z_]+\)$/, ''),
        },
      });
    }

    next(err);
  }
}

/**
 * GET /api/records/:id/patient-message
 *
 * Get the latest message status for a record. Returns null if no message has
 * been sent yet.
 *
 * @param {object} req.params.id - Medical record UUID
 */
async function getStatus(req, res, next) {
  try {
    const { id: recordId } = req.params;

    const message = await getPatientMessageStatus(recordId);

    res.json({
      success: true,
      data: message,
    });
  } catch (err) {
    next(err);
  }
}

module.exports = {
  preview,
  send,
  getStatus,
};
