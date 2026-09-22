// backend/services/patientMessage/pictogram.js
// ============================================================
// Smart Prescriptions — the dose chart (Phase 3)
// ============================================================
// A deterministic SVG composer: one row per medicine, one column per slot of
// the day, a pill glyph in the cells that apply.
//
// NEVER AI IMAGE GENERATION. A model that renders three pills where the
// prescription says one is a patient-safety bug with no reviewer downstream.
// Every glyph below is a hand-written path committed to this repo; nothing is
// fetched at render time and the same input always produces the same bytes.
//
// The chart carries NO WORDS — only glyphs and numerals. That is the point
// (the patient cannot read), and it also sidesteps the rasteriser needing a
// Devanagari or Tamil font to be installed.
//
// The row head repeats the number and the colour that script.js speaks, both
// taken from palette.js, so the chart and the audio cannot disagree.
//
// rasterise() is the one component in this feature allowed to fail SOFT: the
// chart is an aid, the audio is the instruction. If @resvg/resvg-js is not
// installed it returns null and Phase 5 sends audio + text only.
// ============================================================

'use strict';

const { PALETTE } = require('./palette');
const { SLOTS } = require('../../utils/doseSchedule');

// ── geometry ─────────────────────────────────────────────────────────────────

const MARGIN = 20;
const HEAD_W = 170;   // number + colour swatch
const COL_W = 160;    // one slot of the day
const DAYS_W = 110;   // how many days to continue
const HEADER_H = 96;
const ROW_H = 132;
const PAGE_W = MARGIN * 2 + HEAD_W + COL_W * SLOTS.length + DAYS_W;

const INK = '#1f2937';
const RULE = '#cbd5e1';
const PAPER = '#ffffff';
const BAND = '#f1f5f9';
const MUTED = '#94a3b8';

// The raster width. 960 → 960: 1:1, which keeps the glyph strokes crisp on the
// phone screens this is actually viewed on.
const RASTER_WIDTH = PAGE_W;

// ── glyphs ───────────────────────────────────────────────────────────────────
// Each is drawn around a local origin and positioned by a translate().

/** n evenly spaced rays around (0,0), between radius r0 and r1. */
function rays(n, r0, r1, stroke = INK) {
  const out = [];
  for (let i = 0; i < n; i++) {
    const a = (Math.PI * 2 * i) / n;
    const x0 = (Math.cos(a) * r0).toFixed(1);
    const y0 = (Math.sin(a) * r0).toFixed(1);
    const x1 = (Math.cos(a) * r1).toFixed(1);
    const y1 = (Math.sin(a) * r1).toFixed(1);
    out.push(`<line x1="${x0}" y1="${y0}" x2="${x1}" y2="${y1}" stroke="${stroke}" stroke-width="3" stroke-linecap="round"/>`);
  }
  return out.join('');
}

/** Sun on the horizon with an arrow: up = rising (morning), down = setting (evening). */
function sunOnHorizon(direction) {
  const arrow = direction === 'up'
    ? '<path d="M 26 4 L 26 -12 M 20 -6 L 26 -12 L 32 -6" fill="none" stroke="#334155" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'
    : '<path d="M 26 -12 L 26 4 M 20 -2 L 26 4 L 32 -2" fill="none" stroke="#334155" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>';
  return [
    `<g transform="translate(0,4)">${rays(8, 15, 22)}</g>`,
    '<circle cx="0" cy="4" r="12" fill="#facc15" stroke="#ca8a04" stroke-width="2"/>',
    `<line x1="-34" y1="20" x2="34" y2="20" stroke="${INK}" stroke-width="3" stroke-linecap="round"/>`,
    arrow,
  ].join('');
}

/** Sun high overhead — midday. */
function sunHigh() {
  return [
    rays(8, 16, 24),
    '<circle cx="0" cy="0" r="13" fill="#facc15" stroke="#ca8a04" stroke-width="2"/>',
  ].join('');
}

/**
 * Crescent moon with one star — night.
 * The crescent is a disc with a second disc masked out of it. A two-arc path
 * is the shorter spelling but renders as an empty or filled circle depending
 * on how the rasteriser resolves the arc flags; the mask is unambiguous.
 */
function moon() {
  return [
    '<mask id="moon-cut" maskUnits="userSpaceOnUse" x="-20" y="-20" width="40" height="40">',
    '<rect x="-20" y="-20" width="40" height="40" fill="#ffffff"/>',
    '<circle cx="9" cy="-5" r="13" fill="#000000"/>',
    '</mask>',
    '<circle cx="0" cy="0" r="15" fill="#475569" mask="url(#moon-cut)"/>',
    '<path d="M 24 -13 l 2.5 5.5 5.5 2.5 -5.5 2.5 -2.5 5.5 -2.5 -5.5 -5.5 -2.5 5.5 -2.5 z" fill="#94a3b8"/>',
  ].join('');
}

/** A whole tablet, tilted, with the score line. */
function pill(fill) {
  return `<g transform="rotate(-30)">
      <rect x="-19" y="-9" width="38" height="18" rx="9" fill="${fill}" stroke="#334155" stroke-width="2.5"/>
      <line x1="0" y1="-8" x2="0" y2="8" stroke="#334155" stroke-width="2.5"/>
    </g>`;
}

