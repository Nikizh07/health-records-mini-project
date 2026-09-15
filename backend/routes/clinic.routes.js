// backend/routes/clinic.routes.js
// ============================================================
// Clinic Module Router
// ============================================================
// All routes require a valid Firebase ID token (authenticate).
// POST needs clinic:create; PUT needs clinic:update (own clinic for CLINIC_ADMIN).
// ============================================================

'use strict';

const express    = require('express');
const router     = express.Router();

const authenticate   = require('../middleware/authenticate');
const requirePermission = require('../middleware/requirePermission');
const clinicCtrl     = require('../controllers/clinic.controller');

// Apply authentication to every clinic route
router.use(authenticate);

/**
 * @route   POST /api/clinics
 * @desc    Create a new clinic
 * @access  Private — clinic:create
 */
router.post('/', requirePermission('clinic:create'), clinicCtrl.createClinic);

/**
 * @route   GET /api/clinics
 * @desc    List all clinics
 * @access  Private — Any authenticated user (PATIENT, DOCTOR, ADMIN)
 */
router.get('/', clinicCtrl.getAllClinics);

/**
 * @route   GET /api/clinics/:id
 * @desc    Get a single clinic by UUID
 * @access  Private — Any authenticated user
 */
router.get('/:id', clinicCtrl.getClinicById);

/**
 * @route   PUT /api/clinics/:id
 * @desc    Update clinic info (partial update supported)
 * @access  Private — clinic:update
 */
router.put('/:id', requirePermission('clinic:update'), clinicCtrl.updateClinic);

module.exports = router;
