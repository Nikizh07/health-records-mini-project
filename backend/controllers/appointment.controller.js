// backend/controllers/appointment.controller.js
// ============================================================
// Appointment Module Controller (Day 12)
// ============================================================
// Handles:
// 1. POST   /api/appointments          — Patient books appointment (with conflict check)
// 2. GET    /api/appointments/me       — Logged-in patient views own appointments
// 3. GET    /api/appointments          — Doctor / Admin views schedule (optional ?doctor_id=)
// 4. PUT    /api/appointments/:id      — Patient reschedules own appointment (with conflict check)
// 5. PATCH  /api/appointments/:id/cancel — Patient / Admin cancels appointment (soft cancel)
// ============================================================

'use strict';

const prisma = require('../config/prisma');
const { getAuthenticatedDoctorId } = require('./record.controller');

// Reusable UUID validator regex (8-4-4-4-12)
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Standard relational payload to include in responses
const APPOINTMENT_INCLUDE = {
  doctor: {
    select: {
      id: true,
      name: true,
      specialization: true,
      phone: true,
    },
  },
  clinic: {
    select: {
      id: true,
      name: true,
      location: true,
      contact_number: true,
    },
  },
  patient: {
    select: {
      id: true,
      name: true,
      phone: true,
      health_id: true,
      gender: true,
      dob: true,
    },
  },
};

/**
 * Helper: Derives patient ID for the authenticated user.
 * Checks cached req.user.patient_id first, then queries database by firebase_uid.
 */
async function getAuthenticatedPatientId(req) {
  if (req.user?.patient_id) {
    return req.user.patient_id;
  }

  if (!req.user?.uid) {
    return null;
  }

  // 1. Check user record by firebase_uid
  const user = await prisma.user.findUnique({
    where: { firebase_uid: req.user.uid },
    include: { patient: true },
  });

  if (user?.patient) {
    req.user.patient_id = user.patient.id;
    return user.patient.id;
  }

  // No phone fallback: a patient row with a matching phone is not proof it
  // belongs to this account. Only the users → patients link counts.
  return null;
}

/**
 * ------------------------------------------------------------
 * 1. POST /api/appointments
 * ------------------------------------------------------------
 * Patient books a new appointment.
 * - Validates doctor_id, clinic_id, slot_time.
 * - Verifies doctor and clinic exist (and match).
 * - Performs CONFLICT CHECK: Ensures no 'pending' or 'confirmed'
 *   appointment exists for doctor_id + slot_time.
 * - Derives patient_id from authenticated user.
 * ------------------------------------------------------------
 */
