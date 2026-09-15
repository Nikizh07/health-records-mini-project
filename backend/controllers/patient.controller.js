// backend/controllers/patient.controller.js
// ============================================================
// Patient Module Controller
// ============================================================
// Handles Patient Registration (POST), Profile Lookup (GET), and Profile Updates (PUT)
// ============================================================

'use strict';

const prisma = require('../config/prisma');
const { generateUniqueHealthId } = require('../utils/healthId');
const { toE164 } = require('../utils/phone');
const { permissionsFor } = require('../config/permissions');
const { acceptInvite } = require('./staff.controller');

const STAFF_TITLES = {
  ADMIN: 'System Administrator',
  CLINIC_ADMIN: 'Clinic Administrator',
  RECEPTIONIST: 'Receptionist',
};

/**
 * @route   POST /api/patients
 * @desc    Register a new patient profile linked to Firebase Auth UID & phone number
 * @access  Private (Authenticated User)
 */
async function createPatient(req, res, next) {
  try {
    const { name, dob, gender, language_pref } = req.body;

    // 1. Field Validations
    if (!name || typeof name !== 'string' || name.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "name" is required and must be at least 2 characters.',
      });
    }

    if (!dob || isNaN(Date.parse(dob))) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "dob" (Date of Birth) is required and must be a valid date format (e.g. YYYY-MM-DD).',
      });
    }

    if (!gender || !['Male', 'Female', 'Other'].includes(gender)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "gender" is required and must be one of: Male, Female, Other.',
      });
    }

    if (!language_pref || typeof language_pref !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "language_pref" is required (e.g. Bengali, Hindi, English, Tamil, Malayalam).',
      });
    }

    // The phone comes ONLY from the verified Firebase token — never the body,
    // or anyone could register against someone else's number.
    // Guest (anonymous) accounts have no phone; phone is unique + required in the
    // schema, so they get a per-account placeholder. authenticate() already
    // refuses guests in production.
    const isGuest = req.user.sign_in_provider === 'anonymous';
    const userPhone = isGuest ? `guest-${req.user.uid}` : toE164(req.user.phone_number);
    if (!userPhone) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Your account has no verified phone number. Please sign in with your phone number first.',
      });
    }

    // 2. Find or Create database User record
    let user = await prisma.user.findUnique({
      where: { firebase_uid: req.user.uid },
    });

    if (!user) {
      user = await prisma.user.create({
        data: {
          firebase_uid: req.user.uid,
          phone: userPhone,
          role: 'PATIENT',
        },
      });
    }

    // 3. Check if Patient profile already exists for this User or Phone
    const existingPatient = await prisma.patient.findFirst({
      where: {
        OR: [{ user_id: user.id }, { phone: userPhone }],
      },
    });

    if (existingPatient) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'A patient profile is already registered for this user account / phone number.',
        patient_id: existingPatient.id,
        health_id: existingPatient.health_id,
      });
    }

    // 4. Generate system-wide unique Health ID (MWH-XXXXXX)
    const health_id = await generateUniqueHealthId(prisma);

    // 5. Create Patient record in PostgreSQL
    const newPatient = await prisma.patient.create({
      data: {
        user_id: user.id,
        health_id,
        name: name.trim(),
        phone: userPhone,
        dob: new Date(dob),
        gender,
        language_pref: language_pref.trim(),
      },
      include: {
        user: {
          select: { id: true, firebase_uid: true, role: true },
        },
      },
    });

    return res.status(201).json({
      success: true,
      message: '🎉 Patient profile registered successfully!',
      // Same access fields as GET /patients/me: the app keeps this as the profile.
      data: { ...newPatient, permissions: permissionsFor(user.role, user.status), status: user.status, clinic: null },
    });
  } catch (error) {
    console.error('❌ Error creating patient:', error.message);
    next(error);
  }
}

/**
 * Where an account without a profile goes next: phone (or debug guest) sign-ins
 * register as patients; email sign-ins verify their email, then apply as staff.
 */
function nextStep(authUser) {
  if (authUser.phone_number || authUser.sign_in_provider === 'anonymous') return 'REGISTER';
  if (!authUser.email_verified) return 'VERIFY_EMAIL';
  return 'STAFF_APPLY';
}

/**
 * @route   GET /api/patients/me
 * @desc    Fetch profile of currently authenticated patient
 * @access  Private (Self)
 */
