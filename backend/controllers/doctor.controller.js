// backend/controllers/doctor.controller.js
// ============================================================
// Doctor Module Controller
// ============================================================
// Handles Doctor creation (POST), listing with optional filter
// (GET all), single retrieval (GET /:id), and profile updates
// (PUT /:id).
//
// Access Rules:
//   POST / PUT → ADMIN role only  (enforced in router, not here)
//   GET        → Any authenticated user
// ============================================================

'use strict';

const prisma = require('../config/prisma');

// Reusable UUID format validator
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Fields to include when returning a doctor — always show the
// clinic name & location so the client doesn't need a second call.
const DOCTOR_INCLUDE = {
  clinic: {
    select: { id: true, name: true, location: true },
  },
};

/**
 * @route   POST /api/doctors
 * @desc    Register a new doctor linked to an existing clinic
 * @access  Private — ADMIN only
 */
async function createDoctor(req, res, next) {
  try {
    const { name, clinic_id, specialization, phone } = req.body;

    // ── Input Validation ─────────────────────────────────────
    if (!name || typeof name !== 'string' || name.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "name" is required and must be at least 2 characters.',
      });
    }

    if (!clinic_id || !UUID_REGEX.test(clinic_id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "clinic_id" is required and must be a valid UUID.',
      });
    }

    if (!specialization || typeof specialization !== 'string' || specialization.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "specialization" is required (e.g. "General Practice", "Dermatology").',
      });
    }

    if (!phone || typeof phone !== 'string' || phone.trim().length < 5) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "phone" is required (e.g. "+60123456789").',
      });
    }

    // ── Clinic Existence Check ────────────────────────────────
    // We verify the referenced clinic exists BEFORE inserting.
    // This gives a clean 404 instead of a raw DB foreign key error.
    const clinic = await prisma.clinic.findUnique({ where: { id: clinic_id } });
    if (!clinic) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Clinic with ID "${clinic_id}" not found. Create the clinic first via POST /api/clinics.`,
      });
    }

    // ── Database Insert ───────────────────────────────────────
    const doctor = await prisma.doctor.create({
      data: {
        clinic_id,
        name:           name.trim(),
        specialization: specialization.trim(),
        phone:          phone.trim(),
      },
      include: DOCTOR_INCLUDE,
    });

    return res.status(201).json({
      success: true,
      message: '👨‍⚕️ Doctor registered successfully!',
      data: doctor,
    });
  } catch (error) {
    // Handle unique-phone constraint violation gracefully
    if (error.code === 'P2002' && error.meta?.target?.includes('phone')) {
      return res.status(400).json({
        success: false,
        error: 'Conflict',
        message: `Phone number "${req.body.phone}" is already registered to another doctor.`,
      });
    }
    console.error('❌ Error creating doctor:', error.message);
    next(error);
  }
}

/**
 * @route   GET /api/doctors
 * @route   GET /api/doctors?clinic_id=<uuid>
 * @desc    List all doctors. Optionally filter by clinic using ?clinic_id= query param.
 * @access  Private — Any authenticated user
 */
async function getAllDoctors(req, res, next) {
  try {
    const { clinic_id } = req.query;

    // Build where clause dynamically
    // If clinic_id is provided AND looks like a UUID, filter by it.
    // Otherwise, return all doctors (no where clause = no filter).
    const where = {};
    if (clinic_id) {
      if (!UUID_REGEX.test(clinic_id)) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: `Query param "clinic_id" must be a valid UUID. Received: "${clinic_id}".`,
        });
      }
      where.clinic_id = clinic_id;
    }

    const doctors = await prisma.doctor.findMany({
      where,
      include:  DOCTOR_INCLUDE,
      orderBy: { created_at: 'desc' },
    });

    return res.json({
      success: true,
      count: doctors.length,
      // Let the client know which filter was applied (helpful for debugging)
      filter: clinic_id ? { clinic_id } : null,
      data: doctors,
    });
  } catch (error) {
    console.error('❌ Error fetching doctors:', error.message);
    next(error);
  }
}

/**
 * @route   GET /api/doctors/:id
 * @desc    Retrieve a single doctor by their UUID
 * @access  Private — Any authenticated user
 */
async function getDoctorById(req, res, next) {
  try {
    const { id } = req.params;

    if (!UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: `"${id}" is not a valid doctor ID format. Expected a UUID.`,
      });
    }

    const doctor = await prisma.doctor.findUnique({
      where: { id },
      include: DOCTOR_INCLUDE,
    });

    if (!doctor) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Doctor with ID "${id}" not found.`,
      });
    }

    return res.json({
      success: true,
      data: doctor,
    });
  } catch (error) {
    console.error('❌ Error fetching doctor:', error.message);
    next(error);
  }
}

/**
 * @route   PUT /api/doctors/:id
 * @desc    Update doctor information (partial update — only send fields to change)
 * @access  Private — ADMIN only
 */
async function updateDoctor(req, res, next) {
  try {
    const { id } = req.params;
    const { name, clinic_id, specialization, phone } = req.body;

    if (!UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: `"${id}" is not a valid doctor ID format. Expected a UUID.`,
      });
    }

    // Confirm the doctor exists
    const existing = await prisma.doctor.findUnique({ where: { id } });
    if (!existing) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Doctor with ID "${id}" not found.`,
      });
    }

    // Build update payload dynamically
    const updateData = {};

    if (name && typeof name === 'string' && name.trim().length >= 2) {
      updateData.name = name.trim();
    }
    if (specialization && typeof specialization === 'string' && specialization.trim().length >= 2) {
      updateData.specialization = specialization.trim();
    }
    if (phone && typeof phone === 'string' && phone.trim().length >= 5) {
      updateData.phone = phone.trim();
    }

    // If clinic_id is being changed, verify the new clinic exists first
    if (clinic_id) {
      if (!UUID_REGEX.test(clinic_id)) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'Field "clinic_id" must be a valid UUID.',
        });
      }
      const clinic = await prisma.clinic.findUnique({ where: { id: clinic_id } });
      if (!clinic) {
        return res.status(404).json({
          success: false,
          error: 'Not Found',
          message: `Clinic with ID "${clinic_id}" not found.`,
        });
      }
      updateData.clinic_id = clinic_id;
    }

    if (Object.keys(updateData).length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'No valid update fields provided. Allowed fields: name, clinic_id, specialization, phone.',
      });
    }

    const updatedDoctor = await prisma.doctor.update({
      where: { id },
      data: updateData,
      include: DOCTOR_INCLUDE,
    });

    return res.json({
      success: true,
      message: '✅ Doctor profile updated successfully.',
      data: updatedDoctor,
    });
  } catch (error) {
    // Handle unique-phone constraint violation gracefully
    if (error.code === 'P2002' && error.meta?.target?.includes('phone')) {
      return res.status(400).json({
        success: false,
        error: 'Conflict',
        message: `Phone number "${req.body.phone}" is already registered to another doctor.`,
      });
    }
    console.error('❌ Error updating doctor:', error.message);
    next(error);
  }
}

module.exports = {
  createDoctor,
  getAllDoctors,
  getDoctorById,
  updateDoctor,
};
