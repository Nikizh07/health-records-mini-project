// backend/routes/doctor.routes.js
// ============================================================
// Doctor Module Router
// ============================================================
// All routes require a valid Firebase ID token (authenticate).
// Write operations (POST / PUT) additionally require ADMIN role.
// ============================================================

'use strict';

const express   = require('express');
const router    = express.Router();

const authenticate = require('../middleware/authenticate');
const requireRole  = require('../middleware/requireRole');
const doctorCtrl   = require('../controllers/doctor.controller');

// Apply authentication to every doctor route
router.use(authenticate);

/**
 * @route   POST /api/doctors
 * @desc    Create a new doctor linked to a clinic
 * @access  Private — ADMIN only
 */
router.post('/', requireRole('ADMIN'), doctorCtrl.createDoctor);

/**
 * @route   GET /api/doctors
 * @route   GET /api/doctors?clinic_id=<uuid>
 * @desc    List all doctors (or filter by clinic)
 * @access  Private — Any authenticated user (PATIENT, DOCTOR, ADMIN)
 */
router.get('/', doctorCtrl.getAllDoctors);

/**
 * @route   GET /api/doctors/:id
 * @desc    Get a single doctor by UUID
 * @access  Private — Any authenticated user
 */
router.get('/:id', doctorCtrl.getDoctorById);

/**
 * @route   PUT /api/doctors/:id
 * @desc    Update doctor info (partial update supported)
 * @access  Private — ADMIN only
 */
router.put('/:id', requireRole('ADMIN'), doctorCtrl.updateDoctor);

module.exports = router;
