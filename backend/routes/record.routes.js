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
const { requirePatientAccess, fromParam, fromBody, fromRecord } = require('../middleware/requirePatientAccess');
const recordCtrl = require('../controllers/record.controller');
const patientMessageCtrl = require('../controllers/patientMessage.controller');

// All medical record routes require authentication. Every route that touches
// a patient's records also goes through requirePatientAccess: care link,
// consent or emergency for doctors (logged), or the patient themselves.
router.use(authenticate);

/**
 * @route   POST /api/records
 * @desc    Create a new medical record with nested prescriptions
 * @access  Private — record:write
 */
router.post('/', requirePermission('record:write'), requirePatientAccess('WRITE_RECORD', fromBody), recordCtrl.createMedicalRecord);

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
  requirePatientAccess('INTERACTION_CHECK', fromBody),
  recordCtrl.checkDrugInteractions
);

/**
 * @route   POST /api/records/schedule-parse
 * @desc    Autofill structured dose-schedule chips from the free text the doctor typed
 * @access  Private — record:write
 * @note    Gated by the permission ONLY. It takes no patient_id and reads no
 *          patient data, so it deliberately skips requirePatientAccess —
 *          that is what lets the visit form autofill as the doctor types,
 *          before a patient has even been selected. Declared before '/:id'
 *          so the literal path is not swallowed by the wildcard.
 */
router.post('/schedule-parse', requirePermission('record:write'), recordCtrl.parseDoseSchedules);

/**
 * @route   GET /api/records/patient/:patientId
 * @desc    Get longitudinal medical history for a patient (cross-clinic)
 * @access  Private — self:profile (own) or record:read
 */
router.get(
  '/patient/:patientId',
  requirePermission('self:profile', 'record:read'),
  requirePatientAccess('READ_HISTORY', fromParam('patientId')),
  recordCtrl.getPatientMedicalHistory
);

/**
 * @route   GET /api/records/:id
 * @desc    Get details of a single medical record
 * @access  Private — self:profile (own) or record:read
 */
router.get('/:id', requirePermission('self:profile', 'record:read'), requirePatientAccess('READ_RECORD', fromRecord), recordCtrl.getMedicalRecordById);

/**
 * @route   POST /api/records/:id/upload
 * @desc    Upload a lab report or document to a medical record
 * @access  Private — report:upload
 */
router.post(
  '/:id/upload',
  requirePermission('report:upload'),
  requirePatientAccess('UPLOAD_REPORT', fromRecord), // before multer, so a refused upload never lands on disk
  upload.single('report'),
  recordCtrl.uploadReportFile
);

/**
 * @route   POST /api/records/:id/patient-message/preview
 * @desc    Preview the WhatsApp medication message (script + pictogram) without sending
 * @access  Private — message:send
 * @note    Smart Prescriptions Phase 5: builds the spoken script and dose chart
 *          for doctor review. Nothing is stored or sent. Returns segments with
 *          glosses, chart as data URI, and blockers if any prescription's
 *          schedule is incomplete.
 */
router.post(
  '/:id/patient-message/preview',
  requirePermission('message:send'),
  requirePatientAccess('PREVIEW_MESSAGE', fromRecord),
  patientMessageCtrl.preview
);

/**
 * @route   POST /api/records/:id/patient-message/send
 * @desc    Send WhatsApp medication instructions to the patient
 * @access  Private — message:send
 * @note    Smart Prescriptions Phase 5: synthesizes audio, builds pictogram,
 *          stores assets, sends via messaging provider. Fail-closed: blocks if
 *          whatsapp_opt_in is false, phone is missing/invalid, or any
 *          prescription's schedule is unset.
 */
router.post(
  '/:id/patient-message/send',
  requirePermission('message:send'),
  requirePatientAccess('SEND_MESSAGE', fromRecord),
  patientMessageCtrl.send
);

/**
 * @route   GET /api/records/:id/patient-message
 * @desc    Get the latest patient message status for a medical record
 * @access  Private — message:send or self:profile
 * @note    Returns the most recent PatientMessage row (status, language,
 *          provider, error, timestamps) or null if no message has been sent.
 */
router.get(
  '/:id/patient-message',
  requirePermission('message:send', 'self:profile'),
  requirePatientAccess('READ_MESSAGE_STATUS', fromRecord),
  patientMessageCtrl.getStatus
);

module.exports = router;
