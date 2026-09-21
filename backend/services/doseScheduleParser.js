// backend/services/doseScheduleParser.js
// ============================================================
// Smart Prescriptions — the AI autofill leg (Phase 2)
// ============================================================
// Turns the free text a doctor already typed into structured dose-schedule
// chips they confirm with a glance. Shaped like interactionChecker.js: a
// deterministic core that always runs, plus an optional AI leg.
//
// The one rule that makes this safe to autofill:
//
//   THE MODEL MAY ONLY FILL GAPS.
//
// utils/doseSchedule.parseDoseText runs FIRST on every row, and that result
// is the fallback — it exists before the AI is touched. Wherever the regex
// filled a field, the model's answer for that field is discarded. The model
// never overrides a deterministic hit and never introduces a medicine that
// is not in the request, the same clamp attributeAiConflicts applies to the
// interaction checker.
//
// Unlike the drug-interaction checker, which fails open, the feature this
// feeds fails CLOSED: an AI outage here leaves rows with no schedule, and
// Phase 5 refuses to send a prescription whose schedule is still unset.
// So there is nothing to do on failure but return the deterministic parse.
// ============================================================

'use strict';

const { parseDoseText, SLOTS } = require('../utils/doseSchedule');
const { isAiEnabled, complete, renderPrompt, extractJsonObject, AiUnavailableError } = require('./ai');

const SLOT_SET = new Set(SLOTS);
const FOOD_RELATIONS = new Set(['BEFORE', 'AFTER', 'WITH', 'ANY']);

// How the schedule on a row was arrived at. DOCTOR is set by the client when
// the doctor edits a chip by hand; nothing in this file ever produces it.
const SOURCE_PARSED = 'PARSED';
const SOURCE_AI = 'AI';

const MAX_CONDITION_LENGTH = 60;

// ── request normalisation ────────────────────────────────────────────────────

/**
 * One clean row per INPUT element, order and length preserved — a row the
 * caller sent with no medicine name keeps its position with an empty name.
 * The client autofills chips by index, so dropping a row here would shift
 * every answer after it onto the wrong prescription.
 */
function normaliseRows(prescriptions) {
  return (Array.isArray(prescriptions) ? prescriptions : []).map((rx) => ({
    medicine_name: rx && typeof rx.medicine_name === 'string' ? rx.medicine_name.trim() : '',
    dosage: rx && rx.dosage ? String(rx.dosage).trim() : '',
    duration: rx && rx.duration ? String(rx.duration).trim() : '',
  }));
}

/** The named rows only — what is worth sending to a model. */
const namedRows = (rows) => rows.filter((rx) => rx.medicine_name);

/**
 * The deterministic parse, in the shape the API and the Prisma columns use.
 * `schedule_source` is the audit trail Phase 5 reads: null means nothing
 * placed this row's schedule, and nothing may be spoken about it.
 */
function deterministicSchedule(rx) {
  // A row with no medicine name is not a prescription; there is nothing to
  // schedule and nothing that could later be spoken about it.
  if (!rx.medicine_name) {
    return {
      medicine_name: '',
      slots: [],
      food_relation: null,
      pills_per_dose: null,
      prn: false,
      prn_condition: null,
      days: null,
      confidence: 'NONE',
      schedule_source: null,
    };
  }

  const parsed = parseDoseText(rx.dosage, rx.duration);
  const placed = parsed.slots.length > 0 || parsed.prn;

  return {
    medicine_name: rx.medicine_name,
    slots: parsed.slots,
    food_relation: parsed.food_relation,
    pills_per_dose: parsed.pills_per_dose,
    prn: parsed.prn,
    prn_condition: parsed.prn_condition ?? null,
    days: parsed.days,
    confidence: parsed.confidence,
    schedule_source: placed ? SOURCE_PARSED : null,
  };
}

// ── prompt ───────────────────────────────────────────────────────────────────

const bulletList = (lines) => (lines.length ? lines.map((l) => `- ${l}`).join('\n') : '(none)');

/**
 * Renders the dose-schedule prompt. Exported so a smoke test sends exactly
 * what production sends, as renderInteractionPrompt is.
 */
function renderSchedulePrompt(prescriptions) {
  // Numbered contiguously over the rows actually sent, so the model is never
  // asked about a gap. parseSchedules maps those indices back to its own.
  const rows = namedRows(normaliseRows(prescriptions));
  return renderPrompt('dose-schedule', {
    prescriptions: bulletList(
      rows.map((rx, i) =>
        [
          `index ${i}`,
          `medicine_name: ${rx.medicine_name}`,
          `dosage text: ${rx.dosage || '(blank)'}`,
          `duration text: ${rx.duration || '(blank)'}`,
        ].join(' | ')
      )
    ),
  });
}

// ── model output ─────────────────────────────────────────────────────────────

const isText = (v) => typeof v === 'string' && v.trim() !== '';

/**
 * Pulls `{ "schedules": [...] }` out of model text, tolerating code fences,
 * surrounding prose and <think> blocks. Unusable output throws
 * AiUnavailableError so it is handled exactly like an outage.
 */
