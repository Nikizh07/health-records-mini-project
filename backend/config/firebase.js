// backend/config/firebase.js
// ============================================================
// Firebase Admin SDK Initialization Singleton
// ============================================================
// Supports firebase-admin v14+ modular API.
//
// Credentials, in order:
//   1. FIREBASE_SERVICE_ACCOUNT_JSON — the whole key as an env var, raw JSON
//      or base64. Use this on any host (Render, ECS): the key file is
//      .dockerignored, so it is NOT in the image and the file path below
//      finds nothing.
//   2. FIREBASE_SERVICE_ACCOUNT_PATH — the local key file (local dev).
// There is no Application Default Credentials fallback: outside Google Cloud
// it can only fail later, at the first token verification, so fail loudly here.
// ============================================================

'use strict';

const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const path = require('path');
const fs = require('fs');

/** Accepts raw JSON or base64-encoded JSON, so it survives shells and dashboards. */
function serviceAccountFromEnv() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw || !raw.trim()) return null;

  const text = raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
  const account = JSON.parse(text);
  // A key pasted through a dashboard often arrives with literal \n in the PEM.
  if (typeof account.private_key === 'string') {
    account.private_key = account.private_key.replace(/\\n/g, '\n');
  }
  return account;
}

if (getApps().length === 0) {
  let initialized = false;

  try {
    const fromEnv = serviceAccountFromEnv();
    if (fromEnv) {
      initializeApp({ credential: cert(fromEnv) });
      console.log('✅ Firebase Admin SDK initialized from FIREBASE_SERVICE_ACCOUNT_JSON');
      initialized = true;
    }
  } catch (err) {
    // Don't fall through silently: a malformed env var must be obvious.
    console.error('❌ FIREBASE_SERVICE_ACCOUNT_JSON is set but unreadable:', err.message);
  }

  if (!initialized) {
    const relativePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './config/firebase-adminsdk.json';
    const resolvedPath = path.resolve(__dirname, '..', relativePath);

    if (fs.existsSync(resolvedPath)) {
      try {
        const serviceAccount = require(resolvedPath);
        initializeApp({ credential: cert(serviceAccount) });
        console.log('✅ Firebase Admin SDK initialized with Service Account Key');
        initialized = true;
      } catch (err) {
        console.error('❌ Failed to load Firebase Service Account JSON file:', err.message);
      }
    }
  }

  if (!initialized) {
    throw new Error(
      'Firebase Admin credentials missing. Set FIREBASE_SERVICE_ACCOUNT_JSON ' +
      '(raw JSON or base64) or place the key file at the path given by ' +
      'FIREBASE_SERVICE_ACCOUNT_PATH. Off Google Cloud there is no ADC fallback.'
    );
  }
}

const auth = getAuth();

module.exports = {
  auth,
};