/**
 * Half a tablet: the WHOLE capsule outlined, with only the half that is taken
 * filled in. Drawing just the fragment on its own reads as a small pill rather
 * than as half of one — the whole outline is what makes it a fraction.
 */
function halfPill(fill) {
  return `<g transform="rotate(-30)">
      <rect x="-19" y="-9" width="38" height="18" rx="9" fill="${PAPER}" stroke="#334155" stroke-width="2.5"/>
      <path d="M 0 -9 L -10 -9 A 9 9 0 0 0 -10 9 L 0 9 Z" fill="${fill}"/>
      <line x1="0" y1="-9" x2="0" y2="8.5" stroke="#334155" stroke-width="2.5"/>
    </g>`;
}

/** Calendar page — the "continue for N days" column header. */
function calendar() {
  return `<g stroke="${INK}" stroke-width="3" fill="none" stroke-linejoin="round">
      <rect x="-20" y="-16" width="40" height="36" rx="4" fill="${PAPER}"/>
      <line x1="-20" y1="-5" x2="20" y2="-5"/>
      <line x1="-11" y1="-23" x2="-11" y2="-11"/>
      <line x1="11" y1="-23" x2="11" y2="-11"/>
    </g>`;
}

/** "Only when needed" — the PRN band's marker. */
function alertGlyph() {
  return `<g>
      <circle cx="0" cy="0" r="19" fill="#fef3c7" stroke="#b45309" stroke-width="3"/>
      <line x1="0" y1="-9" x2="0" y2="4" stroke="#b45309" stroke-width="4" stroke-linecap="round"/>
      <circle cx="0" cy="11" r="2.5" fill="#b45309"/>
    </g>`;
}

const SLOT_GLYPH = {
  MORNING: () => sunOnHorizon('up'),
  AFTERNOON: sunHigh,
  EVENING: () => sunOnHorizon('down'),
  NIGHT: moon,
};

// ── cell contents ────────────────────────────────────────────────────────────

/**
 * The pills in one cell. Small whole counts are drawn literally, because
 * counting glyphs is the one thing this chart does that words cannot. Anything
 * else falls back to one glyph plus a numeral — and the audio always states
 * the exact count regardless.
 */
function pillsInCell(count, fill) {
  const n = typeof count === 'number' && count > 0 ? count : 1;

  if (n === 0.5) return halfPill(fill);

  if (Number.isInteger(n) && n <= 3) {
    const spread = 42;
    const start = -((n - 1) * spread) / 2;
    return Array.from({ length: n }, (_, i) =>
      `<g transform="translate(${(start + i * spread).toFixed(1)},0)">${pill(fill)}</g>`
    ).join('');
  }

  return `${pill(fill)}<text x="30" y="8" font-family="sans-serif" font-size="26" font-weight="700" fill="${INK}">${escapeText(`×${n}`)}</text>`;
}

// ── SVG assembly ─────────────────────────────────────────────────────────────

function escapeText(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}

/**
 * Build the dose chart.
 *
 * @param {Array<object>} schedules - the `medicines` array buildScript returns
 *   (position, index, colour, slots, pills_per_dose, prn, days). Rows are drawn
 *   in the order given; `index` is what the audio speaks.
 * @param {Array<object>} [palette] - accepted for symmetry with the plan's
 *   signature. Each row already carries its own colour from palette.js; this
 *   only supplies a colour for a row that somehow arrived without one.
 * @returns {string} standalone SVG
 */
