// backend/utils/doseSchedule.js
// ============================================================
// Deterministic dose-schedule parser — pure, no DB, no network.
// ============================================================
// parseDoseText(dosage, duration) → {
//   slots, food_relation, pills_per_dose, prn, prn_condition,
//   days, confidence   // CERTAIN | PARTIAL | NONE
// }
//
// Slots are a subset of SLOTS. The parser NEVER guesses a slot it
// cannot confidently derive — anything ambiguous returns NONE.
// Reuses prescriptionWindow.parseDurationDays for the duration field.
// ============================================================

'use strict';

const { parseDurationDays } = require('./prescriptionWindow');

const SLOTS = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];

// ── helpers ──────────────────────────────────────────────────────────────────

/** Lowercase + collapse whitespace for consistent matching. */
function norm(s) {
  return typeof s === 'string' ? s.toLowerCase().replace(/\s+/g, ' ').trim() : '';
}

// ── slot patterns ─────────────────────────────────────────────────────────────

/**
 * Tries the Indian numeric shorthand: 1-0-1, 1-1-1, 0-0-1, etc.
 * Four positions map to M-A-E-N. Three positions map to M-A-N.
 * Returns { slots, pills_per_dose } or null.
 */
function tryNumericShorthand(text) {
  // 4-part: M-A-E-N
  let m = text.match(/\b([01\d])-([01\d])-([01\d])-([01\d])\b/);
  if (m) {
    const parts = m.slice(1).map(Number);
    const labels = ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'];
    const slots = labels.filter((_, i) => parts[i] > 0);
    const pills = parts.find(p => p > 0) || 1;
    return slots.length ? { slots, pills_per_dose: pills } : null;
  }

  // 3-part: M-A(midday)-N
  m = text.match(/\b([01\d])-([01\d])-([01\d])\b/);
  if (m) {
    const parts = m.slice(1).map(Number);
    const labels = ['MORNING', 'AFTERNOON', 'NIGHT'];
    const slots = labels.filter((_, i) => parts[i] > 0);
    const pills = parts.find(p => p > 0) || 1;
    return slots.length ? { slots, pills_per_dose: pills } : null;
  }

  return null;
}

/**
 * Tries standard Latin abbreviations: OD, BD, TDS, QDS / QID.
 * Returns { slots } or null.
 */
