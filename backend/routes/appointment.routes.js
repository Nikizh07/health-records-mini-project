// backend/routes/appointment.routes.js
// ============================================================
// Appointment Module Router (Day 12)
// ============================================================
// All routes require a valid Firebase ID token (authenticate).
// Permissions (config/permissions.js); scope is checked in the controller:
//   - POST   /api/appointments          → self:profile (book) or appointment:manage (walk-in)
//   - GET    /api/appointments/me       → self:profile
//   - GET    /api/appointments          → appointment:manage
//   - PUT    /api/appointments/:id      → self:profile (own) or appointment:manage (scoped)
//   - PATCH  /api/appointments/:id/cancel → self:profile (own) or appointment:manage (scoped)
//   - PATCH  /api/appointments/:id/confirm → appointment:manage (scoped)
// ============================================================

'use strict';

const express = require('express');
const router = express.Router();

const authenticate = require('../middleware/authenticate');
const requirePermission = require('../middleware/requirePermission');
const appointmentCtrl = require('../controllers/appointment.controller');

// Apply authentication to all appointment routes
router.use(authenticate);

/**
 * @route   POST /api/appointments
 * @desc    Book a new appointment with conflict checking
 *          (appointment:manage: on-the-spot walk-in for body.patient_id)
 * @access  Private — self:profile or appointment:manage
 */
router.post('/', requirePermission('self:profile', 'appointment:manage'), appointmentCtrl.bookAppointment);

/**
 * @route   GET /api/appointments/me
 * @desc    List all appointments of the logged-in patient
 * @access  Private — self:profile
 * NOTE: Must be defined before any /:id param route
 */
router.get('/me', requirePermission('self:profile'), appointmentCtrl.getMyAppointments);

/**
 * @route   GET /api/appointments
 * @desc    List appointments for doctors/admins (optional ?doctor_id= query filter)
 * @access  Private — appointment:manage (own schedule / own clinic)
 */
router.get('/', requirePermission('appointment:manage'), appointmentCtrl.getAppointments);

/**
 * @route   PUT /api/appointments/:id
 * @desc    Reschedule an appointment (update slot_time with conflict check)
 * @access  Private — self:profile (own) or appointment:manage (scoped)
 */
router.put('/:id', requirePermission('self:profile', 'appointment:manage'), appointmentCtrl.rescheduleAppointment);

/**
 * @route   PATCH /api/appointments/:id/cancel
 * @desc    Soft-cancel an appointment (sets status='cancelled', frees slot)
 * @access  Private — self:profile (own) or appointment:manage (scoped)
 */
router.patch('/:id/cancel', requirePermission('self:profile', 'appointment:manage'), appointmentCtrl.cancelAppointment);

/**
 * @route   PATCH /api/appointments/:id/confirm
 * @desc    Confirm a pending appointment (pending → confirmed)
 * @access  Private — appointment:manage (scoped)
 */
router.patch('/:id/confirm', requirePermission('appointment:manage'), appointmentCtrl.confirmAppointment);

module.exports = router;
