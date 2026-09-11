// backend/controllers/clinic.controller.js
// ============================================================
// Clinic Module Controller
// ============================================================
// Handles Clinic creation (POST), listing (GET all), single
// retrieval (GET /:id), and profile updates (PUT /:id).
//
// Access Rules:
//   POST / PUT → ADMIN role only  (enforced in router, not here)
//   GET        → Any authenticated user
// ============================================================

'use strict';

const prisma = require('../config/prisma');

// Reusable UUID format validator — prevents Prisma from throwing a
// type error when a garbage string (e.g. "abc") is used as an ID.
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * @route   POST /api/clinics
 * @desc    Register a new clinic
 * @access  Private — ADMIN only
 */
async function createClinic(req, res, next) {
  try {
    const { name, location, contact_number, latitude, longitude } = req.body;

    // ── Input Validation ─────────────────────────────────────
    if (!name || typeof name !== 'string' || name.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "name" is required and must be at least 2 characters.',
      });
    }

    if (!location || typeof location !== 'string' || location.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "location" is required (e.g. "Block 4, Puchong Industrial Area").',
      });
    }

    if (!contact_number || typeof contact_number !== 'string' || contact_number.trim().length < 5) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "contact_number" is required (e.g. "+60123456789").',
      });
    }

    const parsedLat = latitude !== undefined && latitude !== null ? parseFloat(latitude) : null;
    const parsedLng = longitude !== undefined && longitude !== null ? parseFloat(longitude) : null;

    // ── Database Insert ───────────────────────────────────────
    const clinic = await prisma.clinic.create({
      data: {
        name:           name.trim(),
        location:       location.trim(),
        contact_number: contact_number.trim(),
        latitude:       parsedLat && !isNaN(parsedLat) ? parsedLat : null,
        longitude:      parsedLng && !isNaN(parsedLng) ? parsedLng : null,
      },
    });

    return res.status(201).json({
      success: true,
      message: '🏥 Clinic registered successfully!',
      data: clinic,
    });
  } catch (error) {
    console.error('❌ Error creating clinic:', error.message);
    next(error);
  }
}

/**
 * @route   GET /api/clinics
 * @desc    Retrieve all clinics, ordered by creation date (newest first)
 * @access  Private — Any authenticated user
 */
async function getAllClinics(req, res, next) {
  try {
    const clinics = await prisma.clinic.findMany({
      orderBy: { created_at: 'desc' },
    });

    return res.json({
      success: true,
      count: clinics.length,
      data: clinics,
    });
  } catch (error) {
    console.error('❌ Error fetching clinics:', error.message);
    next(error);
  }
}

/**
 * @route   GET /api/clinics/:id
 * @desc    Retrieve a single clinic by its UUID
 * @access  Private — Any authenticated user
 */
async function getClinicById(req, res, next) {
  try {
    const { id } = req.params;

    // Guard: reject non-UUID IDs early to avoid a Prisma validation error
    if (!UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: `"${id}" is not a valid clinic ID format. Expected a UUID.`,
      });
    }

    const clinic = await prisma.clinic.findUnique({
      where: { id },
      include: {
        // Return the count of doctors at this clinic for context
        _count: { select: { doctors: true } },
      },
    });

    if (!clinic) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Clinic with ID "${id}" not found.`,
      });
    }

    return res.json({
      success: true,
      data: clinic,
    });
  } catch (error) {
    console.error('❌ Error fetching clinic:', error.message);
    next(error);
  }
}

/**
 * @route   PUT /api/clinics/:id
 * @desc    Update clinic information (partial update — only send fields to change)
 * @access  Private — ADMIN only
 */
async function updateClinic(req, res, next) {
  try {
    const { id } = req.params;
    const { name, location, contact_number, latitude, longitude } = req.body;

    if (!UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: `"${id}" is not a valid clinic ID format. Expected a UUID.`,
      });
    }

    // Confirm the clinic exists before attempting an update
    const existing = await prisma.clinic.findUnique({ where: { id } });
    if (!existing) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Clinic with ID "${id}" not found.`,
      });
    }

    // Build update payload dynamically — only include provided fields
    const updateData = {};
    if (name && typeof name === 'string' && name.trim().length >= 2) {
      updateData.name = name.trim();
    }
    if (location && typeof location === 'string' && location.trim().length >= 2) {
      updateData.location = location.trim();
    }
    if (contact_number && typeof contact_number === 'string' && contact_number.trim().length >= 5) {
      updateData.contact_number = contact_number.trim();
    }
    if (latitude !== undefined && latitude !== null) {
      const parsedLat = parseFloat(latitude);
      if (!isNaN(parsedLat)) updateData.latitude = parsedLat;
    }
    if (longitude !== undefined && longitude !== null) {
      const parsedLng = parseFloat(longitude);
      if (!isNaN(parsedLng)) updateData.longitude = parsedLng;
    }

    if (Object.keys(updateData).length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'No valid update fields provided. Allowed fields: name, location, contact_number, latitude, longitude.',
      });
    }

    const updatedClinic = await prisma.clinic.update({
      where: { id },
      data: updateData,
    });

    return res.json({
      success: true,
      message: '✅ Clinic updated successfully.',
      data: updatedClinic,
    });
  } catch (error) {
    console.error('❌ Error updating clinic:', error.message);
    next(error);
  }
}

module.exports = {
  createClinic,
  getAllClinics,
  getClinicById,
  updateClinic,
};
