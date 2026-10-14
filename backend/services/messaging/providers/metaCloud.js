// backend/services/messaging/providers/metaCloud.js
// ============================================================
// Meta WhatsApp Cloud API provider.
//
// Uses the official Graph API at graph.facebook.com/v19.0.
// Works on the free developer tier — no paid plan needed.
// Supports sending text + media (image/audio) as separate messages.
//
// Required env vars:
//   META_PHONE_NUMBER_ID   — numeric ID of the sending phone number
//   META_ACCESS_TOKEN      — permanent system-user token (or temporary test token)
//
// Optional:
//   META_API_VERSION       — Graph API version, defaults to v19.0
//   META_WABA_ID           — WhatsApp Business Account ID (for template management)
//
// ⚠️  24-HOUR CONVERSATION WINDOW (dev/test tier)
//   Meta only delivers free-form messages inside a 24-hour window that opens
//   when the PATIENT messages the clinic number first.
//
//   Dev / testing:
//     1. Patient taps: https://wa.me/15556755619?text=Hi
//     2. Sends any message to +1 555-675-5619
//     3. Free-form text + media now works for 24 h
//
//   Production:
//     Send an approved template (e.g. appointment reminder) to initiate the
//     conversation — Meta delivers it and opens the 24-hour window.
// ============================================================

'use strict';

const DEFAULT_API_VERSION = 'v19.0';

function isConfigured() {
  return Boolean(
    process.env.META_PHONE_NUMBER_ID &&
    process.env.META_ACCESS_TOKEN
  );
}

/**
 * Upload a media buffer to Meta's media CDN and return the media_id.
 * Meta requires media to be on their CDN — public URLs are not accepted.
 *
 * @param {Buffer} buffer
 * @param {string} mimetype  e.g. 'audio/mpeg' | 'image/png'
 * @param {string} filename  e.g. 'audio-0.mp3'
 * @param {string} token
 * @param {string} phoneNumberId
 * @param {string} apiVersion
 * @returns {Promise<string>} media_id
 */
async function uploadMedia(buffer, mimetype, filename, token, phoneNumberId, apiVersion) {
  const url = `https://graph.facebook.com/${apiVersion}/${phoneNumberId}/media`;

  // Meta's media upload uses multipart/form-data (native FormData, Node 18+)
  const form = new FormData();
  form.append('messaging_product', 'whatsapp');
  form.append('type', mimetype);
  form.append('file', new Blob([buffer], { type: mimetype }), filename);

  const res = await fetch(url, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}` },
    body: form,
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Media upload failed (${res.status}): ${err}`);
  }

  const data = await res.json();
  if (!data.id) throw new Error(`Media upload returned no ID: ${JSON.stringify(data)}`);
  return data.id;
}

/**
 * Send a WhatsApp message via Meta Cloud API.
 *
 * Sends text first, then each media item as a separate message
 * (Meta doesn't support multiple media attachments in one message).
 *
 * Requires the patient to have messaged the clinic number first to open
 * a 24-hour conversation window (see file header for details).
 *
 * @param {Object} params
 * @param {string} params.to              E.164 phone number, e.g. '+919876543210'
 * @param {string} params.body            Text transcript / prescription summary
 * @param {Array<{buffer, mimetype, filename}>} params.media
 * @param {AbortSignal} [params.signal]
 * @returns {Promise<{providerMessageId: string}>}
 */
async function send({ to, body, media = [], signal }) {
  if (!isConfigured()) {
    throw new Error('Meta Cloud API not configured (META_PHONE_NUMBER_ID / META_ACCESS_TOKEN missing)');
  }

  const token = process.env.META_ACCESS_TOKEN;
  const phoneNumberId = process.env.META_PHONE_NUMBER_ID;
  const apiVersion = process.env.META_API_VERSION || DEFAULT_API_VERSION;
  const apiUrl = `https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`;

  // Meta wants bare E.164 (no + prefix, no whatsapp: prefix)
  const toNumber = to.replace(/^whatsapp:/, '').replace(/^\+/, '');

  const headers = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };

  let lastMessageId = null;

  // ① Send prescription text
  const textPayload = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to: toNumber,
    type: 'text',
    text: { preview_url: false, body },
  };

  const textRes = await fetch(apiUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify(textPayload),
    signal,
  });

  if (!textRes.ok) {
    const err = await textRes.text();
    throw new Error(`Text message failed (${textRes.status}): ${err}`);
  }

  const textData = await textRes.json();
  lastMessageId = textData.messages?.[0]?.id;

  // ② Upload + send each media item as a separate message
  for (const item of media) {
    try {
      const mediaId = await uploadMedia(item.buffer, item.mimetype, item.filename, token, phoneNumberId, apiVersion);

      let msgType = 'document';
      if (item.mimetype.startsWith('audio/')) msgType = 'audio';
      else if (item.mimetype.startsWith('image/')) msgType = 'image';

      const mediaPayload = {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: toNumber,
        type: msgType,
        [msgType]: { id: mediaId },
      };

      const mediaRes = await fetch(apiUrl, {
        method: 'POST',
        headers,
        body: JSON.stringify(mediaPayload),
        signal,
      });

      if (!mediaRes.ok) {
        const err = await mediaRes.text();
        // Non-fatal: log and continue with remaining media
        console.warn(`⚠️  Meta media send failed for ${item.filename} (${mediaRes.status}): ${err}`);
        continue;
      }

      const mediaData = await mediaRes.json();
      lastMessageId = mediaData.messages?.[0]?.id ?? lastMessageId;
    } catch (uploadErr) {
      console.warn(`⚠️  Media upload skipped for ${item.filename}:`, uploadErr.message);
    }
  }

  if (!lastMessageId) {
    throw new Error('Meta API returned no message ID');
  }

  return { providerMessageId: lastMessageId };
}

module.exports = {
  name: 'meta-cloud',
  isConfigured,
  send,
};
