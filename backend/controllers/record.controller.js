// backend/controllers/record.controller.js
// ============================================================
// Medical Records & Prescriptions Module Controller (Day 13)
// ============================================================
// Handles:
// 1. POST  /api/records                    — Doctor creates medical record + nested prescriptions (atomic write)
// 2. GET   /api/records/patient/:patientId — Comprehensive patient history (cross-clinic visibility)
// 3. GET   /api/records/:id                — Single record details with prescriptions
// 4. POST  /api/records/:id/upload         — Upload medical report/document (Multer → private S3)
// 5. POST  /api/records/interaction-check  — Pre-flight cross-clinic drug interaction check
// 6. POST  /api/records/schedule-parse     — Autofill structured dose chips from the free text (no patient data)
// ============================================================

'use strict';

const path = require('path');

const prisma = require('../config/prisma');
const { putReport, signReport } = require('../config/s3');
const { checkInteractions } = require('../services/interactionChecker');
const { parseSchedules } = require('../services/doseScheduleParser');

// Reusable UUID validator regex (8-4-4-4-12)
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Standard relational payload for medical records
const RECORD_INCLUDE = {
  prescriptions: {
    select: {
      id: true,
      medicine_name: true,
      dosage: true,
      duration: true,
      created_at: true,
    },
  },
  doctor: {
    select: {
      id: true,
      name: true,
      specialization: true,
      phone: true,
      clinic: {
        select: {
          id: true,
          name: true,
          location: true,
        },
      },
    },
  },
  patient: {
    select: {
      id: true,
      name: true,
      health_id: true,
      phone: true,
      gender: true,
      dob: true,
      language_pref: true,
    },
  },
  appointment: {
    select: {
      id: true,
      slot_time: true,
      status: true,
    },
  },
};

/**
 * Helper: Derives Doctor ID for the authenticated user.
 */
async function getAuthenticatedDoctorId(req) {
  if (req.user?.doctor_id) {
    return req.user.doctor_id;
  }

  if (!req.user?.uid) {
    return null;
  }

  // 1. Check user record by firebase_uid
  const user = await prisma.user.findUnique({
    where: { firebase_uid: req.user.uid },
    include: { doctor: true },
  });

  if (user?.doctor) {
    req.user.doctor_id = user.doctor.id;
    return user.doctor.id;
  }

  // No phone fallback: an unlinked Doctor row is not proof of identity.
  // Doctors get linked once, in GET /patients/me.
  return null;
}

/**
 * ------------------------------------------------------------
 * 1. POST /api/records
 * ------------------------------------------------------------
 * Doctor creates a new medical consultation record.
 * - Supports nested array of prescriptions in the same payload.
 * - Executes in a single atomic database transaction.
 * - Optionally links to an appointment_id and completes it.
 * ------------------------------------------------------------
 */
