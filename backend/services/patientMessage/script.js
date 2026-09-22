// backend/services/patientMessage/script.js
// ============================================================
// Smart Prescriptions — the spoken script (Phase 3)
// ============================================================
// buildScript turns a saved record into the exact sentences the patient will
// hear. Deterministic: no DB, no network, no model.
//
// THE MODEL NEVER WRITES A WORD THE PATIENT HEARS. Every sentence is a
// template from backend/messages/prescription.<lang>.json with structured
// values slotted in, so a clinician can review the wording once and it is
// then identical for every patient. The AI leg's only job (Phase 2) was to
// fill the structured chips a doctor then confirmed.
//
// Two safety properties this file is responsible for:
//
//  1. FAIL CLOSED. A prescription whose schedule is unset, or a PRN row with
//     no condition, produces NO segment and instead lands in `blockers`.
//     Phase 5 refuses the send while `blockers` is non-empty. Nothing is ever
//     described vaguely — there is no literate reader downstream to catch it.
//
//  2. NO UNFILLED PLACEHOLDER SURVIVES. render() throws rather than speaking
//     a literal "{{days}}" at a patient.
//
// Every segment carries a `gloss`: the same sentence composed from the English
// templates. That is what the doctor reads in the preview to verify a Hindi or
// Tamil sentence they may not speak.
// ============================================================

'use strict';

const fs = require('fs');
const path = require('path');

const { resolveLanguage, SUPPORTED_CODES } = require('../../utils/language');
const { SLOTS } = require('../../utils/doseSchedule');
const { colourForIndex } = require('./palette');

const MESSAGES_DIR = path.join(__dirname, '..', '..', 'messages');
const GLOSS_LANGUAGE = 'en';

/** Raised when the templates and the composer disagree — a bug, not bad input. */
class ScriptTemplateError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ScriptTemplateError';
  }
}

// The contract between this composer and the three JSON files. The offline
// suite asserts all three languages carry exactly these keys, so a template
// added here without a Tamil translation fails a test rather than a send.
const TEMPLATE_KEYS = [
  'greeting',
  'scheduled',
  'dose',
  'dose_no_count',
  'food_clause',
  'days_clause',
  'prn',
  'closing',
  'slot_join',
  'slot_separator',
];
const TEMPLATE_MAPS = ['slots', 'food', 'colours', 'units', 'fractions', 'conditions'];

// Reasons a prescription cannot be spoken about. Phase 5 returns these to the
// client as SCHEDULE_INCOMPLETE.
const BLOCKER_NO_MEDICINE_NAME = 'NO_MEDICINE_NAME';
const BLOCKER_NO_SCHEDULE = 'NO_SCHEDULE';
const BLOCKER_NO_SCHEDULE_SOURCE = 'NO_SCHEDULE_SOURCE';
const BLOCKER_PRN_NO_CONDITION = 'PRN_NO_CONDITION';

// ── template loading ─────────────────────────────────────────────────────────

// Cached in production only, so editing the wording in development needs no
// restart — the same rule backend/services/ai/index.js applies to prompts.
const CACHE_TEMPLATES = process.env.NODE_ENV === 'production';
const templateCache = new Map();

/**
 * Loads prescription.<code>.json. Throws for an unknown code rather than
 * falling back silently — resolveLanguage has already narrowed the input to
 * en|hi|ta, so reaching here with anything else is a bug.
 */
function loadTemplates(code) {
  if (CACHE_TEMPLATES && templateCache.has(code)) return templateCache.get(code);

  if (!SUPPORTED_CODES.includes(code)) {
    throw new ScriptTemplateError(`No message templates for language "${code}"`);
  }

  const file = path.join(MESSAGES_DIR, `prescription.${code}.json`);
  let templates;
  try {
    templates = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    throw new ScriptTemplateError(`Could not read ${file}: ${err.message}`);
  }

  for (const key of TEMPLATE_KEYS) {
    if (typeof templates[key] !== 'string') {
      throw new ScriptTemplateError(`${file} is missing string key "${key}"`);
    }
  }
  for (const key of TEMPLATE_MAPS) {
    if (!templates[key] || typeof templates[key] !== 'object') {
      throw new ScriptTemplateError(`${file} is missing object key "${key}"`);
    }
  }

  if (CACHE_TEMPLATES) templateCache.set(code, templates);
  return templates;
}

