// backend/controllers/staff.controller.js
// ============================================================
// Staff onboarding (AUTH_RBAC_CONSENT_PLAN.md Phase 3)
// ============================================================
// Two ways in:
//   - Invite: an admin names a role, clinic and email/phone. The invite is
//     accepted on the person's first GET /patients/me (acceptInvite), only
//     when the matching identifier is verified on their Firebase account.
//   - Application: a signed-in doctor with a verified email and no account
//     applies with a registration number → DOCTOR, PENDING until approved.
// No email is sent: the admin tells the person to sign in.
// ============================================================

'use strict';

const { STATUS_CODES } = require('http');
const prisma = require('../config/prisma');
const { toE164 } = require('../utils/phone');
const { outsideOwnClinic } = require('../config/permissions');

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const INVITE_ROLES = ['RECEPTIONIST', 'DOCTOR', 'CLINIC_ADMIN'];
const INVITE_DAYS = 14;

const STAFF_SELECT = {
  id: true,
  email: true,
  phone: true,
  role: true,
  status: true,
  created_at: true,
  clinic: { select: { id: true, name: true } },
  doctor: {
    select: {
      id: true, name: true, specialization: true, clinic_id: true,
      registration_number: true, registration_council: true, verified_at: true,
    },
  },
};

const fail = (res, status, message) =>
  res.status(status).json({ success: false, error: STATUS_CODES[status], message });

const text = (value) => (typeof value === 'string' ? value.trim() : '');

/**
 * Validates an invite request. Returns { error: [status, message] } or
 * { data } ready for prisma.staffInvite.create. Shared with POST /doctors.
 */
async function buildInvite(req, body) {
  const role = text(body.role).toUpperCase();
  if (!INVITE_ROLES.includes(role)) {
    return { error: [400, `Field "role" must be one of: ${INVITE_ROLES.join(', ')}.`] };
  }
  const name = text(body.name);
  if (name.length < 2) {
    return { error: [400, 'Field "name" is required and must be at least 2 characters.'] };
  }
  const email = text(body.email).toLowerCase() || null;
  if (email && !EMAIL_REGEX.test(email)) {
    return { error: [400, 'Field "email" must be a valid email address.'] };
  }
  const phone = body.phone ? toE164(body.phone) : null;
  if (body.phone && !phone) {
    return { error: [400, 'Field "phone" must include its country code (e.g. "+60123456789").'] };
  }
  if (!email && !phone) {
    return { error: [400, 'An invite needs an "email" or a "phone".'] };
  }
  const specialization = text(body.specialization);
  if (role === 'DOCTOR' && specialization.length < 2) {
    return { error: [400, 'Field "specialization" is required for a doctor (e.g. "General Practice").'] };
  }

  const clinic_id = text(body.clinic_id) || req.user.clinic_id;
  if (!clinic_id || !UUID_REGEX.test(clinic_id)) {
    return { error: [400, 'Field "clinic_id" is required and must be a valid UUID.'] };
  }
  if (outsideOwnClinic(req.user, clinic_id)) {
    return { error: [403, 'You can only manage your own clinic.'] };
  }
  if (!(await prisma.clinic.findUnique({ where: { id: clinic_id } }))) {
    return { error: [404, `Clinic with ID "${clinic_id}" not found.`] };
  }

  // An account with this identifier would never reach the invite on sign-in.
  const identifiers = [email && { email }, phone && { phone }].filter(Boolean);
  if (await prisma.user.findFirst({ where: { OR: identifiers } })) {
    return { error: [409, 'This email or phone already belongs to an account.'] };
  }
  if (await prisma.staffInvite.findFirst({
    where: { OR: identifiers, accepted_user_id: null, expires_at: { gt: new Date() } },
  })) {
    return { error: [409, 'An open invite already exists for this email or phone.'] };
  }

  return {
    data: {
      clinic_id,
      role,
      email,
      phone,
      name,
      specialization: role === 'DOCTOR' ? specialization : null,
      invited_by_id: req.user.db_id,
      expires_at: new Date(Date.now() + INVITE_DAYS * 24 * 60 * 60 * 1000),
    },
  };
}

/**
 * First sign-in of an invited person (called from GET /patients/me when the
 * account has no users row). Accepts the newest open invite matching a
 * VERIFIED identifier. A DOCTOR invite links an existing unlinked Doctor with
 * the same phone or email, so its appointments are kept. Returns the new user
 * (with `include`), or null when there is no invite.
 */
