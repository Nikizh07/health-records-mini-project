// backend/config/firebase.js
// ============================================================
// Firebase Admin SDK Initialization Singleton
// ============================================================
// Supports firebase-admin v14+ modular API
// ============================================================

'use strict';

const { initializeApp, getApps, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const path = require('path');
const fs = require('fs');

if (getApps().length === 0) {
  const relativePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './config/firebase-adminsdk.json';
  const resolvedPath = path.resolve(__dirname, '..', relativePath);

  if (fs.existsSync(resolvedPath)) {
    try {
      const serviceAccount = require(resolvedPath);
      initializeApp({
        credential: cert(serviceAccount),
      });
      console.log('✅ Firebase Admin SDK initialized with Service Account Key');
    } catch (err) {
      console.error('❌ Failed to load Firebase Service Account JSON file:', err.message);
      initializeApp();
    }
  } else {
    console.warn(`⚠️ Firebase service account key not found at "${resolvedPath}".`);
    console.warn('⚠️ Fallback: Initializing Firebase Admin SDK with Application Default Credentials (ADC)...');
    initializeApp();
  }
}

const auth = getAuth();

module.exports = {
  auth,
};