async function createMedicalRecord(req, res, next) {
  try {
    let body = req.body || {};
    if (typeof body === 'string') {
      try {
        body = JSON.parse(body);
      } catch (e) {
        body = {};
      }
    }

    const {
      patient_id,
      doctor_id: bodyDoctorId,
      appointment_id,
      visit_date,
      diagnosis,
      notes,
      prescriptions,
      check_id,
      override_reason,
    } = body;

    // ── 1. Validate Doctor Identity ──────────────────────────
    // record:write is DOCTOR only, and a doctor always saves under their own
    // profile: a visit must be saved under the doctor who saw the patient.
    const doctor_id = await getAuthenticatedDoctorId(req);
    if (!doctor_id || (bodyDoctorId && String(bodyDoctorId).trim() !== doctor_id)) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden',
        message: doctor_id
          ? 'Doctors can only save visit records under their own profile.'
          : 'No doctor profile is linked to this account.',
      });
    }

    // ── 2. Validate Patient Existence ────────────────────────
    if (!patient_id || !UUID_REGEX.test(String(patient_id).trim())) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "patient_id" is required and must be a valid UUID.',
      });
    }

    const patient = await prisma.patient.findUnique({
      where: { id: String(patient_id).trim() },
    });

    if (!patient) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Patient with ID "${patient_id}" does not exist.`,
      });
    }

    // ── 3. Validate Diagnosis & Notes ────────────────────────
    if (!diagnosis || typeof diagnosis !== 'string' || diagnosis.trim().length < 2) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "diagnosis" is required and must be at least 2 characters.',
      });
    }

    // ── 4. Validate Optional Appointment Linking ─────────────
    let validAppointmentId = null;
    if (appointment_id) {
      const cleanApptId = String(appointment_id).trim();
      if (!UUID_REGEX.test(cleanApptId)) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'Field "appointment_id" must be a valid UUID if provided.',
        });
      }

      const appointment = await prisma.appointment.findUnique({
        where: { id: cleanApptId },
      });

      if (!appointment) {
        return res.status(404).json({
          success: false,
          error: 'Not Found',
          message: `Appointment with ID "${appointment_id}" was not found.`,
        });
      }

      if (appointment.patient_id !== patient.id) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'The specified appointment does not belong to this patient.',
        });
      }

      validAppointmentId = cleanApptId;
    }

    // ── 5. Validate & Sanitize Prescriptions Array ───────────
    const formattedPrescriptions = [];
    if (prescriptions) {
      if (!Array.isArray(prescriptions)) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'Field "prescriptions" must be an array of prescription objects.',
        });
      }

      for (let i = 0; i < prescriptions.length; i++) {
        const item = prescriptions[i];
        if (!item.medicine_name || typeof item.medicine_name !== 'string' || !item.medicine_name.trim()) {
          return res.status(400).json({
            success: false,
            error: 'Bad Request',
            message: `Prescription at index ${i} requires a non-empty "medicine_name".`,
          });
        }

        if (!item.dosage || typeof item.dosage !== 'string' || !item.dosage.trim()) {
          return res.status(400).json({
            success: false,
            error: 'Bad Request',
            message: `Prescription at index ${i} requires a non-empty "dosage" (e.g. "500mg twice daily").`,
          });
        }

        if (!item.duration || typeof item.duration !== 'string' || !item.duration.trim()) {
          return res.status(400).json({
            success: false,
            error: 'Bad Request',
            message: `Prescription at index ${i} requires a non-empty "duration" (e.g. "5 days").`,
          });
        }

        formattedPrescriptions.push({
          medicine_name: item.medicine_name.trim(),
          dosage: item.dosage.trim(),
          duration: item.duration.trim(),
        });
      }
    }

    // ── 6. Validate the Pre-Flight Interaction Check ─────────
    // The conflicts are read back from the stored check row, never from the
    // request body, so the audit trail reflects what the server actually found
    // and a client cannot save a conflicted record by simply omitting them.
    let interactionCheck = null;
    let cleanOverrideReason = null;

    if (check_id) {
      const cleanCheckId = String(check_id).trim();

      if (!UUID_REGEX.test(cleanCheckId)) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'Field "check_id" must be a valid UUID if provided.',
        });
      }

      interactionCheck = await prisma.interactionCheck.findUnique({
        where: { id: cleanCheckId },
        select: { id: true, patient_id: true, conflicts: true, record_id: true },
      });

      if (!interactionCheck) {
        return res.status(404).json({
          success: false,
          error: 'Not Found',
          message: `Interaction check with ID "${check_id}" was not found.`,
        });
      }

      if (interactionCheck.patient_id !== patient.id) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'The specified interaction check does not belong to this patient.',
        });
      }

      // A check row maps to exactly one record, or the audit trail loses track
      // of which save the doctor was warned about.
      if (interactionCheck.record_id) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: 'This interaction check has already been linked to a medical record. Run a new check.',
        });
      }

      const storedConflicts = Array.isArray(interactionCheck.conflicts)
        ? interactionCheck.conflicts
        : [];

      const hasReason =
        typeof override_reason === 'string' && override_reason.trim().length > 0;

      if (storedConflicts.length > 0 && !hasReason) {
        return res.status(400).json({
          success: false,
          error: 'Bad Request',
          message: `This check found ${storedConflicts.length} drug interaction(s). Field "override_reason" is required to save the record anyway.`,
        });
      }

      if (hasReason) {
        cleanOverrideReason = override_reason.trim();
      }
    }

    // ── 7. Atomic Record + Prescriptions Creation ────────────
    const parsedVisitDate = visit_date && !isNaN(Date.parse(visit_date))
      ? new Date(visit_date)
      : new Date();

    const newRecord = await prisma.medicalRecord.create({
      data: {
        patient_id: patient.id,
        doctor_id: doctor_id,
        appointment_id: validAppointmentId,
        visit_date: parsedVisitDate,
        diagnosis: diagnosis.trim(),
        notes: notes ? String(notes).trim() : '',
        ...(formattedPrescriptions.length > 0
          ? {
              prescriptions: {
                create: formattedPrescriptions,
              },
            }
          : {}),
      },
      include: RECORD_INCLUDE,
    });

    // If linked to an appointment, mark appointment as completed
    if (validAppointmentId) {
      await prisma.appointment.update({
        where: { id: validAppointmentId },
        data: { status: 'completed' },
      }).catch((err) => console.warn('Could not auto-complete appointment:', err.message));
    }

    // Link the pre-flight check to the record it authorised. `overridden` is
    // only true when the doctor saved past real conflicts — a clean check that
    // warned about nothing was not overridden.
    if (interactionCheck) {
      const hadConflicts =
        Array.isArray(interactionCheck.conflicts) && interactionCheck.conflicts.length > 0;

      await prisma.interactionCheck.update({
        where: { id: interactionCheck.id },
        data: {
          record_id: newRecord.id,
          overridden: hadConflicts,
          override_reason: cleanOverrideReason,
        },
      }).catch((err) => console.warn('Could not link interaction check to record:', err.message));
    }

    return res.status(201).json({
      success: true,
      message: 'Medical record and prescriptions created successfully.',
      data: newRecord,
    });
  } catch (error) {
    console.error('❌ Create Medical Record Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 2. GET /api/records/patient/:patientId
 * ------------------------------------------------------------
 * Retrieves the complete longitudinal medical history for a patient.
 * - Core feature: Cross-clinic history follows the patient everywhere!
 * - Accessible by: the patient themselves, or a doctor with a care link,
 *   consent or emergency grant (requirePatientAccess).
 * - Supports lookup by Patient UUID or Health ID (e.g. MWH-XXXXXX).
 * ------------------------------------------------------------
 */
async function getPatientMedicalHistory(req, res, next) {
  try {
    const { patientId } = req.params;

    if (!patientId) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Parameter "patientId" is required in URL.',
      });
    }

    // ── 1. Resolve Patient ───────────────────────────────────
    let patient = null;
    if (UUID_REGEX.test(patientId)) {
      patient = await prisma.patient.findUnique({
        where: { id: patientId },
      });
    } else {
      // Support lookup by Health ID (e.g. MWH-UKFNSP)
      patient = await prisma.patient.findUnique({
        where: { health_id: patientId },
      });
    }

    if (!patient) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Patient with ID/Health ID "${patientId}" was not found.`,
      });
    }

    // ── 2. Access (self, care link, consent) is checked by requirePatientAccess ──

    // ── 3. Fetch Full Longitudinal History ───────────────────
    // Notice: We intentionally DO NOT filter by clinic_id or doctor_id!
    // A doctor at Clinic B must see diagnoses recorded at Clinic A.
    const records = await prisma.medicalRecord.findMany({
      where: {
        patient_id: patient.id,
      },
      include: RECORD_INCLUDE,
      orderBy: {
        visit_date: 'desc', // Most recent consultations first
      },
    });

    return res.status(200).json({
      success: true,
      patient: {
        id: patient.id,
        health_id: patient.health_id,
        name: patient.name,
        dob: patient.dob,
        gender: patient.gender,
        language_pref: patient.language_pref,
      },
      count: records.length,
      data: await Promise.all(records.map(signReport)),
    });
  } catch (error) {
    console.error('❌ Get Patient Medical History Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 3. GET /api/records/:id
 * ------------------------------------------------------------
 * Single medical record details by record UUID.
 * - Accessible by: the patient, or a doctor with access (requirePatientAccess).
 * ------------------------------------------------------------
 */
async function getMedicalRecordById(req, res, next) {
  try {
    const { id } = req.params;

    if (!id || !UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Record ID in URL must be a valid UUID.',
      });
    }

    const record = await prisma.medicalRecord.findUnique({
      where: { id },
      include: RECORD_INCLUDE,
    });

    if (!record) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Medical record with ID "${id}" was not found.`,
      });
    }

    // Access (self, care link, consent) is checked by requirePatientAccess.

    return res.status(200).json({
      success: true,
      data: await signReport(record),
    });
  } catch (error) {
    console.error('❌ Get Medical Record By ID Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 4. POST /api/records/:id/upload
 * ------------------------------------------------------------
 * Uploads a lab report / document for a specific medical record.
 * - File is buffered by Multer, then stored in the private S3 bucket
 * - Stores the S3 *key* in report_file_url; responses carry a presigned URL
 * - Needs report:upload (doctors).
 * ------------------------------------------------------------
 */
async function uploadReportFile(req, res, next) {
  try {
    const { id } = req.params;

    if (!id || !UUID_REGEX.test(id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Record ID in URL must be a valid UUID.',
      });
    }

    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'No file uploaded. Please attach a file under field name "report".',
      });
    }

    // Verify record exists
    const record = await prisma.medicalRecord.findUnique({
      where: { id },
    });

    if (!record) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Medical record with ID "${id}" was not found.`,
      });
    }

    // Store under a per-record prefix so the IAM policy can scope to reports/*
    const ext = path.extname(req.file.originalname).toLowerCase();
    const key = `reports/${id}/${Date.now()}-${Math.round(Math.random() * 1e9)}${ext}`;

    await putReport(req.file.buffer, key, req.file.mimetype);

    // The DB holds the key; the client gets a short-lived presigned URL.
    const updatedRecord = await prisma.medicalRecord.update({
      where: { id },
      data: {
        report_file_url: key,
      },
      include: RECORD_INCLUDE,
    });

    const signed = await signReport(updatedRecord);

    return res.status(200).json({
      success: true,
      message: 'Medical report uploaded successfully.',
      file_url: signed.report_file_url,
      file_info: {
        original_name: req.file.originalname,
        filename: key,
        mimetype: req.file.mimetype,
        size_bytes: req.file.size,
      },
      data: signed,
    });
  } catch (error) {
    console.error('❌ Upload Report Error:', error);
    next(error);
  }
}

