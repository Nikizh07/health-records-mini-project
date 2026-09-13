// backend/services/interactionChecker.js
// ============================================================
// Cross-Clinic Medication Conflict Detector — core
// ============================================================
// Checks the drugs a doctor is about to prescribe against everything the
// patient is still taking, from EVERY clinic in the network.
//
// Two knowledge sources (see AI_DRUG_INTERACTION_PLAN.md):
//   1. the curated `drug_interactions` table — deterministic, no network,
//      always runs. This is the load-bearing safety component.
//   2. an optional AI leg (services/ai) that catches brand names,
//      misspellings and pairs the table does not list.
//
// Because the AI leg is allowed to fail open, nothing here may depend on it.
// ============================================================

'use strict';

const prisma = require('../config/prisma');
const { normaliseDrugName, orderPair } = require('../utils/drugName');
const { isLikelyActive } = require('../utils/prescriptionWindow');
const { isAiEnabled, complete, renderPrompt, parseConflicts } = require('./ai');

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
 * Two kinds of pair are checked:
 *   - EXISTING   — a new drug against something the patient is already on,
 *                  at any clinic. Carries that clinic's name and date.
 *   - SAME_VISIT — two drugs in THIS prescription conflicting with each
 *                  other. Neither has been dispensed yet, so there is no
 *                  source clinic or date to report.
 *
 * A drug pair is reported once, whichever leg finds it first, so a patient
 * already on both drugs does not produce the same warning twice.
 *
 * @param {Array<{raw: string, name: string}>} newDrugs
 * @param {Array} activeMeds - from getActiveMedications
 * @returns {Promise<Array<object>>} conflict objects
 */
