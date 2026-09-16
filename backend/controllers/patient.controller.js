// backend/controllers/patient.controller.js
// ============================================================
// Patient Module Controller
// ============================================================
// Handles Patient Registration (POST), Profile Lookup (GET), and Profile Updates (PUT)
// ============================================================

'use strict';

const { STATUS_CODES } = require('http');
const prisma = require('../config/prisma');
const { generateUniqueHealthId } = require('../utils/healthId');
const { toE164 } = require('../utils/phone');
const { permissionsFor } = require('../config/permissions');
const { acceptInvite } = require('./staff.controller');
const { resolveAccess } = require('../services/patientAccess');

const STAFF_TITLES = {
  ADMIN: 'System Administrator',
  CLINIC_ADMIN: 'Clinic Administrator',
  RECEPTIONIST: 'Receptionist',
};

/** The patient form shared by self and desk registration; returns an error message or null. */
function formError(body = {}) {
  const { name, dob, gender, language_pref } = body;
  if (!name || typeof name !== 'string' || name.trim().length < 2) {
    return 'Field "name" is required and must be at least 2 characters.';
  }
  if (!dob || isNaN(Date.parse(dob))) {
    return 'Field "dob" (Date of Birth) is required and must be a valid date format (e.g. YYYY-MM-DD).';
  }
  if (!gender || !['Male', 'Female', 'Other'].includes(gender)) {
    return 'Field "gender" is required and must be one of: Male, Female, Other.';
  }
  if (!language_pref || typeof language_pref !== 'string') {
    return 'Field "language_pref" is required (e.g. Bengali, Hindi, English, Tamil, Malayalam).';
  }
  return null;
}

const profileOf = (patient, user) => ({
  ...patient,
  permissions: permissionsFor(user.role, user.status),
  status: user.status,
  clinic: null,
});

/**
 * @route   POST /api/patients
 * @desc    Register a new patient profile linked to Firebase Auth UID & phone number
 * @access  Private (Authenticated User)
 */
async function createPatient(req, res, next) {
  try {
    const { name, dob, gender, language_pref } = req.body;
    const invalid = formError(req.body);
    if (invalid) {
      return res.status(400).json({ success: false, error: 'Bad Request', message: invalid });
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

    // Staff register other people through POST /patients/register.
    if (user && user.role !== 'PATIENT') {
      return res.status(403).json({
        success: false,
        error: 'Forbidden',
        message: 'Staff accounts cannot have a patient profile.',
      });
    }

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
      data: profileOf(newPatient, user),
    });
  } catch (error) {
    console.error('❌ Error creating patient:', error.message);
    next(error);
  }
}

/**
 * @route   POST /api/patients/register
 * @desc    Staff register a walk-in patient who has no account (user_id null).
 *          The patient claims it later: phone OTP on that number + date of birth.
 * @access  Private — patient:register
 */
async function registerPatientAtDesk(req, res, next) {
  try {
    const body = req.body || {};
    const invalid = formError(body);
    if (invalid) return res.status(400).json({ success: false, error: 'Bad Request', message: invalid });
    const phone = toE164(body.phone);
    if (!phone) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "phone" is required (10-digit Indian mobile, or with its country code).',
      });
    }

    const existing = await prisma.patient.findUnique({ where: { phone }, select: { id: true, health_id: true, name: true } });
    if (existing) {
      return res.status(409).json({
        success: false,
        error: 'Conflict',
        message: `A patient is already registered with this phone (${existing.health_id}).`,
        data: existing,
      });
    }

    const patient = await prisma.patient.create({
      data: {
        health_id: await generateUniqueHealthId(prisma),
        name: body.name.trim(),
        phone,
        dob: new Date(body.dob),
        gender: body.gender,
        language_pref: body.language_pref.trim(),
        registered_by_user_id: req.user.db_id,
      },
    });
    return res.status(201).json({ success: true, message: 'Patient registered.', data: patient });
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(409).json({ success: false, error: 'Conflict', message: 'A patient is already registered with this phone.' });
    }
    next(error);
  }
}

const CLAIM_MAX_FAILURES = 5;
const CLAIM_LOCK_MS = 24 * 60 * 60 * 1000;

/** A desk-registered profile (no account yet) waiting on this verified phone. */
async function claimablePatient(phoneNumber) {
  const phone = toE164(phoneNumber);
  if (!phone) return null;
  const patient = await prisma.patient.findUnique({ where: { phone } });
  return patient && !patient.user_id ? patient : null;
}

/**
 * @route   POST /api/patients/claim  { dob: "YYYY-MM-DD" }
 * @desc    Link a desk-registered profile to the signed-in account. The token
 *          phone proves the number; the date of birth stops a mistyped number
 *          from handing someone's history to whoever owns it.
 *          5 wrong dates lock the claim for 24 hours.
 * @access  Private — phone sign-in with no patient profile
 */