function buildSvg(schedules, palette = PALETTE) {
  const rows = Array.isArray(schedules) ? schedules : [];
  const pageH = MARGIN * 2 + HEADER_H + Math.max(rows.length, 1) * ROW_H;
  const gridX = MARGIN + HEAD_W;

  const parts = [];
  parts.push(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${PAGE_W}" height="${pageH}" viewBox="0 0 ${PAGE_W} ${pageH}">`,
    `<rect width="${PAGE_W}" height="${pageH}" fill="${PAPER}"/>`
  );

  // ── header: one glyph per slot, then the calendar ──
  const headerY = MARGIN + HEADER_H / 2;
  SLOTS.forEach((slot, i) => {
    const cx = gridX + COL_W * i + COL_W / 2;
    parts.push(`<g transform="translate(${cx},${headerY})">${SLOT_GLYPH[slot]()}</g>`);
  });
  parts.push(
    `<g transform="translate(${gridX + COL_W * SLOTS.length + DAYS_W / 2},${headerY})">${calendar()}</g>`
  );

  // ── rows ──
  rows.forEach((row, i) => {
    const y = MARGIN + HEADER_H + ROW_H * i;
    const mid = y + ROW_H / 2;
    const colour = row && row.colour ? row.colour : palette[i % palette.length];
    const idx = row && row.index != null ? row.index : i + 1;

    parts.push(`<g class="rx-row" data-rx-index="${escapeText(idx)}">`);

    if (i % 2 === 1) {
      parts.push(`<rect x="${MARGIN}" y="${y}" width="${PAGE_W - MARGIN * 2}" height="${ROW_H}" fill="${BAND}"/>`);
    }

    // Row head: the spoken number inside the spoken colour.
    parts.push(
      `<circle cx="${MARGIN + 52}" cy="${mid}" r="34" fill="${colour.hex}" stroke="#334155" stroke-width="3"/>`,
      `<text x="${MARGIN + 52}" y="${mid + 15}" text-anchor="middle" font-family="sans-serif" font-size="42" font-weight="700" fill="${colour.ink}">${escapeText(idx)}</text>`,
      `<rect x="${MARGIN + 100}" y="${mid - 22}" width="46" height="44" rx="8" fill="${colour.hex}" stroke="#334155" stroke-width="3"/>`
    );

    if (row && row.prn) {
      // PRN has no time of day. One band across every slot column, marked
      // "only when needed" — never a pill sitting in a slot it was not given.
      const bandX = gridX + 12;
      const bandW = COL_W * SLOTS.length - 24;
      parts.push(
        `<rect x="${bandX}" y="${mid - 40}" width="${bandW}" height="80" rx="14" fill="#fffbeb" stroke="#b45309" stroke-width="3" stroke-dasharray="10 7"/>`,
        `<g transform="translate(${bandX + 52},${mid})">${alertGlyph()}</g>`,
        `<g transform="translate(${bandX + 130},${mid})">${pillsInCell(row.pills_per_dose, colour.hex)}</g>`
      );
    } else {
      const slots = row && Array.isArray(row.slots) ? row.slots : [];
      SLOTS.forEach((slot, c) => {
        if (!slots.includes(slot)) return;
        const cx = gridX + COL_W * c + COL_W / 2;
        parts.push(
          `<g transform="translate(${cx},${mid})">${pillsInCell(row && row.pills_per_dose, colour.hex)}</g>`
        );
      });
    }

    // Days column — numeral only; the calendar glyph in the header says what
    // the number means. A row with no parsed duration leaves it blank.
    const daysX = gridX + COL_W * SLOTS.length + DAYS_W / 2;
    const days = row && typeof row.days === 'number' && row.days > 0 ? row.days : null;
    parts.push(
      days !== null
        ? `<text x="${daysX}" y="${mid + 14}" text-anchor="middle" font-family="sans-serif" font-size="40" font-weight="700" fill="${INK}">${escapeText(days)}</text>`
        : `<line x1="${daysX - 18}" y1="${mid}" x2="${daysX + 18}" y2="${mid}" stroke="${MUTED}" stroke-width="4" stroke-linecap="round"/>`
    );

    parts.push('</g>');
  });

  // ── rules, drawn last so they sit over the banding ──
  const gridTop = MARGIN + HEADER_H;
  const gridBottom = gridTop + Math.max(rows.length, 1) * ROW_H;
  for (let c = 0; c <= SLOTS.length + 1; c++) {
    const x = c <= SLOTS.length ? gridX + COL_W * c : gridX + COL_W * SLOTS.length + DAYS_W;
    parts.push(`<line x1="${x}" y1="${MARGIN}" x2="${x}" y2="${gridBottom}" stroke="${RULE}" stroke-width="2"/>`);
  }
  for (let r = 0; r <= Math.max(rows.length, 1); r++) {
    const y = gridTop + ROW_H * r;
    parts.push(`<line x1="${MARGIN}" y1="${y}" x2="${PAGE_W - MARGIN}" y2="${y}" stroke="${RULE}" stroke-width="2"/>`);
  }
  parts.push(
    `<rect x="${MARGIN}" y="${MARGIN}" width="${PAGE_W - MARGIN * 2}" height="${gridBottom - MARGIN}" fill="none" stroke="${INK}" stroke-width="3"/>`
  );

  parts.push('</svg>');
  return parts.join('');
}

// ── rasterisation ────────────────────────────────────────────────────────────

/**
 * SVG → PNG, or null.
 *
 * @resvg/resvg-js is an optionalDependency, required lazily exactly like the
 * AWS SDKs in the AI providers, so `npm install --no-optional` and platforms
 * with no prebuilt binary still boot. Returning null is a supported outcome,
 * not an error: the send proceeds with audio + text only.
 *
 * @param {string} svg
 * @returns {Promise<Buffer|null>}
 */
async function rasterise(svg) {
  let Resvg;
  try {
    ({ Resvg } = require('@resvg/resvg-js'));
  } catch (err) {
    console.warn('[pictogram] @resvg/resvg-js not installed — sending without the chart');
    return null;
  }

  try {
    const resvg = new Resvg(svg, {
      fitTo: { mode: 'width', value: RASTER_WIDTH },
      background: PAPER,
    });
    return Buffer.from(resvg.render().asPng());
  } catch (err) {
    console.warn(`[pictogram] rasterise failed — sending without the chart: ${err.message}`);
    return null;
  }
}

module.exports = {
  buildSvg,
  rasterise,
  PAGE_W,
  ROW_H,
  HEADER_H,
};