/**
 * ------------------------------------------------------------
 * 5. POST /api/records/interaction-check
 * ------------------------------------------------------------
 * Pre-flight check run before a visit record is saved.
 * - Compares the pending prescriptions against everything the patient is
 *   still taking, at EVERY clinic in the network.
 * - Persists the result so createMedicalRecord can verify an override
 *   reason against conflicts the server actually found, rather than
 *   trusting whatever the client sends back.
 * - Never blocks: it reports, the doctor decides.
 * ------------------------------------------------------------
 */
async function checkDrugInteractions(req, res, next) {
  try {
    const { patient_id, prescriptions } = req.body || {};

    // ── 1. Validate Patient ──────────────────────────────────
    if (!patient_id || !UUID_REGEX.test(String(patient_id).trim())) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "patient_id" is required and must be a valid UUID.',
      });
    }

    const patient = await prisma.patient.findUnique({
      where: { id: String(patient_id).trim() },
      select: { id: true },
    });

    if (!patient) {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: `Patient with ID "${patient_id}" does not exist.`,
      });
    }

    // ── 2. Validate Prescriptions ────────────────────────────
    if (!Array.isArray(prescriptions)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "prescriptions" is required and must be an array.',
      });
    }

    const cleaned = prescriptions
      .filter((rx) => rx && typeof rx.medicine_name === 'string' && rx.medicine_name.trim())
      .map((rx) => ({
        medicine_name: String(rx.medicine_name).trim(),
        dosage: rx.dosage ? String(rx.dosage).trim() : '',
        duration: rx.duration ? String(rx.duration).trim() : '',
      }));

    // ── 3. Identify the requesting doctor (for the audit row) ─
    const doctor_id = await getAuthenticatedDoctorId(req);

    if (!doctor_id || !UUID_REGEX.test(doctor_id)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Could not resolve the requesting doctor. Ensure the account is linked to a doctor record.',
      });
    }

    // ── 4. Run the check ─────────────────────────────────────
    const result = await checkInteractions({
      patientId: patient.id,
      newPrescriptions: cleaned,
    });

    // ── 5. Persist the audit row ─────────────────────────────
    const check = await prisma.interactionCheck.create({
      data: {
        patient_id: patient.id,
        doctor_id,
        checked_drugs: cleaned,
        conflicts: result.conflicts,
        ai_available: result.ai_available,
        ai_provider: result.ai_provider,
      },
      select: { id: true },
    });

    return res.status(200).json({
      success: true,
      data: {
        check_id: check.id,
        conflicts: result.conflicts,
        ai_available: result.ai_available,
      },
    });
  } catch (error) {
    console.error('❌ Drug Interaction Check Error:', error);
    next(error);
  }
}