// ── rendering ────────────────────────────────────────────────────────────────

const PLACEHOLDER = /\{\{\s*([a-z_]+)\s*\}\}/gi;

/**
 * Fills {{placeholders}} in one pass, so a value that happens to contain
 * braces is never re-scanned. Throws on any placeholder the caller did not
 * supply — speaking a literal "{{days}}" to a patient is worse than a 500.
 */
function render(template, vars) {
  const missing = [];
  const out = template.replace(PLACEHOLDER, (_match, key) => {
    const value = vars[key];
    if (value === undefined || value === null || value === '') {
      missing.push(key);
      return '';
    }
    return String(value);
  });

  if (missing.length) {
    throw new ScriptTemplateError(
      `Template "${template}" has no value for: ${missing.join(', ')}`
    );
  }
  return out.replace(/\s+/g, ' ').trim();
}

/** "morning, afternoon and night" — separator for all but the last join. */
function joinSlots(slots, templates) {
  const words = slots.map((slot) => {
    const word = templates.slots[slot];
    if (!word) throw new ScriptTemplateError(`No ${templates.language} word for slot "${slot}"`);
    return word;
  });
  if (words.length <= 1) return words[0] || '';
  return words.slice(0, -1).join(templates.slot_separator) + templates.slot_join + words[words.length - 1];
}

/**
 * The count and the noun that goes with it.
 * Fractions come from the `fractions` map because "0.5 tablets" is not
 * something any of the three languages says out loud.
 */
function renderPills(pills, templates) {
  const key = String(pills);
  if (templates.fractions[key]) {
    return { pills: templates.fractions[key], unit: templates.units.one };
  }
  return {
    pills: String(pills),
    unit: pills === 1 ? templates.units.one : templates.units.many,
  };
}

/**
 * The PRN condition. The doctor types it as free English text, so a curated
 * lexicon covers the common ones and anything else passes through untranslated
 * — an English word inside a Hindi sentence is imperfect but not a dosing
 * error, and the gloss shows the doctor exactly what will be said.
 */
function renderCondition(condition, templates) {
  const key = String(condition).trim().toLowerCase();
  return templates.conditions[key] || String(condition).trim();
}

// ── composition ──────────────────────────────────────────────────────────────

/**
 * One prescription → one spoken paragraph, in whichever language `templates`
 * holds. Called twice per row: once for the patient, once for the gloss.
 */
function composePrescription(med, templates) {
  const colour = templates.colours[med.colour.key];
  if (!colour) {
    throw new ScriptTemplateError(`No ${templates.language} word for colour "${med.colour.key}"`);
  }

  const sentences = [];

  if (med.prn) {
    sentences.push(render(templates.prn, {
      index: med.index,
      colour,
      condition: renderCondition(med.prn_condition, templates),
    }));
    // Deliberately no days_clause on a PRN row: "continue for 5 days" reads as
    // a standing instruction and contradicts "only if".
  } else {
    sentences.push(render(templates.scheduled, { index: med.index, colour }));

    const slots = joinSlots(med.slots, templates);
    if (med.pills_per_dose) {
      sentences.push(render(templates.dose, { slots, ...renderPills(med.pills_per_dose, templates) }));
    } else {
      sentences.push(render(templates.dose_no_count, { slots }));
    }

    if (med.days) {
      sentences.push(render(templates.days_clause, { days: med.days }));
    }
  }

  if (med.food_relation && templates.food[med.food_relation]) {
    sentences.push(render(templates.food_clause, { food: templates.food[med.food_relation] }));
  }

  return sentences.join(' ');
}

// ── input normalisation ──────────────────────────────────────────────────────

const text = (v) => (typeof v === 'string' ? v.trim() : '');

/**
 * Position is identity here: row N is always "medicine number N+1" in the
 * colour palette.js gives position N, blocked or not. Keeping blocked rows in
 * the list is what stops a refused row from renumbering the ones after it.
 */
