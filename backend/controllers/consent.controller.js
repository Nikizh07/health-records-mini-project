// backend/controllers/consent.controller.js
// ============================================================
// Patient consent (AUTH_RBAC_CONSENT_PLAN.md §D, Phase 7)
// ============================================================
// Doctor (consent:request / consent:emergency):
//   POST /api/consents               { patient_id } → PENDING app request, 10 min
//   GET  /api/consents/:id           poll own request
//   POST /api/consents/redeem        { patient_id, code } → 24 h grant
//   POST /api/consents/emergency     { patient_id, reason ≥ 20 chars } → 4 h grant
// Patient (consent:respond):
//   GET  /api/consents/pending       app requests waiting for an answer
//   POST /api/consents/:id/respond   { approve: true|false } → 24 h grant or DENIED
//   POST /api/consents/share-code    → { code } shown once, 10 min, single use
//   GET  /api/consents/mine          own requests/grants + who accessed the records
//   POST /api/consents/:id/revoke    end a grant
// Audit (audit:read):
//   GET  /api/audit/access?clinic_id=
//
// Every state change is a conditional updateMany, so two taps (or two
// devices) can't both win on a stale read.
// ============================================================

'use strict';

const crypto = require('crypto');
const { STATUS_CODES } = require('http');
const prisma = require('../config/prisma');
const { outsideOwnClinic } = require('../config/permissions');

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const REQUEST_TTL = 10 * MINUTE;
const CODE_TTL = 10 * MINUTE;
const CONSENT_GRANT = 24 * HOUR;
const EMERGENCY_GRANT = 4 * HOUR;
const MAX_REQUESTS_PER_HOUR = 3;
const MAX_CODE_ATTEMPTS = 5;
const MIN_EMERGENCY_REASON = 20;

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const fail = (res, status, message, extra = {}) =>
  res.status(status).json({ success: false, error: STATUS_CODES[status], message, ...extra });

const later = (ms) => new Date(Date.now() + ms);

const hashCode = (consentId, code) => crypto.createHash('sha256').update(`${consentId}:${code}`).digest('hex');

const CONSENT_INCLUDE = {
  doctor: { select: { id: true, name: true, specialization: true } },
  clinic: { select: { id: true, name: true } },
};

/** What a row means right now: a lapsed PENDING or grant reads as EXPIRED. Hides the code hash. */
function present({ code_hash, ...c }) {
  const now = new Date();
  const lapsed =
    (c.status === 'PENDING' && c.expires_at <= now) ||
    (c.status === 'APPROVED' && c.granted_until && c.granted_until <= now);
  return { ...c, status: lapsed ? 'EXPIRED' : c.status };
}

/** The signed-in doctor, or a 403 already sent. */
function doctorOf(req, res) {
  if (req.user.doctor_id) return req.user.doctor_id;
  fail(res, 403, 'No doctor profile is linked to this account.');
  return null;
}

/** The signed-in patient, or a 404 already sent. */
function patientOf(req, res) {
  if (req.user.patient_id) return req.user.patient_id;
  fail(res, 404, 'Patient profile not found.');
  return null;
}

/** body.patient_id of an existing patient, or an error already sent. */
async function targetPatient(req, res) {
  const id = String(req.body?.patient_id || '').trim();
  if (!UUID_REGEX.test(id)) {
    fail(res, 400, 'Field "patient_id" is required and must be a valid UUID.');
    return null;
  }
  if (!(await prisma.patient.findUnique({ where: { id }, select: { id: true } }))) {
    fail(res, 404, `Patient with ID "${id}" does not exist.`);
    return null;
  }
  return id;
}

// ── Doctor ──────────────────────────────────────────────────

async function requestConsent(req, res, next) {
  try {
    const doctor_id = doctorOf(req, res);
    if (!doctor_id) return;
    const patient_id = await targetPatient(req, res);
    if (!patient_id) return;

    const recent = await prisma.consentRequest.count({
      where: { patient_id, doctor_id, method: 'APP', created_at: { gt: new Date(Date.now() - HOUR) } },
    });
    if (recent >= MAX_REQUESTS_PER_HOUR) {
      return fail(res, 429, `At most ${MAX_REQUESTS_PER_HOUR} requests an hour for the same patient. Ask for a share code instead.`);
    }

    // A new request replaces any still waiting, so the patient sees one popup.
    await prisma.consentRequest.updateMany({
      where: { patient_id, doctor_id, method: 'APP', status: 'PENDING' },
      data: { status: 'EXPIRED' },
    });
    const consent = await prisma.consentRequest.create({
      data: {
        patient_id, doctor_id, clinic_id: req.user.clinic_id,
        method: 'APP', status: 'PENDING', expires_at: later(REQUEST_TTL),
      },
      include: CONSENT_INCLUDE,
    });
    return res.status(201).json({ success: true, message: 'Request sent to the patient.', data: present(consent) });
  } catch (error) {
    next(error);
  }
}

