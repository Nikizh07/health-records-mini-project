// backend/scripts/test-patient-message.js
// Offline regression suite for Smart Prescriptions Phase 3:
//   messages/prescription.{en,hi,ta}.json
//   services/patientMessage/{palette,script,pictogram}.js
// No DB, no network, no credentials.
//   node scripts/test-patient-message.js
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');

const {
  buildScript,
  loadTemplates,
  render,
  ScriptTemplateError,
  TEMPLATE_KEYS,
  TEMPLATE_MAPS,
  BLOCKER_NO_SCHEDULE,
  BLOCKER_NO_SCHEDULE_SOURCE,
  BLOCKER_PRN_NO_CONDITION,
  BLOCKER_NO_MEDICINE_NAME,
} = require('../services/patientMessage/script');
const { buildSvg, rasterise } = require('../services/patientMessage/pictogram');
const { PALETTE, colourForIndex } = require('../services/patientMessage/palette');
const { SLOTS } = require('../utils/doseSchedule');

const LANGUAGES = ['en', 'hi', 'ta'];

let passed = 0;
let failed = 0;

function check(label, actual, expected) {
  try {
    assert.deepStrictEqual(actual, expected);
    console.log(`  ✅  ${label}`);
    passed++;
  } catch (err) {
    console.error(`  ❌  ${label}`);
    console.error(`      expected: ${JSON.stringify(expected)}`);
    console.error(`      received: ${JSON.stringify(actual)}`);
    failed++;
  }
}

function ok(label, condition, detail) {
  check(label + (detail ? ` (${detail})` : ''), Boolean(condition), true);
}

