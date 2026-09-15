// backend/routes/record.routes.js
// ============================================================
// Medical Records & Prescriptions Router (Day 13)
// ============================================================

'use strict';

const express = require('express');
const router = express.Router();

const authenticate = require('../middleware/authenticate');
const requirePermission = require('../middleware/requirePermission');
const upload = require('../middleware/upload');
const recordCtrl = require('../controllers/record.controller');

// All medical record routes require authentication
router.use(authenticate);

/**
 * @route   POST /api/records
 * @desc    Create a new medical record with nested prescriptions
 * @access  Private — record:write
 */
router.post('/', requirePermission('record:write'), recordCtrl.createMedicalRecord);

/**
 * @route   POST /api/records/interaction-check
 * @desc    Pre-flight cross-clinic drug interaction check for pending prescriptions
 * @access  Private — interaction:check
 * @note    Declared before the '/:id' routes so the literal path is not
 *          swallowed by the wildcard, matching the convention in
 *          patient.routes.js and appointment.routes.js.
 */
router.post(
  '/interaction-check',
  requirePermission('interaction:check'),
  recordCtrl.checkDrugInteractions
);

/**
 * @route   GET /api/records/patient/:patientId
 * @desc    Get longitudinal medical history for a patient (cross-clinic)
 * @access  Private — self:profile (own) or record:read
 */
router.get('/patient/:patientId', requirePermission('self:profile', 'record:read'), recordCtrl.getPatientMedicalHistory);

/**
 * @route   GET /api/records/:id
 * @desc    Get details of a single medical record
 * @access  Private — self:profile (own) or record:read
 */
router.get('/:id', requirePermission('self:profile', 'record:read'), recordCtrl.getMedicalRecordById);

/**
 * @route   POST /api/records/:id/upload
 * @desc    Upload a lab report or document to a medical record
 * @access  Private — report:upload
 */
router.post(
  '/:id/upload',
  requirePermission('report:upload'),
  upload.single('report'),
  recordCtrl.uploadReportFile
);

module.exports = router;
