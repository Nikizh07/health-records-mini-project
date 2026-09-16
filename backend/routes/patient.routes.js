// backend/routes/patient.routes.js
// ============================================================
// Patient Module Router
// ============================================================

'use strict';

const express = require('express');
const router = express.Router();

const authenticate = require('../middleware/authenticate');
const authorizePatientAccess = require('../middleware/authorizePatientAccess');
const requirePermission = require('../middleware/requirePermission');
const patientController = require('../controllers/patient.controller');


// All patient routes require a valid Firebase ID token
router.use(authenticate);

/**
 * @route   POST /api/patients
 * @desc    Register a new patient profile
 * @access  Private (Authenticated users)
 */
router.post('/', patientController.createPatient);

/**
 * @route   POST /api/patients/register
 * @desc    Staff register a walk-in patient with no account (claimed later)
 * @access  Private — patient:register
 */
router.post('/register', requirePermission('patient:register'), patientController.registerPatientAtDesk);

/**
 * @route   POST /api/patients/claim
 * @desc    Link a desk-registered profile to this phone sign-in, by date of birth
 * @access  Private (Authenticated, verified phone)
 */
router.post('/claim', patientController.claimPatient);

/**
 * @route   GET /api/patients/me
 * @desc    Fetch profile of currently authenticated patient
 * @access  Private (Self)
 */
router.get('/me', patientController.getMyProfile);

/**
 * @route   GET /api/patients/search?q=<query>
 * @desc    Search patients by partial name or Health ID
 * @access  Private — patient:lookup
 *
 * IMPORTANT: This route MUST be declared before GET /:id
 * because Express matches routes sequentially — without this ordering,
 * the /:id wildcard would capture the literal string "search" as an id.
 */
router.get('/search', requirePermission('patient:lookup'), patientController.searchPatients);

/**
 * @route   GET /api/patients/lookup?health_id=|phone=
 * @desc    Exact lookup: demographics, masked phone, access { allowed, via }
 * @access  Private — patient:lookup
 */
router.get('/lookup', requirePermission('patient:lookup'), patientController.lookupPatient);

/**
 * @route   GET /api/patients/:id
 * @desc    Fetch single patient profile by ID
 * @access  Private (Self or patient:lookup)
 */
router.get('/:id', authorizePatientAccess, patientController.getPatientById);

/**
 * @route   PUT /api/patients/:id
 * @desc    Update single patient profile
 * @access  Private (Self or patient:lookup)
 */
router.put('/:id', authorizePatientAccess, patientController.updatePatient);

module.exports = router;
