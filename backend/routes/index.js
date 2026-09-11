// routes/index.js
// Central router — mounts all sub-routers here.
// As you add features (appointments, records), import their routers and mount them below.

'use strict';

const express = require('express');
const router = express.Router();

const healthRouter    = require('./health.routes');
const protectedRouter = require('./protected.routes');
const patientRouter   = require('./patient.routes');
const clinicRouter      = require('./clinic.routes');      // Day 11
const doctorRouter      = require('./doctor.routes');      // Day 11
const appointmentRouter = require('./appointment.routes'); // Day 12
const recordRouter      = require('./record.routes');      // Day 13

// Mount sub-routers
router.use('/health',       healthRouter);
router.use('/protected',    protectedRouter);
router.use('/patients',     patientRouter);
router.use('/clinics',      clinicRouter);      // GET|POST /api/clinics, GET|PUT /api/clinics/:id
router.use('/doctors',      doctorRouter);      // GET|POST /api/doctors, GET|PUT /api/doctors/:id
router.use('/appointments', appointmentRouter); // Day 12: Appointment endpoints
router.use('/records',      recordRouter);      // Day 13: Medical records & prescriptions

module.exports = router;