async function getConsent(req, res, next) {
  try {
    const doctor_id = doctorOf(req, res);
    if (!doctor_id) return;
    const consent = UUID_REGEX.test(req.params.id)
      ? await prisma.consentRequest.findUnique({ where: { id: req.params.id }, include: CONSENT_INCLUDE })
      : null;
    if (!consent || consent.doctor_id !== doctor_id) return fail(res, 404, 'Consent request not found.');
    return res.json({ success: true, data: present(consent) });
  } catch (error) {
    next(error);
  }
}

async function redeemShareCode(req, res, next) {
  try {
    const doctor_id = doctorOf(req, res);
    if (!doctor_id) return;
    const patient_id = await targetPatient(req, res);
    if (!patient_id) return;
    const code = String(req.body?.code || '').trim();
    if (!/^\d{6}$/.test(code)) return fail(res, 400, 'Field "code" must be the 6-digit share code.');

    const consent = await prisma.consentRequest.findFirst({
      where: { patient_id, method: 'CODE', status: 'PENDING', expires_at: { gt: new Date() } },
      orderBy: { created_at: 'desc' },
    });
    if (!consent) return fail(res, 404, 'This patient has no active share code. Ask them to make a new one.');

    // Take the attempt before comparing, so parallel guesses can't beat the limit.
    const { count } = await prisma.consentRequest.updateMany({
      where: { id: consent.id, status: 'PENDING', attempts: { lt: MAX_CODE_ATTEMPTS } },
      data: { attempts: { increment: 1 } },
    });
    if (count === 0) return fail(res, 423, 'Too many wrong codes. Ask the patient to make a new one.');

    const given = Buffer.from(hashCode(consent.id, code));
    if (!crypto.timingSafeEqual(given, Buffer.from(consent.code_hash))) {
      const attempts_left = MAX_CODE_ATTEMPTS - (consent.attempts + 1);
      return fail(res, 403, 'Wrong share code.', { attempts_left: Math.max(attempts_left, 0) });
    }

    const now = new Date();
    const redeemed = await prisma.consentRequest.updateMany({
      where: { id: consent.id, status: 'PENDING' },
      data: {
        status: 'APPROVED', doctor_id, clinic_id: req.user.clinic_id,
        responded_at: now, granted_until: later(CONSENT_GRANT),
      },
    });
    if (redeemed.count === 0) return fail(res, 409, 'This share code has already been used.');
    const granted = await prisma.consentRequest.findUnique({ where: { id: consent.id }, include: CONSENT_INCLUDE });
    return res.json({ success: true, message: 'Access granted for 24 hours.', data: present(granted) });
  } catch (error) {
    next(error);
  }
}

async function emergencyAccess(req, res, next) {
  try {
    const doctor_id = doctorOf(req, res);
    if (!doctor_id) return;
    const reason = String(req.body?.reason || '').trim();
    if (reason.length < MIN_EMERGENCY_REASON) {
      return fail(res, 400, `Field "reason" is required (at least ${MIN_EMERGENCY_REASON} characters). It is shown to the patient and the clinic.`);
    }
    const patient_id = await targetPatient(req, res);
    if (!patient_id) return;

    const now = new Date();
    const consent = await prisma.consentRequest.create({
      data: {
        patient_id, doctor_id, clinic_id: req.user.clinic_id, method: 'EMERGENCY', status: 'APPROVED',
        reason, expires_at: now, responded_at: now, granted_until: later(EMERGENCY_GRANT),
      },
      include: CONSENT_INCLUDE,
    });
    return res.status(201).json({ success: true, message: 'Emergency access granted for 4 hours. This is recorded.', data: present(consent) });
  } catch (error) {
    next(error);
  }
}

// ── Patient ─────────────────────────────────────────────────

async function pendingConsents(req, res, next) {
  try {
    const patient_id = patientOf(req, res);
    if (!patient_id) return;
    const pending = await prisma.consentRequest.findMany({
      where: { patient_id, method: 'APP', status: 'PENDING', expires_at: { gt: new Date() } },
      include: CONSENT_INCLUDE,
      orderBy: { created_at: 'asc' },
    });
    return res.json({ success: true, count: pending.length, data: pending.map(present) });
  } catch (error) {
    next(error);
  }
}

