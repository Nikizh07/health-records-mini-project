// backend/services/messaging/providers/log.js
// ============================================================
// Log provider: writes messages to disk and console for local testing.
// Works with zero external credentials.
// ============================================================

'use strict';

const fs = require('fs');
const path = require('path');
const { randomUUID } = require('crypto');

const OUTPUT_DIR = path.resolve(__dirname, '../../../.scratch/messages');

function isConfigured() {
  // Always available - no external credentials needed
  return true;
}

/**
 * @param {Object} params
 * @param {string} params.to - Recipient phone number
 * @param {string} params.body - Message text
 * @param {Array<{buffer: Buffer, mimetype: string, filename: string, url: string}>} params.media
 * @returns {Promise<{providerMessageId: string}>}
 */
async function send({ to, body, media = [] }) {
  const messageId = `log_${randomUUID()}`;
  const timestamp = new Date().toISOString();
  
  // Ensure output directory exists
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  
  const messageDir = path.join(OUTPUT_DIR, messageId);
  fs.mkdirSync(messageDir, { recursive: true });
  
  // Write message metadata
  const metadata = {
    id: messageId,
    to,
    body,
    timestamp,
    mediaCount: media.length,
  };
  
  fs.writeFileSync(
    path.join(messageDir, 'message.json'),
    JSON.stringify(metadata, null, 2)
  );
  
  // Write body as text
  fs.writeFileSync(path.join(messageDir, 'body.txt'), body);
  
  // Write media files
  media.forEach(({ buffer, filename }, index) => {
    const filepath = path.join(messageDir, filename || `asset-${index}`);
    fs.writeFileSync(filepath, buffer);
  });
  
  // Console output
  console.log('\n📨 [LOG PROVIDER] Message queued');
  console.log(`   To: ${to}`);
  console.log(`   ID: ${messageId}`);
  console.log(`   Body: ${body.substring(0, 100)}${body.length > 100 ? '...' : ''}`);
  console.log(`   Media: ${media.length} file(s)`);
  console.log(`   Saved to: ${messageDir}\n`);
  
  return { providerMessageId: messageId };
}

module.exports = {
  name: 'log',
  isConfigured,
  send,
};