async function findTableConflicts(newDrugs, activeMeds) {
  const newNames = [...new Set(newDrugs.map((d) => d.name))];
  const activeNames = [...new Set(activeMeds.map((m) => m.name))];

  // Note: no early return on an empty activeNames. A patient on nothing at
  // all can still be handed two drugs that conflict with each other.
  if (newNames.length === 0) return [];

  const rows = await prisma.drugInteraction.findMany({
    where: {
      OR: [
        { drug_a: { in: newNames }, drug_b: { in: activeNames } },
        { drug_a: { in: activeNames }, drug_b: { in: newNames } },
        // Both sides new — the same-visit case.
        { drug_a: { in: newNames }, drug_b: { in: newNames } },
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
  // Keyed by the ordered pair, so one interaction is reported once no matter
  // which leg or which drug ordering reaches it.
  const seenPairs = new Set();

  // ── a. A new drug vs something the patient is already taking ─
  for (const newDrug of newDrugs) {
    for (const existingName of latestActive.keys()) {
      // A drug does not conflict with itself; a duplicate prescription is a
      // different problem and out of scope here.
      if (newDrug.name === existingName) continue;

      const [a, b] = orderPair(newDrug.name, existingName);
      const key = `${a}|${b}`;
      const row = byPair.get(key);
      if (!row || seenPairs.has(key)) continue;
      seenPairs.add(key);

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
        scope: 'EXISTING',
      });
    }
  }

  // ── b. Two drugs in THIS prescription, against each other ────
  // Runs second so that when the patient is already on one of the pair, the
  // richer EXISTING conflict (it names a clinic and a date) is the one kept.
  for (let i = 0; i < newDrugs.length; i++) {
    for (let j = i + 1; j < newDrugs.length; j++) {
      const first = newDrugs[i];
      const second = newDrugs[j];
      if (first.name === second.name) continue;

      const [a, b] = orderPair(first.name, second.name);
      const key = `${a}|${b}`;
      const row = byPair.get(key);
      if (!row || seenPairs.has(key)) continue;
      seenPairs.add(key);

      conflicts.push({
        new_drug: first.raw,
        existing_drug: second.raw,
        severity: row.severity,
        // Neither drug has been dispensed, so there is no prescribing clinic
        // or date to point at — `scope` tells the client to say so.
        clinic_name: null,
        prescribed_on: null,
        explanation: row.mechanism,
        suggested_alternative: row.suggested_alternative,
        source: 'TABLE',
        // Both drugs are being written right now; nothing is being assumed
        // about whether a past course is still running.
        confidence: 'CERTAIN',
        scope: 'SAME_VISIT',
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
  const tableOnly = { conflicts: sortBySeverity(tableConflicts), ai_available: false, ai_provider: null };

  if (!isAiEnabled()) return tableOnly;

  try {
    const { conflicts, provider } = await findAiConflicts(newDrugs, activeMeds);
    return {
      conflicts: sortBySeverity(mergeConflicts(tableConflicts, conflicts)),
      ai_available: true,
      ai_provider: provider,
    };
  } catch (err) {
    // Fail open: the table result stands and the check is marked AI-unchecked.
    console.error('❌ AI interaction check failed:', err.message);
    return tableOnly;
  }
}

// ── AI leg ───────────────────────────────────────────────────

const bulletList = (lines) => (lines.length ? lines.map((l) => `- ${l}`).join('\n') : '(none)');

/**
 * Renders the drug-interaction prompt. Exported so scripts/test-ai-provider.js
 * renders exactly what production sends.
 */
function renderInteractionPrompt(newDrugs, activeMeds, tableRows) {
  return renderPrompt('drug-interaction', {
    activeMedications: bulletList(
      activeMeds.map((m) => [m.medicine_name, m.dosage, m.duration && `for ${m.duration}`].filter(Boolean).join(', '))
    ),
    newPrescriptions: bulletList(newDrugs.map((d) => d.raw)),
    interactionTable: bulletList(
      tableRows.map((r) => `${r.drug_a} + ${r.drug_b}: ${r.severity}. ${r.mechanism}`)
    ),
  });
}

async function findAiConflicts(newDrugs, activeMeds) {
  // ponytail: sends the whole curated table (56 rows, ~2k tokens); filter it
  // to the drugs involved once it grows into the hundreds.
  const tableRows = await prisma.drugInteraction.findMany({
    orderBy: [{ drug_a: 'asc' }, { drug_b: 'asc' }],
  });

  const { system, user } = renderInteractionPrompt(newDrugs, activeMeds, tableRows);
  const { text, provider } = await complete({ system, user, temperature: 0 });

  return { conflicts: attributeAiConflicts(parseConflicts(text), newDrugs, activeMeds), provider };
}

/**
 * Turns the model's name pairs into full conflict objects. The clinic, date,
 * scope and confidence come from the patient's real data, never from the
 * model, and a pair naming a drug that is in neither list is dropped.
 */
function attributeAiConflicts(aiConflicts, newDrugs, activeMeds) {
  const newByName = new Map(newDrugs.map((d) => [d.name, d]));
  const activeByName = new Map();
  for (const med of activeMeds) {
    if (!activeByName.has(med.name)) activeByName.set(med.name, med); // newest first
  }

  const conflicts = [];

  for (const c of aiConflicts) {
    const x = normaliseDrugName(c.new_drug);
    const y = normaliseDrugName(c.existing_drug);
    if (!x || !y || x === y) continue;

    // The model may swap which side is new, so try both orientations.
    let newDrug;
    let existing;
    if (newByName.has(x) && activeByName.has(y)) [newDrug, existing] = [newByName.get(x), activeByName.get(y)];
    else if (newByName.has(y) && activeByName.has(x)) [newDrug, existing] = [newByName.get(y), activeByName.get(x)];

    const base = {
      severity: c.severity,
      explanation: c.explanation,
      suggested_alternative: c.suggested_alternative,
      source: 'AI',
    };

    if (existing) {
      conflicts.push({
        ...base,
        new_drug: newDrug.raw,
        existing_drug: existing.medicine_name,
        clinic_name: existing.clinic_name,
        prescribed_on: existing.visit_date,
        confidence: existing.confidence,
        scope: 'EXISTING',
      });
    } else if (newByName.has(x) && newByName.has(y)) {
      conflicts.push({
        ...base,
        new_drug: newByName.get(x).raw,
        existing_drug: newByName.get(y).raw,
        clinic_name: null,
        prescribed_on: null,
        confidence: 'CERTAIN',
        scope: 'SAME_VISIT',
      });
    }
  }

  return conflicts;
}

/**
 * One conflict per unordered drug pair. Where the table and the model both
 * flag a pair, the table's severity wins and the model's prose is kept.
 */
function mergeConflicts(tableConflicts, aiConflicts) {
  const pairKey = (c) => orderPair(normaliseDrugName(c.new_drug), normaliseDrugName(c.existing_drug)).join('|');
  const merged = new Map(tableConflicts.map((c) => [pairKey(c), c]));

  for (const ai of aiConflicts) {
    const key = pairKey(ai);
    const known = merged.get(key);
    if (!known) {
      merged.set(key, ai);
    } else if (known.source === 'TABLE') {
      merged.set(key, {
        ...known,
        explanation: ai.explanation,
        suggested_alternative: ai.suggested_alternative || known.suggested_alternative,
      });
    }
  }

  return [...merged.values()];
}

module.exports = {
  checkInteractions,
  getActiveMedications,
  findTableConflicts,
  renderInteractionPrompt,
  parseConflicts,
};