async function respondToConsent(req, res, next) {
  try {
    const patient_id = patientOf(req, res);
    if (!patient_id) return;
    const { approve } = req.body || {};
    if (typeof approve !== 'boolean') return fail(res, 400, 'Field "approve" must be true or false.');
    if (!UUID_REGEX.test(req.params.id)) return fail(res, 404, 'Consent request not found.');

    const now = new Date();
    const { count } = await prisma.consentRequest.updateMany({
      where: { id: req.params.id, patient_id, method: 'APP', status: 'PENDING', expires_at: { gt: now } },
      data: approve
        ? { status: 'APPROVED', responded_at: now, granted_until: later(CONSENT_GRANT) }
        : { status: 'DENIED', responded_at: now },
    });
    const consent = await prisma.consentRequest.findUnique({ where: { id: req.params.id }, include: CONSENT_INCLUDE });
    if (!consent || consent.patient_id !== patient_id || consent.method !== 'APP') {
      return fail(res, 404, 'Consent request not found.');
    }
    if (count === 0) {
      return fail(res, 409, `This request can no longer be answered (it is ${present(consent).status.toLowerCase()}).`);
    }
    return res.json({ success: true, message: approve ? 'Access allowed for 24 hours.' : 'Request denied.', data: present(consent) });
  } catch (error) {
    next(error);
  }
}

async function createShareCode(req, res, next) {
  try {
    const patient_id = patientOf(req, res);
    if (!patient_id) return;

    // One live code per patient: a new one retires the old.
    await prisma.consentRequest.updateMany({
      where: { patient_id, method: 'CODE', status: 'PENDING' },
      data: { status: 'EXPIRED' },
    });
    const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
    const id = crypto.randomUUID();
    const consent = await prisma.consentRequest.create({
      data: { id, patient_id, method: 'CODE', status: 'PENDING', code_hash: hashCode(id, code), expires_at: later(CODE_TTL) },
    });
    return res.status(201).json({
      success: true,
      message: 'Show this code to the doctor. It works once, for 10 minutes.',
      data: { id: consent.id, code, expires_at: consent.expires_at },
    });
  } catch (error) {
    next(error);
  }
}

/** Access log rows with who read them (doctor name, clinic) and the grant behind it. */
const ACCESS_LOG_INCLUDE = {
  user: {
    select: {
      id: true, role: true, email: true,
      doctor: { select: { name: true, clinic: { select: { id: true, name: true } } } },
    },
  },
  patient: { select: { id: true, name: true, health_id: true } },
  consent: { select: { id: true, method: true, reason: true, granted_until: true } },
};

async function myConsents(req, res, next) {
  try {
    const patient_id = patientOf(req, res);
    if (!patient_id) return;
    const [consents, access_log] = await Promise.all([
      prisma.consentRequest.findMany({
        where: { patient_id, doctor_id: { not: null } },
        include: CONSENT_INCLUDE,
        orderBy: { created_at: 'desc' },
        take: 50,
      }),
      prisma.patientAccessLog.findMany({
        where: { patient_id },
        include: ACCESS_LOG_INCLUDE,
        orderBy: { created_at: 'desc' },
        take: 100,
      }),
    ]);
    return res.json({ success: true, data: { consents: consents.map(present), access_log } });
  } catch (error) {
    next(error);
  }
}

async function revokeConsent(req, res, next) {
  try {
    const patient_id = patientOf(req, res);
    if (!patient_id) return;
    if (!UUID_REGEX.test(req.params.id)) return fail(res, 404, 'Consent not found.');
    const { count } = await prisma.consentRequest.updateMany({
      where: { id: req.params.id, patient_id, status: 'APPROVED', granted_until: { gt: new Date() } },
      data: { status: 'REVOKED' },
    });
    const consent = await prisma.consentRequest.findUnique({ where: { id: req.params.id }, include: CONSENT_INCLUDE });
    if (!consent || consent.patient_id !== patient_id) return fail(res, 404, 'Consent not found.');
    if (count === 0) return fail(res, 409, `Only an active grant can be revoked (this one is ${present(consent).status.toLowerCase()}).`);
    return res.json({ success: true, message: 'Access revoked.', data: present(consent) });
  } catch (error) {
    next(error);
  }
}

// ── Audit ───────────────────────────────────────────────────

async function accessAudit(req, res, next) {
  try {
    const clinic_id = String(req.query.clinic_id || '').trim() || (req.user.role === 'ADMIN' ? null : req.user.clinic_id);
    if (clinic_id && !UUID_REGEX.test(clinic_id)) return fail(res, 400, 'Query parameter "clinic_id" must be a valid UUID.');
    if (req.user.role !== 'ADMIN' && (!clinic_id || outsideOwnClinic(req.user, clinic_id))) {
      return fail(res, 403, 'You can only read the access log of your own clinic.');
    }
    const logs = await prisma.patientAccessLog.findMany({
      where: clinic_id ? { clinic_id } : {},
      include: ACCESS_LOG_INCLUDE,
      orderBy: { created_at: 'desc' },
      take: 200,
    });
    return res.json({ success: true, count: logs.length, data: logs });
  } catch (error) {
    next(error);
  }
}

module.exports = {
  requestConsent,
  getConsent,
  redeemShareCode,
  emergencyAccess,
  pendingConsents,
  respondToConsent,
  createShareCode,
  myConsents,
  revokeConsent,
  accessAudit,
};