function throws(label, fn) {
  try {
    fn();
    console.error(`  ❌  ${label} — expected a throw, got none`);
    failed++;
  } catch (err) {
    console.log(`  ✅  ${label}`);
    passed++;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 1: templates — every key present in all three languages
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── Message templates ──');

const templates = {};
for (const code of LANGUAGES) {
  templates[code] = loadTemplates(code);
  check(`prescription.${code}.json declares its own language`, templates[code].language, code);
}

for (const key of TEMPLATE_KEYS) {
  for (const code of LANGUAGES) {
    ok(`${code}: string key "${key}"`, typeof templates[code][key] === 'string' && templates[code][key].length > 0);
  }
}

// The maps must agree key-for-key across languages, or a Tamil send falls back
// to an English word mid-sentence without anything failing.
for (const map of TEMPLATE_MAPS) {
  const reference = Object.keys(templates.en[map]).sort();
  for (const code of LANGUAGES) {
    check(`${map}: ${code} keys match en`, Object.keys(templates[code][map]).sort(), reference);
  }
  for (const code of LANGUAGES) {
    const blank = Object.entries(templates[code][map]).filter(([, v]) => typeof v !== 'string' || !v.trim());
    check(`${map}: ${code} has no blank values`, blank.map(([k]) => k), []);
  }
}

// The maps the composer indexes by enum must cover every enum value.
for (const code of LANGUAGES) {
  check(`${code}: a word for every slot`, SLOTS.filter((s) => !templates[code].slots[s]), []);
  check(`${code}: a word for every palette colour`, PALETTE.map((c) => c.key).filter((k) => !templates[code].colours[k]), []);
  check(`${code}: a word for every food relation`,
    ['BEFORE', 'AFTER', 'WITH', 'ANY'].filter((f) => !templates[code].food[f]), []);
}

// The templates must reference only placeholders the composer supplies.
const ALLOWED_PLACEHOLDERS = new Set(['name', 'index', 'colour', 'pills', 'unit', 'slots', 'food', 'days', 'condition']);
for (const code of LANGUAGES) {
  const unknown = [];
  for (const key of TEMPLATE_KEYS) {
    for (const m of templates[code][key].matchAll(/\{\{\s*([a-z_]+)\s*\}\}/gi)) {
      if (!ALLOWED_PLACEHOLDERS.has(m[1])) unknown.push(`${key}:${m[1]}`);
    }
  }
  check(`${code}: no unknown placeholders in templates`, unknown, []);
}

// Hindi and Tamil must be in their own script, not romanised — the TTS voices
// in Phase 4 read native script and pronounce romanised text as English.
ok('hi templates are Devanagari', /[ऀ-ॿ]/.test(templates.hi.greeting + templates.hi.scheduled));
ok('ta templates are Tamil script', /[஀-௿]/.test(templates.ta.greeting + templates.ta.scheduled));

// The files on disk are exactly the three the loader knows about.
const onDisk = fs.readdirSync(path.join(__dirname, '..', 'messages'))
  .filter((f) => f.startsWith('prescription.') && f.endsWith('.json')).sort();
check('messages/ holds exactly three template files', onDisk,
  ['prescription.en.json', 'prescription.hi.json', 'prescription.ta.json']);

throws('loadTemplates rejects an unsupported code', () => loadTemplates('bn'));

// ─────────────────────────────────────────────────────────────────────────────
// Section 2: render() — no unfilled placeholder ever survives
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── render() ──');

check('fills a placeholder', render('Take {{days}} days.', { days: 5 }), 'Take 5 days.');
check('collapses whitespace', render('a   {{x}}\n b', { x: 'q' }), 'a q b');
throws('throws on a missing value', () => render('Take {{days}} days.', {}));
throws('throws on an empty value', () => render('Take {{days}} days.', { days: '' }));
check('a value containing braces is not re-scanned',
  render('{{name}} ok', { name: '{{days}}' }), '{{days}} ok');

// ─────────────────────────────────────────────────────────────────────────────
// Section 3: palette — chart and audio share one assignment
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── palette ──');

check('palette has eight distinct keys', new Set(PALETTE.map((c) => c.key)).size, PALETTE.length);
check('index 0 → BLUE', colourForIndex(0).key, 'BLUE');
check('index 3 → YELLOW', colourForIndex(3).key, 'YELLOW');
check('wraps past the end', colourForIndex(PALETTE.length).key, PALETTE[0].key);
check('is a pure function of the index', colourForIndex(5), colourForIndex(5));

// ─────────────────────────────────────────────────────────────────────────────
// Section 4: buildScript — a normal record
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── buildScript: a normal record ──');

const record = {
  patient: { name: 'Ramesh', language_pref: 'Hindi' },
  prescriptions: [
    {
      id: 'rx-1', medicine_name: 'Amoxicillin 500mg',
      slots: ['NIGHT', 'MORNING'], food_relation: 'AFTER', pills_per_dose: 1,
      prn: false, prn_condition: null, days: 5, schedule_source: 'PARSED',
    },
    {
      id: 'rx-2', medicine_name: 'Paracetamol 650mg',
      slots: [], food_relation: null, pills_per_dose: 1,
      prn: true, prn_condition: 'fever', days: 3, schedule_source: 'DOCTOR',
    },
  ],
};

const hi = buildScript(record);
check('language resolved to hi', hi.language_used, 'hi');
check('requested language surfaced', hi.requested_language, 'Hindi');
check('supported', hi.supported, true);
check('no blockers', hi.blockers, []);
check('greeting + 2 prescriptions + closing', hi.segments.map((s) => s.key),
  ['greeting', 'prescription', 'prescription', 'closing']);
check('prescription segments are numbered 1..n',
  hi.segments.filter((s) => s.key === 'prescription').map((s) => s.index), [1, 2]);

// Every segment in every language is speakable text with nothing left over.
for (const seg of hi.segments) {
  ok(`segment "${seg.key}${seg.index ?? ''}" has text`, seg.text.length > 0);
  ok(`segment "${seg.key}${seg.index ?? ''}" has a gloss`, seg.gloss.length > 0);
  ok(`segment "${seg.key}${seg.index ?? ''}" has no unfilled placeholder`, !/\{\{/.test(seg.text + seg.gloss));
}

const rx1 = hi.segments.find((s) => s.index === 1);
ok('rx-1 is spoken in Devanagari', /[ऀ-ॿ]/.test(rx1.text));
ok('rx-1 gloss is English', /^[\x20-\x7E]+$/.test(rx1.gloss), rx1.gloss);
ok('rx-1 gloss names the number', rx1.gloss.includes('number 1'), rx1.gloss);
ok('rx-1 gloss names the colour', rx1.gloss.includes('blue'), rx1.gloss);
ok('rx-1 gloss orders slots morning → night',
  rx1.gloss.indexOf('morning') < rx1.gloss.indexOf('night'), rx1.gloss);
ok('rx-1 gloss carries the food relation', rx1.gloss.includes('after food'), rx1.gloss);
ok('rx-1 gloss carries the duration', rx1.gloss.includes('5 days'), rx1.gloss);

const rx2 = hi.segments.find((s) => s.index === 2);
ok('rx-2 gloss is conditional', rx2.gloss.includes('only if you have fever'), rx2.gloss);
ok('rx-2 is the red one', rx2.gloss.includes('red'), rx2.gloss);
ok('rx-2 speaks no day count (PRN)', !/\d+ days/.test(rx2.gloss), rx2.gloss);
ok('rx-2 condition is translated, not passed through',
  !/fever/i.test(rx2.text) && /[ऀ-ॿ]/.test(rx2.text), rx2.text);

// The same record in the other two languages.
for (const code of ['en', 'ta']) {
  const s = buildScript(record, code);
  check(`${code}: language_used`, s.language_used, code);
  check(`${code}: no blockers`, s.blockers, []);
  check(`${code}: same segment shape`, s.segments.map((x) => x.key), hi.segments.map((x) => x.key));
  ok(`${code}: nothing unfilled`, !s.segments.some((x) => /\{\{/.test(x.text + x.gloss)));
  ok(`${code}: glosses match across languages`,
    s.segments.map((x) => x.gloss).join('|') === hi.segments.map((x) => x.gloss).join('|'));
}

check('en: gloss equals text', buildScript(record, 'en').segments.every((s) => s.text === s.gloss), true);

// ─────────────────────────────────────────────────────────────────────────────
// Section 5: fail closed
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── buildScript: fail closed ──');

const blocked = buildScript({
  patient: { name: 'Sita', language_pref: 'en' },
  prescriptions: [
    // NONE-confidence: the parser could not place a slot and nothing else did.
    { id: 'a', medicine_name: 'Vitamin D', slots: [], prn: false, schedule_source: null },
    // PRN with no condition — "take it when needed" for what?
    { id: 'b', medicine_name: 'Ondansetron', slots: [], prn: true, prn_condition: null, schedule_source: 'DOCTOR' },
    // Slots, but nothing ever confirmed them.
    { id: 'c', medicine_name: 'Metformin', slots: ['MORNING'], prn: false, schedule_source: null },
    // A blank row left behind on the form.
    { id: 'd', medicine_name: '', slots: ['MORNING'], prn: false, schedule_source: 'DOCTOR' },
    // The one good row.
    { id: 'e', medicine_name: 'Cetirizine', slots: ['NIGHT'], prn: false, pills_per_dose: 1, days: 5, schedule_source: 'AI' },
  ],
});

check('a NONE-confidence schedule produces no scheduled segment',
  blocked.segments.filter((s) => s.key === 'prescription').map((s) => s.index), [5]);
check('every unspeakable row is blocked',
  blocked.blockers.map((b) => [b.prescription_id, b.reason]),
  [['a', BLOCKER_NO_SCHEDULE], ['b', BLOCKER_PRN_NO_CONDITION], ['c', BLOCKER_NO_SCHEDULE_SOURCE], ['d', BLOCKER_NO_MEDICINE_NAME]]);
check('blocked rows keep their position, so numbering never shifts',
  blocked.blockers.map((b) => b.index), [1, 2, 3, 4]);
check('the good row is still medicine number five', blocked.medicines[4].index, 5);
check('a record with no prescriptions yields greeting + closing only',
  buildScript({ patient: { name: 'X', language_pref: 'en' }, prescriptions: [] }).segments.map((s) => s.key),
  ['greeting', 'closing']);
check('a nameless patient simply loses the greeting',
  buildScript({ patient: { language_pref: 'en' }, prescriptions: [] }).segments.map((s) => s.key), ['closing']);
check('a missing prescriptions array is not a crash',
  buildScript({ patient: { name: 'X', language_pref: 'en' } }).blockers, []);

// ─────────────────────────────────────────────────────────────────────────────
// Section 6: honest degradation for the five unspoken languages
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── buildScript: unsupported language ──');

const bengali = buildScript({
  patient: { name: 'Anil', language_pref: 'Bengali' },
  prescriptions: [{ id: 'z', medicine_name: 'Iron', slots: ['MORNING'], pills_per_dose: 1, days: 30, schedule_source: 'DOCTOR' }],
});
check('Bengali falls back to English', bengali.language_used, 'en');
check('…and says so', bengali.supported, false);
check('…naming what was asked for', bengali.requested_language, 'Bengali');
ok('…and still produces a full script', bengali.segments.length === 3 && bengali.blockers.length === 0);

check('an explicit override beats language_pref', buildScript(record, 'ta').language_used, 'ta');

// ─────────────────────────────────────────────────────────────────────────────
// Section 7: dose counts
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── buildScript: dose counts ──');

const doseGloss = (pills) => buildScript({
  patient: { name: 'X', language_pref: 'en' },
  prescriptions: [{ id: 'p', medicine_name: 'M', slots: ['MORNING'], pills_per_dose: pills, schedule_source: 'DOCTOR' }],
}).segments.find((s) => s.key === 'prescription').gloss;

ok('1 → singular', doseGloss(1).includes('Take 1 tablet in the morning'), doseGloss(1));
ok('2 → plural', doseGloss(2).includes('Take 2 tablets in the morning'), doseGloss(2));
ok('0.5 → "half a tablet"', doseGloss(0.5).includes('half a tablet'), doseGloss(0.5));
ok('0.25 → "a quarter of a tablet"', doseGloss(0.25).includes('a quarter of a tablet'), doseGloss(0.25));
ok('no count → no invented number', doseGloss(null).includes('Take this medicine in the morning'), doseGloss(null));

const threeSlots = buildScript({
  patient: { name: 'X', language_pref: 'en' },
  prescriptions: [{ id: 'p', medicine_name: 'M', slots: ['NIGHT', 'MORNING', 'AFTERNOON'], pills_per_dose: 1, schedule_source: 'DOCTOR' }],
}).segments.find((s) => s.key === 'prescription').gloss;
ok('three slots read as a list',
  threeSlots.includes('in the morning, in the afternoon and at night'), threeSlots);

// An unknown PRN condition passes through rather than being dropped.
const unknownCondition = buildScript({
  patient: { name: 'X', language_pref: 'hi' },
  prescriptions: [{ id: 'p', medicine_name: 'M', slots: [], prn: true, prn_condition: 'giddiness', schedule_source: 'DOCTOR' }],
}).segments.find((s) => s.key === 'prescription');
ok('an untranslated condition is spoken verbatim, not dropped',
  unknownCondition.text.includes('giddiness'), unknownCondition.text);

// ─────────────────────────────────────────────────────────────────────────────
// Section 8: pictogram
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── pictogram ──');

const svg = buildSvg(hi.medicines);
ok('is an SVG document', svg.startsWith('<svg ') && svg.endsWith('</svg>'));
ok('declares the SVG namespace', svg.includes('xmlns="http://www.w3.org/2000/svg"'));
check('one row per prescription', (svg.match(/class="rx-row"/g) || []).length, hi.medicines.length);
check('groups are balanced', (svg.match(/<g[\s>]/g) || []).length, (svg.match(/<\/g>/g) || []).length);
check('rows are numbered as the audio speaks them',
  (svg.match(/data-rx-index="(\d+)"/g) || []).map((m) => m.match(/\d+/)[0]), ['1', '2']);
ok('uses the same colour the audio names', svg.includes(colourForIndex(0).hex) && svg.includes(colourForIndex(1).hex));
ok('no template placeholder leaks into the chart', !svg.includes('{{'));
ok('the chart carries no words — only numerals', !/>[^<]*[A-Za-z]{2,}[^<]*</.test(
  svg.replace(/<(?!text)[^>]*>/g, '')), 'text elements');
ok('fetches nothing at render time', !/https?:\/\//.test(svg.replace('http://www.w3.org/2000/svg', '')));
ok('is deterministic', buildSvg(hi.medicines) === svg);

const prnRow = buildSvg([hi.medicines[1]]);
ok('a PRN row draws no pill in a slot column', prnRow.includes('stroke-dasharray'), 'as-needed band');

const empty = buildSvg([]);
ok('no prescriptions still yields a valid chart', empty.startsWith('<svg ') && empty.endsWith('</svg>'));
check('…with no rows', (empty.match(/class="rx-row"/g) || []).length, 0);

const many = buildSvg(buildScript({
  patient: { name: 'X', language_pref: 'en' },
  prescriptions: Array.from({ length: 6 }, (_, i) => ({
    id: `m${i}`, medicine_name: `M${i}`, slots: [SLOTS[i % SLOTS.length]],
    pills_per_dose: [1, 2, 3, 0.5, 0.25, 4][i], days: i + 1, schedule_source: 'DOCTOR',
  })),
}).medicines);
check('six medicines → six rows', (many.match(/class="rx-row"/g) || []).length, 6);
ok('a taller chart grows its height', Number(many.match(/height="(\d+)"/)[1]) > Number(svg.match(/height="(\d+)"/)[1]));

// ─────────────────────────────────────────────────────────────────────────────
// Section 9: rasterise — allowed to fail soft
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── rasterise ──');

let hasResvg = true;
try { require.resolve('@resvg/resvg-js'); } catch { hasResvg = false; }

rasterise(svg).then((png) => {
  if (hasResvg) {
    ok('renders a PNG when @resvg/resvg-js is installed', Buffer.isBuffer(png) && png.length > 0);
    ok('…with a PNG magic number', png && png.slice(1, 4).toString() === 'PNG');
  } else {
    check('returns null when the optional rasteriser is absent — the send still goes', png, null);
  }
  return rasterise('not an svg at all');
}).then((bad) => {
  check('malformed input fails soft too', bad, null);

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`patient-message: ${passed + failed} tests — ${passed} passed, ${failed} failed`);
  if (!hasResvg) console.log('note: @resvg/resvg-js not installed — PNG output untested (optional by design)');
  if (failed > 0) process.exit(1);
});
