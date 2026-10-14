// backend/scripts/test-messaging-provider.js
// ============================================================
// Verify the messaging provider is configured and can handle a send.
// ============================================================
// Tests the messaging provider with a dummy message. The log provider writes
// to .scratch/messages/, the twilio-sandbox provider would send a real WhatsApp
// (but we skip that in automated tests).
//
// Usage:
//   node scripts/test-messaging-provider.js
//   MSG_PROVIDER=twilio-sandbox TWILIO_ACCOUNT_SID=... node scripts/test-messaging-provider.js
//
// Exits 0 if the provider is configured and the send logic works, 1 otherwise.
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const { isMessagingEnabled, getProvider } = require('../services/messaging');

async function main() {
  const providerKey = process.env.MSG_PROVIDER || 'log';
  console.log(`\nMessaging Provider: ${providerKey}`);

  if (!isMessagingEnabled()) {
    console.error('❌ Messaging is disabled or the provider is missing its env vars (see backend/.env.example).');
    process.exit(1);
  }

  const provider = getProvider();
  if (!provider) {
    console.error(`❌ Unknown provider: ${providerKey}`);
    process.exit(1);
  }

  console.log(`✓ Provider "${provider.name}" is configured\n`);

  // Don't actually send with twilio-sandbox in automated tests
  if (providerKey === 'twilio-sandbox') {
    console.log('⚠️  Skipping actual send test for twilio-sandbox (would send real WhatsApp).');
    console.log('   To test Twilio Sandbox manually:');
    console.log('   1. Recipient must send "join <sandbox-name>" to the Twilio number');
    console.log('   2. Use the full API endpoint: POST /api/records/:id/patient-message/send');
    console.log('   3. Check Twilio dashboard for delivery status\n');
    process.exit(0);
  }

  // For log provider, test a dummy send
  try {
    console.log('Testing send with dummy data...');
    const result = await provider.send({
      to: 'whatsapp:+919876543210',
      body: 'Test message from messaging provider smoke test',
      media: [
        {
          buffer: Buffer.from('test-audio-content'),
          mimetype: 'audio/mpeg',
          filename: 'test-audio.mp3',
          url: 'http://localhost:3000/api/media/test-token/test-audio.mp3',
        },
      ],
    });

    if (!result || !result.providerMessageId) {
      throw new Error('Provider returned no message ID');
    }

    console.log(`✓ Send succeeded`);
    console.log(`  Message ID: ${result.providerMessageId}`);
    
    if (providerKey === 'log') {
      console.log(`  Check: backend/.scratch/messages/${result.providerMessageId}/\n`);
    }

    process.exit(0);
  } catch (err) {
    console.error(`❌ Send failed: ${err.message}\n`);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(`❌ Unexpected error: ${err.message}\n`);
  console.error(err.stack);
  process.exit(1);
});
