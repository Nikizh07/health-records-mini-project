// backend/middleware/authenticate.js
// ============================================================
// Firebase Authentication Middleware
// ============================================================
// 1. Reads the Authorization header ("Bearer <token>")
// 2. Decodes & verifies the Firebase ID Token via Firebase Admin SDK
// 3. Lookups database user role & ID (if User model exists)
// 4. Attaches user details to `req.user`
// 5. Returns 401 Unauthorized if token is missing, expired, or invalid.
// ============================================================

'use strict';

const { auth } = require('../config/firebase');
const prisma = require('../config/prisma');

async function authenticate(req, res, next) {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        error: 'Unauthorized',
        message: 'Access denied. Missing or malformed Authorization header. Expected format: "Authorization: Bearer <ID_TOKEN>"',
      });
    }

    const idToken = authHeader.split('Bearer ')[1]?.trim();

    if (!idToken) {
      return res.status(401).json({
        success: false,
        error: 'Unauthorized',
        message: 'Access denied. Empty Bearer token provided.',
      });
    }

    // Verify token with Firebase Admin SDK
    const decodedToken = await auth.verifyIdToken(idToken);

    // Optional DB User lookup to obtain database role and profile IDs
    let dbUser = null;
    try {
      if (prisma && prisma.user) {
        dbUser = await prisma.user.findUnique({
          where: { firebase_uid: decodedToken.uid },
          include: { patient: true, doctor: true },
        });
      }
    } catch (dbErr) {
      // Non-blocking fallback if DB table isn't populated yet
    }

    // Attach decoded user info to request object
    req.user = {
      uid: decodedToken.uid,
      phone_number: decodedToken.phone_number || dbUser?.phone || null,
      email: decodedToken.email || null,
      role: dbUser?.role || decodedToken.role || 'PATIENT',
      db_id: dbUser?.id || null,
      patient_id: dbUser?.patient?.id || null,
      doctor_id: dbUser?.doctor?.id || null,
      firebase: decodedToken,
    };

    return next();
  } catch (error) {
    console.error('❌ Authentication Middleware Error:', error.message);

    let customMessage = 'Invalid or expired authentication token.';
    if (error.code === 'auth/id-token-expired') {
      customMessage = 'Firebase ID token has expired. Please re-authenticate on the mobile app.';
    } else if (error.code === 'auth/argument-error') {
      customMessage = 'Firebase ID token format is invalid.';
    }

    return res.status(401).json({
      success: false,
      error: 'Unauthorized',
      message: customMessage,
    });
  }
}

module.exports = authenticate;