async function acceptInvite(req, include) {
  const phone = toE164(req.user.phone_number); // a token phone is verified by Firebase
  const email = req.user.email_verified && req.user.email ? req.user.email.toLowerCase() : null;
  const identifiers = [phone && { phone }, email && { email }].filter(Boolean);
  if (identifiers.length === 0) return null;

  const invite = await prisma.staffInvite.findFirst({
    where: { OR: identifiers, accepted_user_id: null, expires_at: { gt: new Date() } },
    orderBy: { created_at: 'desc' },
  });
  if (!invite) return null;

  let doctor;
  if (invite.role === 'DOCTOR') {
    const inviteIds = [invite.phone && { phone: invite.phone }, invite.email && { email: invite.email }].filter(Boolean);
    const existing = await prisma.doctor.findFirst({ where: { user_id: null, OR: inviteIds } });
    doctor = existing
      ? { connect: { id: existing.id } }
      : {
          create: {
            clinic_id: invite.clinic_id,
            name: invite.name,
            specialization: invite.specialization,
            phone: invite.phone,
            email: invite.email,
          },
        };
  }

  return prisma.$transaction(async (tx) => {
    const user = await tx.user.create({
      data: {
        firebase_uid: req.user.uid,
        phone,
        email,
        role: invite.role,
        clinic_id: invite.clinic_id,
        ...(doctor && { doctor }),
      },
      include,
    });
    // Claim the invite only if nobody else did in the meantime.
    const claimed = await tx.staffInvite.updateMany({
      where: { id: invite.id, accepted_user_id: null },
      data: { accepted_user_id: user.id },
    });
    if (claimed.count !== 1) throw new Error('Invite was already accepted.');
    return user;
  });
}

/**
 * @route   POST /api/staff/invites
 * @access  Private — staff:manage (own clinic for CLINIC_ADMIN)
 */
async function createInvite(req, res, next) {
  try {
    const { error, data } = await buildInvite(req, req.body || {});
    if (error) return fail(res, ...error);
    const invite = await prisma.staffInvite.create({ data });
    return res.status(201).json({
      success: true,
      message: 'Invite created. Ask the person to sign in with this email or phone.',
      data: invite,
    });
  } catch (error) {
    next(error);
  }
}

/**
 * @route   GET /api/staff/invites
 * @access  Private — staff:manage (own clinic for CLINIC_ADMIN)
 */
async function listInvites(req, res, next) {
  try {
    if (req.user.role !== 'ADMIN' && !req.user.clinic_id) {
      return fail(res, 403, 'No clinic is assigned to this account.');
    }
    const invites = await prisma.staffInvite.findMany({
      where: req.user.role === 'ADMIN' ? {} : { clinic_id: req.user.clinic_id },
      include: { clinic: { select: { id: true, name: true } } },
      orderBy: { created_at: 'desc' },
    });
    const now = new Date();
    return res.json({
      success: true,
      count: invites.length,
      data: invites.map((i) => ({
        ...i,
        state: i.accepted_user_id ? 'ACCEPTED' : i.expires_at <= now ? 'EXPIRED' : 'OPEN',
      })),
    });
  } catch (error) {
    next(error);
  }
}

/**
 * @route   POST /api/staff/applications
 * @desc    A doctor applies: signed in, verified email, no account yet.
 * @access  Private — authenticated, no users row
 */
async function applyAsDoctor(req, res, next) {
  try {
    if (req.user.db_id) {
      return fail(res, 409, 'This account is already registered.');
    }
    if (!req.user.email || !req.user.email_verified) {
      return fail(res, 403, 'Verify your email address before applying.');
    }

    const body = req.body || {};
    const name = text(body.name);
    const specialization = text(body.specialization);
    const registration_number = text(body.registration_number);
    const registration_council = text(body.registration_council) || null;
    const clinic_id = text(body.clinic_id);

    if (name.length < 2) return fail(res, 400, 'Field "name" is required and must be at least 2 characters.');
    if (specialization.length < 2) return fail(res, 400, 'Field "specialization" is required.');
    if (registration_number.length < 3) return fail(res, 400, 'Field "registration_number" is required.');
    if (!UUID_REGEX.test(clinic_id)) return fail(res, 400, 'Field "clinic_id" is required and must be a valid UUID.');
    if (!(await prisma.clinic.findUnique({ where: { id: clinic_id } }))) {
      return fail(res, 404, `Clinic with ID "${clinic_id}" not found.`);
    }

    const email = req.user.email.toLowerCase();
    const phone = toE164(req.user.phone_number);
    const user = await prisma.user.create({
      data: {
        firebase_uid: req.user.uid,
        email,
        phone,
        role: 'DOCTOR',
        status: 'PENDING',
        clinic_id,
        doctor: {
          create: { clinic_id, name, specialization, email, phone, registration_number, registration_council },
        },
      },
      select: STAFF_SELECT,
    });

    return res.status(201).json({
      success: true,
      message: 'Application received. A clinic administrator will review it.',
      data: user,
    });
  } catch (error) {
    if (error.code === 'P2002') {
      return fail(res, 409, 'This email or phone already belongs to a doctor profile.');
    }
    next(error);
  }
}

