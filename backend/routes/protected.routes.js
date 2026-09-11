// backend/routes/protected.routes.js
// ============================================================
// Protected Test Routes (Authentication & RBAC Verification)
// ============================================================

'use strict';

const express = require('express');
const router = express.Router();

const authenticate = require('../middleware/authenticate');
const requireRole = require('../middleware/requireRole');

/**
 * @route   GET /api/protected
 * @desc    Test endpoint requiring a valid Firebase ID Token (Any authenticated user)
 * @access  Private
 */
router.get('/', authenticate, (req, res) => {
  res.json({
    success: true,
    message: '🎉 Access Granted! Your Firebase ID token was successfully verified by Firebase Admin SDK.',
    timestamp: new Date().toISOString(),
    authenticated_user: {
      uid: req.user.uid,
      phone_number: req.user.phone_number,
      email: req.user.email,
      role: req.user.role,
      db_user_id: req.user.db_id,
      patient_id: req.user.patient_id,
      doctor_id: req.user.doctor_id,
    },
  });
});

/**
 * @route   GET /api/protected/doctor-only
 * @desc    Test endpoint requiring DOCTOR or ADMIN role
 * @access  Private (DOCTOR, ADMIN)
 */
router.get('/doctor-only', authenticate, requireRole('DOCTOR', 'ADMIN'), (req, res) => {
  res.json({
    success: true,
    message: '👨‍⚕️ Access Granted! You are authorized as a DOCTOR or ADMIN.',
    timestamp: new Date().toISOString(),
    authenticated_user: {
      uid: req.user.uid,
      phone_number: req.user.phone_number,
      role: req.user.role,
    },
  });
});

module.exports = router;