function tryAbbreviation(text) {
  // Once daily
  if (/\bod\b/.test(text) || /\bonce\s+daily\b/.test(text) || /\bonce\s+a\s+day\b/.test(text)) {
    return { slots: ['MORNING'] };
  }
  // Twice daily
  if (/\bbd\b/.test(text) || /\bbid\b/.test(text) || /\btwice\s+daily\b/.test(text) || /\btwice\s+a\s+day\b/.test(text)) {
    return { slots: ['MORNING', 'NIGHT'] };
  }
  // Three times daily
  if (/\btds\b/.test(text) || /\btid\b/.test(text) || /\bthrice\s+daily\b/.test(text) || /\b3\s+times?\s+(a\s+)?day\b/.test(text)) {
    return { slots: ['MORNING', 'AFTERNOON', 'NIGHT'] };
  }
  // Four times daily
  if (/\bqds\b/.test(text) || /\bqid\b/.test(text) || /\b4\s+times?\s+(a\s+)?day\b/.test(text)) {
    return { slots: ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT'] };
  }
  return null;
}

/**
 * Tries natural-language slot mentions: "morning and night", "at bedtime", etc.
 * Returns { slots } or null. Returns null rather than guessing on partial matches.
 */
function tryNaturalSlots(text) {
  const hasMorning  = /\bmorning\b/.test(text);
  const hasAfternoon = /\b(afternoon|noon|midday|lunch)\b/.test(text);
  const hasEvening  = /\b(evening|evening\s+time)\b/.test(text);
  const hasNight    = /\b(night|bedtime|bed\s+time|hs\b|nocte)\b/.test(text);

  // "morning and night", "twice — morning + night"
  const slots = [
    hasMorning   && 'MORNING',
    hasAfternoon && 'AFTERNOON',
    hasEvening   && 'EVENING',
    hasNight     && 'NIGHT',
  ].filter(Boolean);

  return slots.length ? { slots } : null;
}

// ── food relation ─────────────────────────────────────────────────────────────

/**
 * Returns a food_relation string or null.
 */
function tryFoodRelation(text) {
  if (/\bbefore\s+(food|meal|meals|eating)\b/.test(text) || /\bempty\s+stomach\b/.test(text)) {
    return 'BEFORE';
  }
  if (/\bafter\s+(food|meal|meals|eating)\b/.test(text) || /\bpc\b/.test(text)) {
    return 'AFTER';
  }
  if (/\b(with\s+food|with\s+meal|with\s+meals|ac\b)\b/.test(text)) {
    return 'WITH';
  }
  return null;
}

// ── PRN (as-needed / SOS) ─────────────────────────────────────────────────────

/**
 * Detects SOS / PRN and tries to extract the condition (e.g. "if fever").
 * Returns { prn: true, prn_condition } or null.
 */
function tryPrn(text) {
  const isPrn = /\b(sos|prn|as\s+needed|as\s+required|when\s+needed|when\s+required)\b/.test(text);
  const condMatch = text.match(/\bif\s+([a-z\s]+?)(?:\s*[,.]|$)/) ||
                    text.match(/\bfor\s+([a-z\s]+?)(?:\s*[,.]|$)/);
  const prn_condition = condMatch ? condMatch[1].trim() : undefined;

  if (isPrn) {
    return { prn: true, prn_condition };
  }

  // "if fever", "if pain" without explicit SOS — still PRN
  if (condMatch && condMatch[1].trim().length < 30) {
    return { prn: true, prn_condition: condMatch[1].trim() };
  }

  return null;
}

// ── pills per dose ────────────────────────────────────────────────────────────

/**
 * Extracts an explicit pill count like "1 tablet", "2 tablets", "½ tab".
 * Returns a number or null. Numeric shorthand is handled in tryNumericShorthand.
 */
function tryPillsPerDose(text) {
  // "1 tab", "2 tablets", "half tablet"
  const m = text.match(/\b([\d.½¼]+)\s*(tab(?:let)?s?|cap(?:sule)?s?|pill?s?)\b/);
  if (m) {
    const raw = m[1];
    if (raw === '½') return 0.5;
    if (raw === '¼') return 0.25;
    const n = parseFloat(raw);
    return Number.isFinite(n) && n > 0 ? n : null;
  }
  return null;
}

// ── main export ───────────────────────────────────────────────────────────────

/**
 * Parse free-text dosage + duration into a structured schedule.
 *
 * @param {string} dosage   - e.g. "1-0-1 after food", "BD", "if fever SOS"
 * @param {string} duration - e.g. "5 days", "2 weeks", "3/7"
 * @returns {{
 *   slots: string[],
 *   food_relation: string|null,
 *   pills_per_dose: number|null,
 *   prn: boolean,
 *   prn_condition: string|undefined,
 *   days: number|null,
 *   confidence: 'CERTAIN'|'PARTIAL'|'NONE'
 * }}
 */
function parseDoseText(dosage, duration) {
  const text = norm(dosage);
  const result = {
    slots: [],
    food_relation: null,
    pills_per_dose: null,
    prn: false,
    prn_condition: undefined,
    days: parseDurationDays(duration),
    confidence: 'NONE',
  };

  // 1. PRN / SOS — check first; PRN overrides any slot logic
  const prnResult = tryPrn(text);
  if (prnResult) {
    result.prn = prnResult.prn;
    result.prn_condition = prnResult.prn_condition;
    result.food_relation = tryFoodRelation(text);
    result.pills_per_dose = tryPillsPerDose(text);
    // PRN with an identifiable condition = CERTAIN; without = PARTIAL
    result.confidence = prnResult.prn_condition ? 'CERTAIN' : 'PARTIAL';
    return result;
  }

  // 2. Numeric shorthand (1-0-1, 0-0-0-1, …)
  const numeric = tryNumericShorthand(text);
  if (numeric) {
    result.slots = numeric.slots;
    result.pills_per_dose = numeric.pills_per_dose;
    result.food_relation = tryFoodRelation(text);
    result.confidence = 'CERTAIN';
    return result;
  }

  // 3. Latin abbreviations (OD, BD, TDS, QDS…)
  const abbrev = tryAbbreviation(text);
  if (abbrev) {
    result.slots = abbrev.slots;
    result.food_relation = tryFoodRelation(text);
    result.pills_per_dose = tryPillsPerDose(text);
    result.confidence = 'CERTAIN';
    return result;
  }

  // 4. Natural language slot mentions
  const natural = tryNaturalSlots(text);
  if (natural) {
    result.slots = natural.slots;
    result.food_relation = tryFoodRelation(text);
    result.pills_per_dose = tryPillsPerDose(text);
    // Natural language is confident when it yields at least one slot
    result.confidence = 'CERTAIN';
    return result;
  }

  // 5. Nothing matched — return NONE. NEVER guess a slot.
  return result;
}

module.exports = { parseDoseText, SLOTS };