async function getMyProfile(req, res, next) {
  try {
    const include = { patient: true, clinic: true, doctor: { include: { clinic: true } } };
    let user = await prisma.user.findUnique({
      where: { firebase_uid: req.user.uid },
      include,
    });

    // First sign-in of invited staff: accept a matching invite (verified
    // email or phone only). This is the only way a staff account is linked.
    if (!user) {
      user = await acceptInvite(req, include);
    }

    // `next` tells the app where to send an account with no profile yet.
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: 'User account not registered yet. Please register first.',
        next: nextStep(req.user),
      });
    }

    // Every role gets its permissions, status and clinic, so the app gates by
    // permission. Computed from this row: a just-linked doctor has no req.user role.
    const access = {
      permissions: permissionsFor(user.role, user.status),
      status: user.status,
      clinic: user.doctor?.clinic ?? user.clinic ?? null,
    };
    const userInfo = {
      id: user.id,
      firebase_uid: user.firebase_uid,
      role: user.role,
      phone: user.phone,
    };

    if (user.role === 'PATIENT') {
      if (!user.patient) {
        return res.status(404).json({
          success: false,
          error: 'Not Found',
          message: 'Patient profile not registered yet for this account. Please register first via POST /api/patients.',
          next: 'REGISTER',
        });
      }
      return res.json({ success: true, data: { ...user.patient, ...access, user: userInfo } });
    }

    if (user.role === 'DOCTOR') {
      return res.json({
        success: true,
        data: {
          ...(user.doctor || {
            name: user.phone ? `Doctor (${user.phone})` : 'Medical Doctor',
            specialization: 'General Practitioner',
          }),
          ...access,
          user: userInfo,
        },
      });
    }

    // ADMIN, CLINIC_ADMIN, RECEPTIONIST
    return res.json({
      success: true,
      data: { name: STAFF_TITLES[user.role], role: user.role, ...access, user: userInfo },
    });
  } catch (error) {
    console.error('❌ Error fetching own profile:', error.message);
    next(error);
  }
}

/**
 * @route   GET /api/patients/:id
 * @desc    Fetch single patient profile by ID
 * @access  Private (Self-Access or patient:lookup)
 */
async function getPatientById(req, res, next) {
  try {
    const patientId = req.params.id;

    if (!patientId) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Patient ID parameter is required.',
      });
    }

    const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    let patient = null;

    if (UUID_REGEX.test(patientId)) {
      patient = await prisma.patient.findUnique({
        where: { id: patientId },
        include: {
          user: {
            select: { id: true, firebase_uid: true, role: true, phone: true },
          },
        },
      });
    } else {
      patient = await prisma.patient.findUnique({
        where: { health_id: patientId },
        include: {
          user: {
            select: { id: true, firebase_uid: true, role: true, phone: true },
          },
        },
      });
    }

    if (!patient) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Patient profile with ID "${patientId}" not found.`,
      });
    }

    return res.json({
      success: true,
      data: patient,
    });
  } catch (error) {
    console.error('❌ Error fetching patient:', error.message);
    next(error);
  }
}

/**
 * @route   PUT /api/patients/:id
 * @desc    Update allowed profile fields for a patient (name, dob, gender, language_pref)
 * @access  Private (Self-Access or patient:lookup)
 */
async function updatePatient(req, res, next) {
  try {
    const patientId = req.params.id;
    const { name, dob, gender, language_pref } = req.body;

    if (!patientId) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Patient ID parameter is required.',
      });
    }

    const existingPatient = await prisma.patient.findUnique({
      where: { id: patientId },
    });

    if (!existingPatient) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Patient profile with ID "${patientId}" not found.`,
      });
    }

    // Build update payload dynamically
    const updateData = {};
    if (name && typeof name === 'string' && name.trim().length >= 2) {
      updateData.name = name.trim();
    }
    if (dob && !isNaN(Date.parse(dob))) {
      updateData.dob = new Date(dob);
    }
    if (gender && ['Male', 'Female', 'Other'].includes(gender)) {
      updateData.gender = gender;
    }
    if (language_pref && typeof language_pref === 'string') {
      updateData.language_pref = language_pref.trim();
    }

    if (Object.keys(updateData).length === 0) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'No valid update fields provided. Allowed fields: name, dob, gender, language_pref.',
      });
    }

    const updatedPatient = await prisma.patient.update({
      where: { id: patientId },
      data: updateData,
      include: {
        user: {
          select: { id: true, firebase_uid: true, role: true },
        },
      },
    });

    return res.json({
      success: true,
      message: '✅ Patient profile updated successfully.',
      data: updatedPatient,
    });
  } catch (error) {
    console.error('❌ Error updating patient:', error.message);
    next(error);
  }
}

/**
 * @route   GET /api/patients/search?q=<query>
 * @desc    Search patients by name or Health ID (partial, case-insensitive)
 * @access  Private — patient:lookup
 */
async function searchPatients(req, res, next) {
  try {
    const q = (req.query.q || '').toString().trim();

    if (q.length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Query parameter "q" must be at least 2 characters long.',
      });
    }

    const patients = await prisma.patient.findMany({
      where: {
        OR: [
          { name:      { contains: q, mode: 'insensitive' } },
          { health_id: { contains: q, mode: 'insensitive' } },
        ],
      },
      select: {
        id:        true,
        name:      true,
        health_id: true,
        phone:     true,
        gender:    true,
        dob:       true,
      },
      orderBy: { name: 'asc' },
      take: 10,
    });

    return res.json({
      success: true,
      count: patients.length,
      data: patients,
    });
  } catch (error) {
    console.error('❌ Error searching patients:', error.message);
    next(error);
  }
}

module.exports = {
  createPatient,
  getMyProfile,
  getPatientById,
  updatePatient,
  searchPatients,
};