function parseAiSchedules(text) {
  const json = extractJsonObject(String(text).replace(/<think>[\s\S]*?<\/think>/g, ''));

  let parsed;
  try {
    parsed = JSON.parse(json);
  } catch (err) {
    throw new AiUnavailableError('AI response contained no usable JSON', err);
  }
  if (!parsed || !Array.isArray(parsed.schedules)) {
    throw new AiUnavailableError('AI response has no "schedules" array');
  }

  return parsed.schedules.filter((s) => s && Number.isInteger(s.index) && s.index >= 0);
}

/** Only the values this system recognises survive; everything else is dropped. */
function sanitiseSuggestion(raw) {
  const slots = Array.isArray(raw.slots)
    ? SLOTS.filter((slot) => raw.slots.some((s) => isText(s) && s.trim().toUpperCase() === slot))
    : [];

  const food = isText(raw.food_relation) ? raw.food_relation.trim().toUpperCase() : null;
  const pills = Number(raw.pills_per_dose);
  const days = Number(raw.days);
  const condition = isText(raw.prn_condition) ? raw.prn_condition.trim() : null;

  return {
    slots,
    food_relation: FOOD_RELATIONS.has(food) ? food : null,
    pills_per_dose: Number.isFinite(pills) && pills > 0 ? pills : null,
    prn: raw.prn === true,
    prn_condition: condition && condition.length <= MAX_CONDITION_LENGTH ? condition : null,
    days: Number.isInteger(days) && days > 0 ? days : null,
  };
}

/**
 * Merges one model suggestion into one deterministic row, gaps only.
 *
 * A field the regex filled is never touched. A row where the regex already
 * placed a schedule (slots or PRN) keeps `schedule_source: 'PARSED'`, even
 * when the model contributes a detail like food_relation — the provenance
 * that matters is what decided WHEN the patient takes the medicine.
 *
 * @returns {boolean} whether the model placed this row's schedule
 */
function fillGaps(row, suggestion) {
  const regexPlacedSchedule = row.slots.length > 0 || row.prn;
  let aiPlacedSchedule = false;

  if (!regexPlacedSchedule) {
    if (suggestion.prn) {
      // PRN overrides slots, as it does in parseDoseText.
      row.prn = true;
      row.prn_condition = suggestion.prn_condition;
      aiPlacedSchedule = true;
    } else if (suggestion.slots.length > 0) {
      row.slots = suggestion.slots;
      aiPlacedSchedule = true;
    }
  } else if (row.prn && row.prn_condition === null && suggestion.prn && suggestion.prn_condition) {
    // The regex saw "SOS" but no trigger; the model may name the trigger.
    // It does not change WHEN the medicine is taken, so the row stays PARSED.
    row.prn_condition = suggestion.prn_condition;
  }

  if (row.food_relation === null) row.food_relation = suggestion.food_relation;
  if (row.pills_per_dose === null) row.pills_per_dose = suggestion.pills_per_dose;
  if (row.days === null) row.days = suggestion.days;

  if (aiPlacedSchedule) {
    row.schedule_source = SOURCE_AI;
    // An AI-derived schedule is a suggestion the doctor still has to confirm,
    // so it is never CERTAIN however sure the model sounded.
    row.confidence = 'PARTIAL';
  }

  return aiPlacedSchedule;
}

// ── main export ──────────────────────────────────────────────────────────────

/**
 * Parses free-text dosage/duration into structured schedules, one per input
 * prescription, in input order.
 *
 * @param {object} params
 * @param {Array<{medicine_name: string, dosage?: string, duration?: string}>} params.prescriptions
 * @returns {Promise<{schedules: Array<object>, ai_available: boolean, ai_provider: string|null}>}
 */
async function parseSchedules({ prescriptions }) {
  const rows = normaliseRows(prescriptions);

  // 1. The deterministic parse runs first and IS the fallback. Everything
  //    below is an improvement on a result that already exists.
  const schedules = rows.map(deterministicSchedule);
  const deterministicOnly = { schedules, ai_available: false, ai_provider: null };

  // The prompt is numbered over the named rows only; this maps the model's
  // index back to the response row it belongs to.
  const sent = rows
    .map((rx, i) => ({ rx, scheduleIndex: i }))
    .filter(({ rx }) => rx.medicine_name);

  if (sent.length === 0 || !isAiEnabled()) return deterministicOnly;

  try {
    const { system, user } = renderSchedulePrompt(sent.map(({ rx }) => rx));
    const { text, provider } = await complete({ system, user, temperature: 0 });

    for (const raw of parseAiSchedules(text)) {
      const target = sent[raw.index];
      if (!target) continue; // an index outside what was sent — dropped, never shifted
      const row = schedules[target.scheduleIndex];
      // The model must name the medicine at that index. This is the clamp
      // that stops a hallucinated drug from carrying a schedule into the row.
      if (!isText(raw.medicine_name) || raw.medicine_name.trim() !== row.medicine_name) continue;

      fillGaps(row, sanitiseSuggestion(raw));
    }

    return { schedules, ai_available: true, ai_provider: provider };
  } catch (err) {
    // Nothing to fail open into: the deterministic parse is already the answer,
    // and a row it could not place stays unplaced so Phase 5 refuses to send it.
    console.error('❌ AI dose-schedule autofill failed:', err.message);
    return deterministicOnly;
  }
}

module.exports = {
  parseSchedules,
  renderSchedulePrompt,
};
