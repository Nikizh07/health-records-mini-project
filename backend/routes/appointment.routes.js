// backend/routes/appointment.routes.js
// ============================================================
// Appointment Module Router (Day 12)
// ============================================================
// All routes require a valid Firebase ID token (authenticate).
// Role-based restrictions:
//   - POST   /api/appointments          → PATIENT only
//   - GET    /api/appointments/me       → PATIENT only
//   - GET    /api/appointments          → DOCTOR and ADMIN only
//   - PUT    /api/appointments/:id      → PATIENT (own record) or ADMIN
//   - PATCH  /api/appointments/:id/cancel → PATIENT (own record) or ADMIN
// ============================================================

'use strict';

const express = require('express');
const router = express.Router();

const authenticate = require('../middleware/authenticate');
const requireRole = require('../middleware/requireRole');
const appointmentCtrl = require('../controllers/appointment.controller');

// Apply authentication to all appointment routes
router.use(authenticate);

/**
 * @route   POST /api/appointments
 * @desc    Book a new appointment with conflict checking
 *          (DOCTOR/ADMIN: on-the-spot walk-in for body.patient_id)
 * @access  Private — PATIENT, DOCTOR, ADMIN
 */
router.post('/', requireRole('PATIENT', 'DOCTOR', 'ADMIN'), appointmentCtrl.bookAppointment);

/**
 * @route   GET /api/appointments/me
 * @desc    List all appointments of the logged-in patient
 * @access  Private — PATIENT only
 * NOTE: Must be defined before any /:id param route
 */
router.get('/me', requireRole('PATIENT'), appointmentCtrl.getMyAppointments);

/**
 * @route   GET /api/appointments
 * @desc    List appointments for doctors/admins (optional ?doctor_id= query filter)
 * @access  Private — DOCTOR or ADMIN only
 */
router.get('/', requireRole('DOCTOR', 'ADMIN'), appointmentCtrl.getAppointments);

/**
 * @route   PUT /api/appointments/:id
 * @desc    Reschedule an appointment (update slot_time with conflict check)
 * @access  Private — PATIENT (own) or ADMIN
 */
router.put('/:id', requireRole('PATIENT', 'ADMIN'), appointmentCtrl.rescheduleAppointment);

/**
 * @route   PATCH /api/appointments/:id/cancel
 * @desc    Soft-cancel an appointment (sets status='cancelled', frees slot)
 * @access  Private — PATIENT (own) or ADMIN
 */
router.patch('/:id/cancel', requireRole('PATIENT', 'ADMIN'), appointmentCtrl.cancelAppointment);

module.exports = router;