/**
 * ============================================================
 * POST /api/records/schedule-parse
 * ------------------------------------------------------------
 * Turns the free-text dosage/duration a doctor is typing into structured
 * dose-schedule chips they confirm with a glance (Smart Prescriptions
 * Phase 2). Deterministic regex first, an optional AI leg filling only the
 * gaps it leaves.
 *
 * Deliberately PATIENT-FREE. It takes no patient_id, reads nothing from the
 * database and writes no audit row, which is exactly what lets the visit
 * form autofill as the doctor types — before a patient has been selected —
 * without going through requirePatientAccess. Keep it that way: the moment
 * this endpoint touches patient data it needs that gate.
 *
 * Body: { prescriptions: [{ medicine_name, dosage, duration }] }
 *
 * The response carries exactly one schedule per INPUT row, in the same order
 * (a row with no medicine name comes back blank rather than being dropped),
 * so the client can autofill chips by index.
 * ============================================================
 */
async function parseDoseSchedules(req, res, next) {
  try {
    const { prescriptions } = req.body || {};

    if (!Array.isArray(prescriptions)) {
      return res.status(400).json({
        success: false,
        error: 'Bad Request',
        message: 'Field "prescriptions" is required and must be an array.',
      });
    }

    const result = await parseSchedules({ prescriptions });

    return res.status(200).json({
      success: true,
      data: {
        schedules: result.schedules,
        ai_available: result.ai_available,
        ai_provider: result.ai_provider,
      },
    });
  } catch (error) {
    console.error('❌ Dose Schedule Parse Error:', error);
    next(error);
  }
}

module.exports = {
  createMedicalRecord,
  checkDrugInteractions,
  parseDoseSchedules,
  getAuthenticatedDoctorId,
  getPatientMedicalHistory,
  getMedicalRecordById,
  uploadReportFile,
};