async function claimPatient(req, res, next) {
  const fail = (status, message, extra = {}) =>
    res.status(status).json({ success: false, error: STATUS_CODES[status], message, ...extra });
  try {
    const dob = String(req.body?.dob || '');
    if (!/^\d{4}-\d{2}-\d{2}$/.test(dob) || isNaN(Date.parse(dob))) {
      return fail(400, 'Field "dob" is required as YYYY-MM-DD.');
    }

    const existingUser = await prisma.user.findUnique({ where: { firebase_uid: req.user.uid }, include: { patient: true } });
    if (existingUser && (existingUser.role !== 'PATIENT' || existingUser.patient)) {
      return fail(409, 'This account already has a profile.');
    }

    const patient = await claimablePatient(req.user.phone_number);
    if (!patient) return fail(404, 'No clinic-registered profile is waiting for this phone number.');

    // Take one attempt atomically, so parallel guesses can't beat the limit.
    const now = new Date();
    const taken = await prisma.patient.updateMany({
      where: {
        id: patient.id,
        user_id: null,
        claim_failures: { lt: CLAIM_MAX_FAILURES },
        OR: [{ claim_locked_until: null }, { claim_locked_until: { lt: now } }],
      },
      data: { claim_failures: { increment: 1 } },
    });
    if (taken.count === 0) {
      return fail(423, 'Too many wrong dates of birth. Try again in 24 hours, or ask the clinic.');
    }

    if (patient.dob.toISOString().slice(0, 10) !== dob) {
      const after = await prisma.patient.findUnique({ where: { id: patient.id } });
      const left = CLAIM_MAX_FAILURES - after.claim_failures;
      if (left <= 0) {
        await prisma.patient.update({
          where: { id: patient.id },
          data: { claim_failures: 0, claim_locked_until: new Date(Date.now() + CLAIM_LOCK_MS) },
        });
        return fail(423, 'Too many wrong dates of birth. Try again in 24 hours, or ask the clinic.');
      }
      return fail(403, `The date of birth does not match. ${left} attempt${left === 1 ? '' : 's'} left.`, { attempts_left: left });
    }

    const { user, linked } = await prisma.$transaction(async (tx) => {
      const user = existingUser ?? await tx.user.create({
        data: { firebase_uid: req.user.uid, phone: patient.phone, role: 'PATIENT' },
      });
      const claimed = await tx.patient.updateMany({
        where: { id: patient.id, user_id: null },
        data: { user_id: user.id, claim_failures: 0, claim_locked_until: null },
      });
      if (claimed.count !== 1) throw Object.assign(new Error('Profile was already claimed.'), { code: 'P2002' });
      return { user, linked: await tx.patient.findUnique({ where: { id: patient.id } }) };
    });

    return res.json({ success: true, message: 'Profile linked.', data: profileOf(linked, user) });
  } catch (error) {
    if (error.code === 'P2002') return fail(409, 'This profile or phone is already linked to another account.');
    next(error);
  }
}

/**
 * Where an account without a profile goes next: phone (or debug guest) sign-ins
 * register as patients, or claim a desk-registered profile on that phone;
 * email sign-ins verify their email, then apply as staff.
 */
async function nextStep(authUser) {
  if (await claimablePatient(authUser.phone_number)) return 'CLAIM';
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
        next: await nextStep(req.user),
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
          next: await nextStep(req.user),
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

/** +919876543210 → +91******3210, for staff who haven't got the patient in their clinic. */
function maskPhone(phone) {
  return phone && phone.length > 7 ? phone.slice(0, 3) + '*'.repeat(phone.length - 7) + phone.slice(-4) : phone;
}

/**
 * @route   GET /api/patients/search?q=<query>
 * @desc    Name or Health ID search, limited to patients with an appointment at
 *          the caller's clinic. An exact Health ID or phone finds anyone (as
 *          /lookup does), with the phone masked outside the clinic.
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
    const clinic_id = req.user.clinic_id;
    if (!clinic_id) {
      return res.status(403).json({ success: false, error: 'Forbidden', message: 'No clinic is assigned to this account.' });
    }

    const phone = toE164(q);
    const patients = await prisma.patient.findMany({
      where: {
        OR: [
          { health_id: { equals: q, mode: 'insensitive' } },
          ...(phone ? [{ phone }] : []),
          {
            appointments: { some: { clinic_id } },
            OR: [
              { name:      { contains: q, mode: 'insensitive' } },
              { health_id: { contains: q, mode: 'insensitive' } },
            ],
          },
        ],
      },
      select: {
        id:        true,
        name:      true,
        health_id: true,
        phone:     true,
        gender:    true,
        dob:       true,
        appointments: { where: { clinic_id }, select: { id: true }, take: 1 },
      },
      orderBy: { name: 'asc' },
      take: 10,
    });

    return res.json({
      success: true,
      count: patients.length,
      data: patients.map(({ appointments, ...p }) => (appointments.length ? p : { ...p, phone: maskPhone(p.phone) })),
    });
  } catch (error) {
    console.error('❌ Error searching patients:', error.message);
    next(error);
  }
}

/**
 * @route   GET /api/patients/lookup?health_id=|phone=
 * @desc    Exact match → demographics, a masked phone, and whether the caller
 *          may open the records: access { allowed, via } (services/patientAccess.js).
 *          Not logged: no record data is returned.
 * @access  Private — patient:lookup
 */
async function lookupPatient(req, res, next) {
  try {
    const healthId = String(req.query.health_id || '').trim();
    const phone = healthId ? null : toE164(String(req.query.phone || ''));
    if (!healthId && !phone) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Pass an exact "health_id" or "phone" (10-digit Indian mobile, or with its country code).',
      });
    }

    const patient = await prisma.patient.findFirst({
      where: healthId ? { health_id: { equals: healthId, mode: 'insensitive' } } : { phone },
      select: { id: true, name: true, health_id: true, gender: true, dob: true, phone: true },
    });
    if (!patient) {
      return res.status(404).json({ success: false, error: 'Not Found', message: 'No patient matches that Health ID or phone.' });
    }

    const { allowed, via } = await resolveAccess(req.user, patient.id);
    return res.json({ success: true, data: { ...patient, phone: maskPhone(patient.phone), access: { allowed, via } } });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  createPatient,
  registerPatientAtDesk,
  claimPatient,
  getMyProfile,
  getPatientById,
  updatePatient,
  searchPatients,
  lookupPatient,
};
