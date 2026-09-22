// backend/services/patientMessage/palette.js
// ============================================================
// Smart Prescriptions — pill identity (Phase 3)
// ============================================================
// A patient who cannot read needs to know WHICH medicine a sentence is about.
// The app holds no clinical data about what a tablet actually looks like, so
// the colour here is not a claim about the pill — it is a LABEL assigned to
// the medicine's position on the chart, and the audio names the same label
// ("medicine number one, the blue one").
//
// That only works if the chart and the script agree, which is why both
// script.js and pictogram.js read the assignment from this one module rather
// than each picking their own. The assignment is a pure function of the index,
// so the same record always produces the same chart and the same words.
//
// `name_key` indexes `colours` in backend/messages/prescription.<lang>.json.
// ============================================================

'use strict';

// Ordered by how far apart they read at a glance, not by hue. The first four
// carry the common case — most visits are one to four medicines.
const PALETTE = [
  { key: 'BLUE',   hex: '#2563eb', ink: '#ffffff' },
  { key: 'RED',    hex: '#dc2626', ink: '#ffffff' },
  { key: 'GREEN',  hex: '#16a34a', ink: '#ffffff' },
  { key: 'YELLOW', hex: '#eab308', ink: '#1f2937' },
  { key: 'WHITE',  hex: '#f8fafc', ink: '#1f2937' },
  { key: 'ORANGE', hex: '#ea580c', ink: '#ffffff' },
  { key: 'PURPLE', hex: '#7c3aed', ink: '#ffffff' },
  { key: 'PINK',   hex: '#db2777', ink: '#ffffff' },
];

/**
 * The colour label for a zero-based prescription position.
 * Wraps past the end of the palette: a visit with more than eight medicines
 * reuses colours, but the spoken NUMBER is still unique, and the number is
 * what the sentence leads with.
 *
 * @param {number} index - zero-based
 * @returns {{ key: string, hex: string, ink: string }}
 */
function colourForIndex(index) {
  const i = Number.isInteger(index) && index >= 0 ? index : 0;
  return PALETTE[i % PALETTE.length];
}

module.exports = { PALETTE, colourForIndex };
