// backend/services/interactionChecker.js
// ============================================================
// Cross-Clinic Medication Conflict Detector — core
// ============================================================
// Checks the drugs a doctor is about to prescribe against everything the
// patient is still taking, from EVERY clinic in the network.
//
// Two knowledge sources are planned (see AI_DRUG_INTERACTION_PLAN.md):
//   1. the curated `drug_interactions` table — deterministic, no network,
//      always runs. This is the load-bearing safety component.
//   2. an optional AI leg — added in Phase 4 at the seam marked below.
//
// Because the AI leg is allowed to fail open, nothing here may depend on it.
// ============================================================

'use strict';

const prisma = require('../config/prisma');
const { normaliseDrugName, orderPair } = require('../utils/drugName');
const { isLikelyActive } = require('../utils/prescriptionWindow');

// Most dangerous first — the banner shows them in this order.
const SEVERITY_RANK = {
  CRITICAL: 0,
  MAJOR: 1,
  MODERATE: 2,
  MINOR: 3,
};

/**
 * Loads every prescription the patient is probably still taking, across all
 * clinics. Mirrors getPatientMedicalHistory: deliberately NOT filtered by
 * clinic_id or doctor_id — seeing Clinic A's drugs at Clinic B is the point.
 *
 * @param {string} patientId
 * @returns {Promise<Array<{name, medicine_name, dosage, duration, clinic_name, visit_date, confidence}>>}
 */
async function getActiveMedications(patientId) {
  const records = await prisma.medicalRecord.findMany({
    where: { patient_id: patientId },
    select: {
      visit_date: true,
      prescriptions: {
        select: { medicine_name: true, dosage: true, duration: true },
      },
      doctor: {
        select: { clinic: { select: { name: true } } },
      },
    },
    orderBy: { visit_date: 'desc' },
  });

  const active = [];

  for (const record of records) {
    const clinicName = record.doctor?.clinic?.name || 'Unknown clinic';

    for (const rx of record.prescriptions) {
      const { active: stillActive, confidence } = isLikelyActive(rx, record.visit_date);
      if (!stillActive) continue;

      const name = normaliseDrugName(rx.medicine_name);
      if (!name) continue;

      active.push({
        name,
        medicine_name: rx.medicine_name,
        dosage: rx.dosage,
        duration: rx.duration,
        clinic_name: clinicName,
        visit_date: record.visit_date,
        confidence,
      });
    }
  }

  return active;
}

/**
 * Deterministic leg: looks the candidate pairs up in the curated table.
 * One query, matched in memory.
 *
 * @param {Array<{raw: string, name: string}>} newDrugs
 * @param {Array} activeMeds - from getActiveMedications
 * @returns {Promise<Array<object>>} conflict objects
 */
async function findTableConflicts(newDrugs, activeMeds) {
  const newNames = [...new Set(newDrugs.map((d) => d.name))];
  const activeNames = [...new Set(activeMeds.map((m) => m.name))];

  if (newNames.length === 0 || activeNames.length === 0) return [];

  const rows = await prisma.drugInteraction.findMany({
    where: {
      OR: [
        { drug_a: { in: newNames }, drug_b: { in: activeNames } },
        { drug_a: { in: activeNames }, drug_b: { in: newNames } },
      ],
    },
  });

  if (rows.length === 0) return [];

  // Most recent active prescription per normalised drug name.
  // activeMeds is already ordered newest-first, so the first hit wins.
  const latestActive = new Map();
  for (const med of activeMeds) {
    if (!latestActive.has(med.name)) latestActive.set(med.name, med);
  }

  const byPair = new Map(rows.map((r) => [`${r.drug_a}|${r.drug_b}`, r]));
  const conflicts = [];
  const seen = new Set();

  for (const newDrug of newDrugs) {
    for (const existingName of latestActive.keys()) {
      // A drug does not conflict with itself; a duplicate prescription is a
      // different problem and out of scope here.
      if (newDrug.name === existingName) continue;

      const [a, b] = orderPair(newDrug.name, existingName);
      const row = byPair.get(`${a}|${b}`);
      if (!row) continue;

      const key = `${newDrug.name}|${existingName}`;
      if (seen.has(key)) continue;
      seen.add(key);

      const existing = latestActive.get(existingName);

      conflicts.push({
        new_drug: newDrug.raw,
        existing_drug: existing.medicine_name,
        severity: row.severity,
        clinic_name: existing.clinic_name,
        prescribed_on: existing.visit_date,
        explanation: row.mechanism,
        suggested_alternative: row.suggested_alternative,
        source: 'TABLE',
        confidence: existing.confidence,
      });
    }
  }

  return conflicts;
}

function sortBySeverity(conflicts) {
  return conflicts.sort(
    (x, y) => (SEVERITY_RANK[x.severity] ?? 99) - (SEVERITY_RANK[y.severity] ?? 99)
  );
}

/**
 * Runs the full check for one pending set of prescriptions.
 *
 * @param {object} params
 * @param {string} params.patientId
 * @param {Array<{medicine_name: string}>} params.newPrescriptions
 * @returns {Promise<{conflicts: Array<object>, ai_available: boolean, ai_provider: string|null}>}
 */
async function checkInteractions({ patientId, newPrescriptions }) {
  const newDrugs = (newPrescriptions || [])
    .map((rx) => ({ raw: rx.medicine_name, name: normaliseDrugName(rx.medicine_name) }))
    .filter((d) => d.name);

  if (newDrugs.length === 0) {
    return { conflicts: [], ai_available: false, ai_provider: null };
  }

  const activeMeds = await getActiveMedications(patientId);
  const tableConflicts = await findTableConflicts(newDrugs, activeMeds);

  // ── AI leg plugs in here (Phase 4) ───────────────────────────
  // Call the provider adapter with { activeMeds, newDrugs, curated table },
  // merge its conflicts with tableConflicts by normalised pair (table severity
  // wins), and set ai_available / ai_provider from the result.
  // On ANY failure it must return the table conflicts unchanged — fail open.
  // ─────────────────────────────────────────────────────────────

  return {
    conflicts: sortBySeverity(tableConflicts),
    ai_available: false,
    ai_provider: null,
  };
}

module.exports = {
  checkInteractions,
  getActiveMedications,
  findTableConflicts,
};