/**
 * @route   GET /api/staff?status=ACTIVE|PENDING|DISABLED
 * @access  Private — staff:manage (own clinic for CLINIC_ADMIN)
 */
async function listStaff(req, res, next) {
  try {
    const where = { role: { not: 'PATIENT' } };
    if (req.query.status) {
      const status = String(req.query.status).toUpperCase();
      if (!['ACTIVE', 'PENDING', 'DISABLED'].includes(status)) {
        return fail(res, 400, 'Query parameter "status" must be one of: ACTIVE, PENDING, DISABLED.');
      }
      where.status = status;
    }
    if (req.user.role !== 'ADMIN') {
      // Without a clinic, `clinic_id: null` would match every platform ADMIN.
      if (!req.user.clinic_id) return fail(res, 403, 'No clinic is assigned to this account.');
      where.OR = [{ clinic_id: req.user.clinic_id }, { doctor: { clinic_id: req.user.clinic_id } }];
    }

    const staff = await prisma.user.findMany({ where, select: STAFF_SELECT, orderBy: { created_at: 'desc' } });
    return res.json({ success: true, count: staff.length, data: staff });
  } catch (error) {
    next(error);
  }
}

/**
 * @route   POST /api/staff/:userId/approve   PENDING or DISABLED → ACTIVE
 * @route   POST /api/staff/:userId/reject    PENDING → removed (they may apply again)
 * @route   POST /api/staff/:userId/disable   → DISABLED (403 on every call)
 * @access  Private — staff:manage (own clinic for CLINIC_ADMIN)
 */
function staffAction(action) {
  return async (req, res, next) => {
    try {
      const { userId } = req.params;
      if (!UUID_REGEX.test(userId)) return fail(res, 400, 'User ID must be a valid UUID.');

      const target = await prisma.user.findUnique({ where: { id: userId }, include: { doctor: true } });
      if (!target || target.role === 'PATIENT') return fail(res, 404, 'Staff member not found.');
      if (target.id === req.user.db_id) return fail(res, 400, 'You cannot change your own account.');
      if (outsideOwnClinic(req.user, target.doctor?.clinic_id ?? target.clinic_id)) {
        return fail(res, 403, 'You can only manage your own clinic.');
      }

      if (action === 'reject') {
        if (target.status !== 'PENDING') return fail(res, 400, 'Only pending applications can be rejected.');
        // A pending doctor is hidden from booking, so there is nothing to keep.
        await prisma.user.delete({ where: { id: target.id } }); // cascades to the Doctor row
        return res.json({ success: true, message: 'Application rejected.' });
      }

      const status = action === 'approve' ? 'ACTIVE' : 'DISABLED';
      if (target.status === status) return fail(res, 400, `This account is already ${status}.`);

      const updated = await prisma.$transaction(async (tx) => {
        if (action === 'approve' && target.doctor && !target.doctor.verified_at) {
          await tx.doctor.update({
            where: { id: target.doctor.id },
            data: { verified_at: new Date(), verified_by_id: req.user.db_id },
          });
        }
        return tx.user.update({ where: { id: target.id }, data: { status }, select: STAFF_SELECT });
      });

      return res.json({ success: true, message: `Account is now ${status}.`, data: updated });
    } catch (error) {
      next(error);
    }
  };
}

module.exports = {
  buildInvite,
  acceptInvite,
  createInvite,
  listInvites,
  applyAsDoctor,
  listStaff,
  approveStaff: staffAction('approve'),
  rejectStaff: staffAction('reject'),
  disableStaff: staffAction('disable'),
};