function describeMedicines(prescriptions) {
  return (Array.isArray(prescriptions) ? prescriptions : []).map((rx, i) => ({
    position: i,
    index: i + 1, // what the patient hears
    prescription_id: rx && rx.id ? rx.id : null,
    medicine_name: text(rx && rx.medicine_name),
    colour: colourForIndex(i),
    // Sorted into the order of the day, not the order the column happened to
    // store them: "at night and in the morning" is a confusing instruction.
    slots: SLOTS.filter((slot) => Array.isArray(rx && rx.slots) && rx.slots.includes(slot)),
    food_relation: text(rx && rx.food_relation) || null,
    pills_per_dose: typeof (rx && rx.pills_per_dose) === 'number' ? rx.pills_per_dose : null,
    prn: Boolean(rx && rx.prn),
    prn_condition: text(rx && rx.prn_condition) || null,
    days: typeof (rx && rx.days) === 'number' ? rx.days : null,
    schedule_source: text(rx && rx.schedule_source) || null,
  }));
}

/** The fail-closed gate. Returns a reason string, or null when speakable. */
function blockerFor(med) {
  if (!med.medicine_name) return BLOCKER_NO_MEDICINE_NAME;
  if (!med.slots.length && !med.prn) return BLOCKER_NO_SCHEDULE;
  if (med.prn && !med.prn_condition) return BLOCKER_PRN_NO_CONDITION;
  if (!med.schedule_source) return BLOCKER_NO_SCHEDULE_SOURCE;
  return null;
}

// ── main export ──────────────────────────────────────────────────────────────

/**
 * Build the spoken script for one record.
 *
 * @param {object} record - { patient: { name, language_pref }, prescriptions: [...] }
 *   Prescription rows are the Prisma shape plus an optional `days` (the parsed
 *   duration); `duration` free text is not spoken.
 * @param {string} [language] - overrides record.patient.language_pref. Goes
 *   through resolveLanguage either way, so `supported` stays honest.
 *
 * @returns {{
 *   language_used: 'en'|'hi'|'ta',
 *   requested_language: string,
 *   supported: boolean,
 *   segments: Array<{ key: string, index: number|null, text: string, gloss: string }>,
 *   blockers: Array<{ position: number, index: number, prescription_id: string|null,
 *                     medicine_name: string, reason: string }>,
 *   medicines: Array<object>
 * }}
 */
function buildScript(record, language) {
  const patient = (record && record.patient) || {};
  const resolved = resolveLanguage(language !== undefined && language !== null && language !== ''
    ? language
    : patient.language_pref);

  const templates = loadTemplates(resolved.code);
  const glossTemplates = resolved.code === GLOSS_LANGUAGE
    ? templates
    : loadTemplates(GLOSS_LANGUAGE);

  const medicines = describeMedicines(record && record.prescriptions);
  const blockers = [];
  const segments = [];

  // The greeting is the one segment that can be dropped: it carries no
  // instruction, so a nameless patient simply hears the medicines.
  const name = text(patient.name);
  if (name) {
    segments.push({
      key: 'greeting',
      index: null,
      text: render(templates.greeting, { name }),
      gloss: render(glossTemplates.greeting, { name }),
    });
  }

  for (const med of medicines) {
    const reason = blockerFor(med);
    if (reason) {
      blockers.push({
        position: med.position,
        index: med.index,
        prescription_id: med.prescription_id,
        medicine_name: med.medicine_name,
        reason,
      });
      continue; // fail closed: no segment, nothing spoken about this row
    }

    segments.push({
      key: 'prescription',
      index: med.index,
      text: composePrescription(med, templates),
      gloss: composePrescription(med, glossTemplates),
    });
  }

  segments.push({
    key: 'closing',
    index: null,
    text: templates.closing,
    gloss: glossTemplates.closing,
  });

  return {
    language_used: resolved.code,
    requested_language: resolved.requested,
    supported: resolved.supported,
    segments,
    blockers,
    medicines,
  };
}

module.exports = {
  buildScript,
  loadTemplates,
  render,
  ScriptTemplateError,
  TEMPLATE_KEYS,
  TEMPLATE_MAPS,
  BLOCKER_NO_MEDICINE_NAME,
  BLOCKER_NO_SCHEDULE,
  BLOCKER_NO_SCHEDULE_SOURCE,
  BLOCKER_PRN_NO_CONDITION,
};
