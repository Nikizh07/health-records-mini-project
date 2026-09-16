// backend/services/patientAccess.js
// ============================================================
// Who may see a patient's records (AUTH_RBAC_CONSENT_PLAN.md §D)
// ============================================================
// resolveAccess(user, patientId) → { allowed, via, consent_id?, appointment_id? }
//   SELF       the patient themselves
//   CARE       a doctor who wrote a record for the patient, or whose clinic has
//              a non-cancelled appointment with them within ±30 days
//   CONSENT    an APPROVED app request or redeemed share code, still in date
//   EMERGENCY  an emergency grant, still in date
// Everyone else (receptionists, admins, other patients) is refused.
// ============================================================

'use strict';

const prisma = require('../config/prisma');

const CARE_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const DENIED = Object.freeze({ allowed: false, via: null });

async function resolveAccess(user, patientId, now = new Date()) {
  if (!user || !patientId) return DENIED;
  if (user.patient_id && user.patient_id === patientId) return { allowed: true, via: 'SELF' };
  if (!user.permissions?.includes('record:read') || !user.doctor_id) return DENIED;

  const wrote = await prisma.medicalRecord.findFirst({
    where: { patient_id: patientId, doctor_id: user.doctor_id },
    select: { id: true },
  });
  if (wrote) return { allowed: true, via: 'CARE' };

  if (user.clinic_id) {
    const appointment = await prisma.appointment.findFirst({
      where: {
        patient_id: patientId,
        clinic_id: user.clinic_id,
        status: { not: 'cancelled' },
        slot_time: { gte: new Date(now - CARE_WINDOW_MS), lte: new Date(+now + CARE_WINDOW_MS) },
      },
      select: { id: true },
    });
    if (appointment) return { allowed: true, via: 'CARE', appointment_id: appointment.id };
  }

  const grant = await prisma.consentRequest.findFirst({
    where: { patient_id: patientId, doctor_id: user.doctor_id, status: 'APPROVED', granted_until: { gt: now } },
    orderBy: { granted_until: 'desc' },
    select: { id: true, method: true },
  });
  if (grant) {
    return { allowed: true, via: grant.method === 'EMERGENCY' ? 'EMERGENCY' : 'CONSENT', consent_id: grant.id };
  }

  return DENIED;
}

module.exports = { resolveAccess };
