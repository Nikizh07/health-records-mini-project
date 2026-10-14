// backend/services/messaging/providers/twilioSandbox.js
// ============================================================
// Twilio WhatsApp Sandbox provider: sends via Twilio's test sandbox.
// Requires recipients to send "join <sandbox-name>" to the Twilio number first.
// ============================================================

'use strict';

function isConfigured() {
  return Boolean(
    process.env.TWILIO_ACCOUNT_SID &&
    process.env.TWILIO_AUTH_TOKEN &&
    process.env.TWILIO_SANDBOX_NUMBER &&
    process.env.PUBLIC_BASE_URL
  );
}

/**
 * @param {Object} params
 * @param {string} params.to - E.164 phone number (e.g., '+919876543210')
 * @param {string} params.body - Message text
 * @param {Array<{buffer: Buffer, mimetype: string, filename: string, url: string}>} params.media
 * @param {AbortSignal} [params.signal] - Timeout signal
 * @returns {Promise<{providerMessageId: string}>}
 */
async function send({ to, body, media = [], signal }) {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_SANDBOX_NUMBER; // e.g., 'whatsapp:+14155238886'
  const publicBaseUrl = process.env.PUBLIC_BASE_URL;

  if (!isConfigured()) {
    throw new Error('Twilio Sandbox not configured (missing env vars)');
  }

  // Ensure "to" has whatsapp: prefix
  const toNumber = to.startsWith('whatsapp:') ? to : `whatsapp:${to}`;

  // Build form data for Twilio API
  const formData = new URLSearchParams();
  formData.append('From', from);
  formData.append('To', toNumber);
  formData.append('Body', body);

  // Add media URLs (Twilio fetches them from our server)
  media.forEach(({ url }) => {
    if (url) {
      formData.append('MediaUrl', url);
    }
  });

  const url = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
  const auth = Buffer.from(`${accountSid}:${authToken}`).toString('base64');

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${auth}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: formData.toString(),
    signal,
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Twilio API error (${response.status}): ${error}`);
  }

  const result = await response.json();
  
  return { providerMessageId: result.sid };
}

module.exports = {
  name: 'twilio-sandbox',
  isConfigured,
  send,
};