async function bookAppointment(req, res, next) {
  try {
    // Gracefully handle both parsed JSON and string body
    let body = req.body || {};
    if (typeof body === 'string') {
      try {
        body = JSON.parse(body);
      } catch (e) {
        body = {};
      }
    }

    let doctor_id = (body.doctor_id || body.doctorID || body.doctorId) ? String(body.doctor_id || body.doctorID || body.doctorId).trim() : null;
    let clinic_id = (body.clinic_id || body.clinicID || body.clinicId) ? String(body.clinic_id || body.clinicID || body.clinicId).trim() : null;
    let slot_time = (body.slot_time || body.slotTime) ? String(body.slot_time || body.slotTime).trim() : null;

    // Staff (DOCTOR/ADMIN) create on-the-spot walk-ins for a given patient:
    // doctor defaults to the caller, clinic to that doctor's clinic, time to now.
    const userRole = (req.user?.role || 'PATIENT').toUpperCase();
    const isStaff = userRole === 'DOCTOR' || userRole === 'ADMIN';

    // ── 1. Resolve Patient ID ────────────────────────────────
    let patient_id;
    if (isStaff) {
      patient_id = body.patient_id ? String(body.patient_id).trim() : null;
      if (!patient_id || !UUID_REGEX.test(patient_id)) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'Field "patient_id" is required and must be a valid UUID.',
        });
      }
      const patientExists = await prisma.patient.findUnique({
        where: { id: patient_id },
        select: { id: true },
      });
      if (!patientExists) {
        return res.status(404).json({
          success: false,
          error: 'Not Found',
          message: `Patient with ID "${patient_id}" does not exist.`,
        });
      }

      doctor_id = doctor_id || await getAuthenticatedDoctorId(req);
      if (doctor_id && !clinic_id && UUID_REGEX.test(doctor_id)) {
        const doc = await prisma.doctor.findUnique({
          where: { id: doctor_id },
          select: { clinic_id: true },
        });
        clinic_id = doc?.clinic_id || null;
      }
      slot_time = slot_time || new Date().toISOString();
    } else {
      patient_id = await getAuthenticatedPatientId(req);

      if (!patient_id) {
        return res.status(404).json({
          success: false,
          error: 'Not Found',
          message: 'Patient profile not found. Please complete patient registration first via POST /api/patients.',
        });
      }
    }

    // ── 2. Validate Input Fields ─────────────────────────────
    if (!doctor_id || !UUID_REGEX.test(doctor_id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "doctor_id" is required and must be a valid UUID.',
      });
    }

    if (!clinic_id || !UUID_REGEX.test(clinic_id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "clinic_id" is required and must be a valid UUID.',
      });
    }

    if (!slot_time || isNaN(Date.parse(slot_time))) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "slot_time" is required and must be a valid ISO 8601 datetime (e.g. 2026-08-25T10:00:00.000Z).',
      });
    }

    const parsedSlotTime = new Date(slot_time);

    // ── 3. Validate Doctor & Clinic Existence ────────────────
    const doctor = await prisma.doctor.findUnique({
      where: { id: doctor_id },
      include: { clinic: true },
    });

    if (!doctor) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Doctor with ID "${doctor_id}" does not exist.`,
      });
    }

    if (doctor.clinic_id !== clinic_id) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: `Doctor "${doctor.name}" is assigned to clinic "${doctor.clinic?.name}" (${doctor.clinic_id}), not clinic "${clinic_id}".`,
      });
    }

    // ── 4. Conflict Check: Doctor Availability ───────────────
    // An existing appointment conflicts only if status is 'pending' or 'confirmed'.
    // Cancelled or completed appointments do NOT block the slot.
    const conflictingAppointment = await prisma.appointment.findFirst({
      where: {
        doctor_id,
        slot_time: parsedSlotTime,
        status: { in: ['pending', 'confirmed'] },
      },
    });

    if (conflictingAppointment) {
      const doctorDisplayName = doctor.name.startsWith('Dr.') ? doctor.name : `Dr. ${doctor.name}`;
      return res.status(409).json({
        success: false,
        error: 'Conflict',
        message: `The selected time slot (${parsedSlotTime.toISOString()}) is already booked for ${doctorDisplayName}. Please select a different time slot or doctor.`,
        conflicting_slot: parsedSlotTime.toISOString(),
      });
    }

    // ── 5. Create the Appointment ────────────────────────────
    const newAppointment = await prisma.appointment.create({
      data: {
        patient_id,
        doctor_id,
        clinic_id,
        slot_time: parsedSlotTime,
        status: isStaff ? 'confirmed' : 'pending', // walk-ins are confirmed on the spot
      },
      include: APPOINTMENT_INCLUDE,
    });

    return res.status(201).json({
      success: true,
      message: 'Appointment booked successfully. Awaiting confirmation.',
      data: newAppointment,
    });
  } catch (error) {
    console.error('❌ Book Appointment Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 2. GET /api/appointments/me
 * ------------------------------------------------------------
 * Fetch all appointments belonging to the logged-in patient.
 * - Supports optional query ?status=pending|confirmed|cancelled|completed
 * - Sorted by slot_time ASC (upcoming first)
 * ------------------------------------------------------------
 */
async function getMyAppointments(req, res, next) {
  try {
    const patient_id = await getAuthenticatedPatientId(req);

    if (!patient_id) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: 'Patient profile not found. Please complete patient registration first via POST /api/patients.',
      });
    }

    const { status } = req.query;

    const whereClause = {
      patient_id,
    };

    if (status) {
      const validStatuses = ['pending', 'confirmed', 'cancelled', 'completed'];
      if (!validStatuses.includes(status.toLowerCase())) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: `Query parameter "status" must be one of: ${validStatuses.join(', ')}.`,
        });
      }
      whereClause.status = status.toLowerCase();
    }

    const appointments = await prisma.appointment.findMany({
      where: whereClause,
      include: APPOINTMENT_INCLUDE,
      orderBy: { slot_time: 'asc' },
    });

    return res.status(200).json({
      success: true,
      count: appointments.length,
      data: appointments,
    });
  } catch (error) {
    console.error('❌ Get My Appointments Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 3. GET /api/appointments
 * ------------------------------------------------------------
 * List appointments for DOCTOR and ADMIN roles.
 * - DOCTOR role: Defaults to viewing their own schedule unless ADMIN.
 * - Supports filters: ?doctor_id=, ?clinic_id=, ?status=, ?date=YYYY-MM-DD
 * ------------------------------------------------------------
 */
async function getAppointments(req, res, next) {
  try {
    const userRole = (req.user?.role || 'PATIENT').toUpperCase();
    const { doctor_id, clinic_id, status, date } = req.query;

    const whereClause = {};

    // Role-based scope
    if (userRole === 'DOCTOR') {
      // A doctor only ever sees their own schedule. No linked profile means
      // no schedule — never "no filter", which would list every appointment.
      if (!req.user.doctor_id) {
        return res.status(403).json({
          success: false,
          error: 'Forbidden',
          message: 'No doctor profile is linked to this account.',
        });
      }
      whereClause.doctor_id = req.user.doctor_id;
    } else if (userRole === 'ADMIN') {
      // Admin can filter by any doctor_id
      if (doctor_id) {
        if (!UUID_REGEX.test(doctor_id)) {
          return res.status(400).json({
            success: false,
            error: 'Bad Request',
            message: 'Query parameter "doctor_id" must be a valid UUID.',
          });
        }
        whereClause.doctor_id = doctor_id;
      }
    }

    if (clinic_id) {
      if (!UUID_REGEX.test(clinic_id)) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'Query parameter "clinic_id" must be a valid UUID.',
        });
      }
      whereClause.clinic_id = clinic_id;
    }

    if (status) {
      const validStatuses = ['pending', 'confirmed', 'cancelled', 'completed'];
      if (!validStatuses.includes(status.toLowerCase())) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: `Query parameter "status" must be one of: ${validStatuses.join(', ')}.`,
        });
      }
      whereClause.status = status.toLowerCase();
    }

    if (date) {
      const startOfDay = new Date(`${date}T00:00:00.000Z`);
      const endOfDay = new Date(`${date}T23:59:59.999Z`);
      if (isNaN(startOfDay.getTime())) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'Query parameter "date" must be a valid date format (YYYY-MM-DD).',
        });
      }
      whereClause.slot_time = {
        gte: startOfDay,
        lte: endOfDay,
      };
    }

    const appointments = await prisma.appointment.findMany({
      where: whereClause,
      include: APPOINTMENT_INCLUDE,
      orderBy: { slot_time: 'asc' },
    });

    return res.status(200).json({
      success: true,
      count: appointments.length,
      data: appointments,
    });
  } catch (error) {
    console.error('❌ Get Appointments Schedule Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 4. PUT /api/appointments/:id
 * ------------------------------------------------------------
 * Patient reschedules their own appointment.
 * - Checks appointment exists and belongs to the logged-in patient.
 * - Checks appointment is not already 'cancelled' or 'completed'.
 * - Runs conflict check for the doctor on the new slot_time (excluding current appointment id).
 * - Updates slot_time and resets status to 'pending'.
 * ------------------------------------------------------------
 */
async function rescheduleAppointment(req, res, next) {
  try {
    const { id } = req.params;
    let body = req.body || {};
    if (typeof body === 'string') {
      try {
        body = JSON.parse(body);
      } catch (e) {
        body = {};
      }
    }
    const slot_time = body.slot_time ? String(body.slot_time).trim() : null;

    if (!id || !UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Appointment ID in URL parameter must be a valid UUID.',
      });
    }

    if (!slot_time || isNaN(Date.parse(slot_time))) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "slot_time" is required and must be a valid ISO 8601 datetime.',
      });
    }

    const parsedNewSlot = new Date(slot_time);

    // ── 1. Fetch Existing Appointment ────────────────────────
    const appointment = await prisma.appointment.findUnique({
      where: { id },
      include: { doctor: true },
    });

    if (!appointment) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Appointment with ID "${id}" does not exist.`,
      });
    }

    // ── 2. Ownership & Status Validation ─────────────────────
    const patient_id = await getAuthenticatedPatientId(req);
    const userRole = (req.user?.role || 'PATIENT').toUpperCase();

    if (userRole !== 'ADMIN' && appointment.patient_id !== patient_id) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden',
        message: 'Access denied. You can only reschedule your own appointments.',
      });
    }

    if (appointment.status === 'cancelled') {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Cannot reschedule a cancelled appointment. Please book a new appointment instead.',
      });
    }

    if (appointment.status === 'completed') {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Cannot reschedule a completed appointment.',
      });
    }

    // ── 3. Conflict Check on New Slot ────────────────────────
    const conflict = await prisma.appointment.findFirst({
      where: {
        doctor_id: appointment.doctor_id,
        slot_time: parsedNewSlot,
        status: { in: ['pending', 'confirmed'] },
        id: { not: appointment.id }, // Exclude current appointment
      },
    });

    if (conflict) {
      const docName = appointment.doctor?.name || 'Doctor';
      const doctorDisplayName = docName.startsWith('Dr.') ? docName : `Dr. ${docName}`;
      return res.status(409).json({
        success: false,
        error: 'Conflict',
        message: `The requested time slot (${parsedNewSlot.toISOString()}) is already booked for ${doctorDisplayName}. Please choose another slot.`,
        conflicting_slot: parsedNewSlot.toISOString(),
      });
    }

    // ── 4. Update Appointment ────────────────────────────────
    const updatedAppointment = await prisma.appointment.update({
      where: { id },
      data: {
        slot_time: parsedNewSlot,
        status: 'pending', // Revert to pending for doctor/clinic confirmation
      },
      include: APPOINTMENT_INCLUDE,
    });

    return res.status(200).json({
      success: true,
      message: 'Appointment rescheduled successfully. Status reset to pending.',
      data: updatedAppointment,
    });
  } catch (error) {
    console.error('❌ Reschedule Appointment Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 5. PATCH /api/appointments/:id/cancel
 * ------------------------------------------------------------
 * Soft-cancels an appointment by setting status = 'cancelled'.
 * - Accessible by the appointment's patient or an ADMIN.
 * - Preserves historical record while immediately freeing up the slot.
 * ------------------------------------------------------------
 */
async function cancelAppointment(req, res, next) {
  try {
    const { id } = req.params;

    if (!id || !UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Appointment ID in URL parameter must be a valid UUID.',
      });
    }

    // ── 1. Fetch Existing Appointment ────────────────────────
    const appointment = await prisma.appointment.findUnique({
      where: { id },
    });

    if (!appointment) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Appointment with ID "${id}" does not exist.`,
      });
    }

    // ── 2. Ownership & Status Validation ─────────────────────
    const patient_id = await getAuthenticatedPatientId(req);
    const userRole = (req.user?.role || 'PATIENT').toUpperCase();

    if (userRole !== 'ADMIN' && appointment.patient_id !== patient_id) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden',
        message: 'Access denied. You can only cancel your own appointments.',
      });
    }

    if (appointment.status === 'cancelled') {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'This appointment is already cancelled.',
      });
    }

    if (appointment.status === 'completed') {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Cannot cancel a completed appointment.',
      });
    }

    // ── 3. Soft Cancel ───────────────────────────────────────
    const cancelledAppointment = await prisma.appointment.update({
      where: { id },
      data: { status: 'cancelled' },
      include: APPOINTMENT_INCLUDE,
    });

    return res.status(200).json({
      success: true,
      message: 'Appointment has been cancelled successfully. Time slot has been freed up.',
      data: cancelledAppointment,
    });
  } catch (error) {
    console.error('❌ Cancel Appointment Error:', error);
    next(error);
  }
}

module.exports = {
  bookAppointment,
  getMyAppointments,
  getAppointments,
  rescheduleAppointment,
  cancelAppointment,
};
