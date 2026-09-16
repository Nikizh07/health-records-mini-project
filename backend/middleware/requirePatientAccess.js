// backend/middleware/requirePatientAccess.js
// ============================================================
// Record gate: care link, consent or emergency (services/patientAccess.js)
// ============================================================
//   router.get('/patient/:patientId', requirePermission(...),
//     requirePatientAccess('READ_HISTORY', fromParam('patientId')), ctrl.history);
//
// Runs after requirePermission. Finds the patient the request is about,
// resolves access, writes a PatientAccessLog row for every allowed staff
// request (a patient's own reads are not logged), and answers 403
// { code: 'CONSENT_REQUIRED' } when refused.
//
// If the patient can't be identified (malformed id, no such patient or
// record) it passes through: every controller behind it answers 400/404
// before touching patient data.
// ============================================================

'use strict';

const prisma = require('../config/prisma');
const { resolveAccess } = require('../services/patientAccess');

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Must find a patient exactly where the controller behind it would, or a
// request could slip past here and still be answered there.
async function patientById(id) {
  if (!id) return null;
  const where = UUID_REGEX.test(id) ? { id } : { health_id: id };
  return (await prisma.patient.findUnique({ where, select: { id: true } }))?.id ?? null;
}

/** Patient UUID or health ID in req.params[name] (as getPatientMedicalHistory reads it). */
const fromParam = (name) => (req) => patientById(req.params[name]);

/** Patient UUID in req.body.patient_id (as the record controllers read it). */
function fromBody(req) {
  const id = String(req.body?.patient_id || '').trim();
  return UUID_REGEX.test(id) ? patientById(id) : null;
}

/** The patient a medical record (req.params.id) belongs to. */
async function fromRecord(req) {
  if (!UUID_REGEX.test(req.params.id || '')) return null;
  const record = await prisma.medicalRecord.findUnique({ where: { id: req.params.id }, select: { patient_id: true } });
  return record?.patient_id ?? null;
}

function requirePatientAccess(action, locate) {
  return async (req, res, next) => {
    try {
      const patientId = await locate(req);
      if (!patientId) return next();

      const access = await resolveAccess(req.user, patientId);
      if (!access.allowed) {
        const canAsk = req.user.permissions?.includes('consent:request');
        return res.status(403).json({
          success: false,
          error: 'Forbidden',
          ...(canAsk ? { code: 'CONSENT_REQUIRED', patient_id: patientId } : {}),
          message: canAsk
            ? "This patient isn't under your care. Ask for their consent, use a share code, or use emergency access."
            : "Access denied. You can only view your own medical records.",
        });
      }

      if (access.via !== 'SELF') {
        // Fails closed: no audit row, no access.
        await prisma.patientAccessLog.create({
          data: {
            patient_id: patientId,
            user_id: req.user.db_id,
            clinic_id: req.user.clinic_id,
            via: access.via,
            consent_id: access.consent_id ?? null,
            appointment_id: access.appointment_id ?? null,
            action,
          },
        });
      }
      req.patientAccess = access;
      return next();
    } catch (error) {
      return next(error);
    }
  };
}

module.exports = { requirePatientAccess, fromParam, fromBody, fromRecord };
