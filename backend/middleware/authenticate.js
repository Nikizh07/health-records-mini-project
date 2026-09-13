// backend/middleware/authenticate.js
// ============================================================
// Firebase Authentication Middleware
// ============================================================
// 1. Reads the Authorization header ("Bearer <token>")
// 2. Verifies the Firebase ID Token via Firebase Admin SDK → 401 if invalid
// 3. Refuses anonymous (guest) tokens in production → 401
// 4. Looks up the database user; the DB is the ONLY source of the role.
//    A signed-in Firebase user with no users row has role null, so every
//    role-gated route answers 403 until they register.
// 5. Attaches user details to `req.user`
//
// A database failure is passed to the error handler (500), not reported as
// 401: the app ends the session on 401/403, and a DB outage must not log
// everyone out.
// ============================================================

'use strict';

const { auth } = require('../config/firebase');
const prisma = require('../config/prisma');

async function authenticate(req, res, next) {
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

  let decodedToken;
  try {
    decodedToken = await auth.verifyIdToken(idToken);
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

  const signInProvider = decodedToken.firebase?.sign_in_provider || null;
  if (signInProvider === 'anonymous' && process.env.NODE_ENV === 'production') {
    return res.status(401).json({
      success: false,
      error: 'Unauthorized',
      message: 'Guest sign-in is not available. Please sign in with your phone number.',
    });
  }

  try {
    const dbUser = await prisma.user.findUnique({
      where: { firebase_uid: decodedToken.uid },
      include: { patient: true, doctor: true },
    });

    req.user = {
      uid: decodedToken.uid,
      phone_number: decodedToken.phone_number || null,
      email: decodedToken.email || null,
      email_verified: decodedToken.email_verified === true,
      sign_in_provider: signInProvider,
      role: dbUser?.role || null,
      db_id: dbUser?.id || null,
      patient_id: dbUser?.patient?.id || null,
      doctor_id: dbUser?.doctor?.id || null,
      firebase: decodedToken,
    };

    return next();
  } catch (error) {
    return next(error);
  }
}

module.exports = authenticate;
