// scripts/get-test-tokens.js
// ============================================================
// Helper script to get Firebase ID tokens for Postman testing.
// Exchanges Admin SDK custom tokens for ID tokens via REST API.
//
// Usage:
//   node scripts/get-test-tokens.js
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const { auth } = require('../config/firebase');
const https = require('https');

const WEB_API_KEY = process.env.FIREBASE_WEB_API_KEY;

if (!WEB_API_KEY) {
  console.error('\n❌  Missing FIREBASE_WEB_API_KEY in your .env file.');
  console.error('   Find it in: Firebase Console → Project Settings → General → Web API key\n');
  process.exit(1);
}

// ── Test users — edit UIDs to match your Firebase project ────
// Get UIDs from: Firebase Console → Authentication → Users
const TEST_USERS = [
  { label: 'ADMIN',   uid: process.env.TEST_ADMIN_UID   || 'REPLACE_WITH_ADMIN_FIREBASE_UID'   },
  { label: 'PATIENT', uid: process.env.TEST_PATIENT_UID || 'REPLACE_WITH_PATIENT_FIREBASE_UID' },
];

/**
 * Exchange a Firebase Custom Token for an ID Token via REST.
 * The Admin SDK generates a custom token; Firebase REST API
 * exchanges it for a usable ID token (what your middleware expects).
 */
function exchangeCustomToken(customToken) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      token: customToken,
      returnSecureToken: true,
    });

    const options = {
      hostname: 'identitytoolkit.googleapis.com',
      path: `/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.error) reject(new Error(json.error.message));
          else resolve(json.idToken);
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function main() {
  console.log('\n🔑  Generating Firebase ID Tokens for Postman testing...\n');
  console.log('='.repeat(70));

  for (const user of TEST_USERS) {
    if (user.uid.startsWith('REPLACE_')) {
      console.log(`\n⚠️  [${user.label}] Skipped — UID not configured.`);
      console.log(`   Set TEST_${user.label}_UID=<firebase-uid> in your .env file.`);
      continue;
    }

    try {
      // Step 1: Admin SDK creates a custom token for the given UID
      const customToken = await auth.createCustomToken(user.uid);

      // Step 2: Exchange the custom token for an ID token via REST
      const idToken = await exchangeCustomToken(customToken);

      console.log(`\n✅  [${user.label}] UID: ${user.uid}`);
      console.log(`\nBearer Token (copy into Postman — valid 1 hour):\n`);
      console.log(idToken);
      console.log('\n' + '-'.repeat(70));
    } catch (err) {
      console.error(`\n❌  [${user.label}] Failed: ${err.message}`);
    }
  }

  console.log('\n📋  Paste each token into Postman:');
  console.log('    Authorization tab → Type: Bearer Token → paste above token\n');

  // Force exit — Prisma/pg pool keeps process alive otherwise
  process.exit(0);
}

main();
