// backend/utils/drugName.js
// ============================================================
// Drug name normalisation
// ============================================================
// Prescriptions are stored as free text (`medicine_name` bundles the
// strength, e.g. "Amoxicillin 500mg", "Tab. Paracetamol 650 mg"), and
// there is no generic name or drug code column. To compare a prescription
// against the curated interaction table we reduce both sides to a bare
// lowercase name.
//
// The seeder (scripts/seed-drug-interactions.js) and the checker
// (services/interactionChecker.js) MUST use this same function, or table
// lookups silently miss.
// ============================================================

'use strict';

// Dose forms and prefixes doctors commonly type around the actual name.
const FORM_WORDS = [
  'tab', 'tabs', 'tablet', 'tablets',
  'cap', 'caps', 'capsule', 'capsules',
  'syr', 'syp', 'syrup', 'susp', 'suspension', 'sol', 'solution',
  'inj', 'injection', 'inf', 'infusion', 'iv', 'im',
  'oint', 'ointment', 'cream', 'gel', 'lotion', 'drops', 'spray',
  'supp', 'suppository', 'sachet', 'powder', 'neb',
  'sr', 'xr', 'er', 'cr', 'dt', 'md',
];

const FORM_RE = new RegExp(`\\b(?:${FORM_WORDS.join('|')})\\b\\.?`, 'g');

// Strengths: 500mg, 5 ml, 1.5g, 40mcg, 10%, 100iu, 2.5mg/ml
const STRENGTH_RE = /\b\d+(?:\.\d+)?\s*(?:mg|mcg|µg|ug|g|ml|l|iu|u|%)(?:\s*\/\s*\d*\.?\d*\s*(?:mg|mcg|ml|l)?)?\b/g;

// A bare trailing number ("Paracetamol 650") once the unit has been stripped.
const BARE_NUMBER_RE = /\b\d+(?:\.\d+)?\b/g;

/**
 * Reduces a free-text medicine name to a normalised lookup key.
 *
 *   "Tab. Amoxicillin 500mg"  -> "amoxicillin"
 *   "IBUPROFEN 400 MG"        -> "ibuprofen"
 *   "Calcium Carbonate"       -> "calcium carbonate"
 *
 * Returns '' when nothing recognisable is left, so callers can skip the row.
 *
 * @param {string} raw
 * @returns {string}
 */
function normaliseDrugName(raw) {
  if (typeof raw !== 'string') return '';

  return raw
    .toLowerCase()
    .replace(/[()[\]{}]/g, ' ')
    .replace(STRENGTH_RE, ' ')
    .replace(FORM_RE, ' ')
    .replace(BARE_NUMBER_RE, ' ')
    .replace(/[^a-z\s-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Orders a pair alphabetically so a drug combination has exactly one key.
 * Mirrors the drug_a < drug_b invariant held in the drug_interactions table.
 *
 * @param {string} a - already normalised
 * @param {string} b - already normalised
 * @returns {[string, string]}
 */
function orderPair(a, b) {
  return a < b ? [a, b] : [b, a];
}

module.exports = {
  normaliseDrugName,
  orderPair,
};
