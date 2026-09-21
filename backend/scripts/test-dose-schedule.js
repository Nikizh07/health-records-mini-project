// backend/scripts/test-dose-schedule.js
// Offline regression suite for utils/doseSchedule.js and utils/language.js
// No DB, no network, no credentials.
//   node scripts/test-dose-schedule.js
'use strict';

const assert = require('assert');
const { parseDoseText, SLOTS } = require('../utils/doseSchedule');
const { resolveLanguage } = require('../utils/language');

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

// ─────────────────────────────────────────────────────────────────────────────
// Section 1: SLOTS constant
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── SLOTS constant ──');
check('SLOTS has four values', SLOTS, ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT']);

// ─────────────────────────────────────────────────────────────────────────────
// Section 2: Numeric shorthand (1-0-1 style)
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── Numeric shorthand ──');

{
  const r = parseDoseText('1-0-1', '5 days');
  check('1-0-1 → MORNING+NIGHT CERTAIN', { slots: r.slots, confidence: r.confidence }, { slots: ['MORNING', 'NIGHT'], confidence: 'CERTAIN' });
  check('1-0-1 → days=5', r.days, 5);
  check('1-0-1 → pills=1', r.pills_per_dose, 1);
}

{
  const r = parseDoseText('1-1-1', '7 days');
  check('1-1-1 → M+A+N CERTAIN', { slots: r.slots, confidence: r.confidence }, { slots: ['MORNING', 'AFTERNOON', 'NIGHT'], confidence: 'CERTAIN' });
}

{
  const r = parseDoseText('0-0-1', '3/7');
  check('0-0-1 → NIGHT only', r.slots, ['NIGHT']);
  check('0-0-1 → days=3 (UK 3/7)', r.days, 3);
}

{
  const r = parseDoseText('1-0-1-1', '10 days');
  check('1-0-1-1 → M+E+N (4-part)', r.slots, ['MORNING', 'EVENING', 'NIGHT']);
}

{
  const r = parseDoseText('0-0-0-1', '5 days');
  check('0-0-0-1 → NIGHT only (4-part)', r.slots, ['NIGHT']);
}

{
  const r = parseDoseText('1-1-1-1 after food', '5 days');
  check('1-1-1-1 after food → AFTER', r.food_relation, 'AFTER');
  check('1-1-1-1 → all four slots', r.slots, ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT']);
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 3: Latin abbreviations
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── Latin abbreviations ──');

check('OD → MORNING', parseDoseText('OD', '5 days').slots, ['MORNING']);
check('BD → M+N', parseDoseText('BD after food', '5 days').slots, ['MORNING', 'NIGHT']);
check('TDS → M+A+N', parseDoseText('TDS', '5 days').slots, ['MORNING', 'AFTERNOON', 'NIGHT']);
check('QDS → all four', parseDoseText('QDS', '5 days').slots, ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT']);
check('QID → all four', parseDoseText('QID', '5 days').slots, ['MORNING', 'AFTERNOON', 'EVENING', 'NIGHT']);
check('once daily → MORNING', parseDoseText('once daily', '5 days').slots, ['MORNING']);
check('twice daily → M+N', parseDoseText('twice daily', '5 days').slots, ['MORNING', 'NIGHT']);
check('thrice daily → M+A+N', parseDoseText('thrice daily', '5 days').slots, ['MORNING', 'AFTERNOON', 'NIGHT']);

{
  const r = parseDoseText('BD before food', '14 days');
  check('BD before food → BEFORE', r.food_relation, 'BEFORE');
  check('BD before food → days=14', r.days, 14);
  check('BD before food → CERTAIN', r.confidence, 'CERTAIN');
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 4: Natural language
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── Natural language ──');

check('morning and night → M+N', parseDoseText('morning and night', '5 days').slots, ['MORNING', 'NIGHT']);
check('morning only → MORNING', parseDoseText('take every morning', '10 days').slots, ['MORNING']);
check('at bedtime → NIGHT', parseDoseText('1 tablet at bedtime', '5 days').slots, ['NIGHT']);
check('nocte → NIGHT', parseDoseText('1 tab nocte', '7 days').slots, ['NIGHT']);

{
  const r = parseDoseText('1 tablet morning and night after meals', '5 days');
  check('1 tab morning+night after meals → slots', r.slots, ['MORNING', 'NIGHT']);
  check('1 tab morning+night after meals → food=AFTER', r.food_relation, 'AFTER');
  check('1 tab morning+night after meals → pills=1', r.pills_per_dose, 1);
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 5: PRN / SOS
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── PRN / SOS ──');

{
  const r = parseDoseText('SOS', '');
  check('SOS → prn:true', r.prn, true);
  check('SOS → slots empty', r.slots, []);
  check('SOS → PARTIAL (no condition)', r.confidence, 'PARTIAL');
}

{
  const r = parseDoseText('PRN if fever', '');
  check('PRN if fever → prn:true', r.prn, true);
  check('PRN if fever → condition="fever"', r.prn_condition, 'fever');
  check('PRN if fever → CERTAIN', r.confidence, 'CERTAIN');
}

{
  const r = parseDoseText('1 tablet as needed for pain', '');
  check('as needed for pain → prn:true', r.prn, true);
  check('as needed for pain → condition="pain"', r.prn_condition, 'pain');
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 6: Food relation
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── Food relation ──');

check('before food → BEFORE', parseDoseText('1-0-1 before food', '5 days').food_relation, 'BEFORE');
check('after meals → AFTER', parseDoseText('BD after meals', '5 days').food_relation, 'AFTER');
check('with food → WITH', parseDoseText('OD with food', '5 days').food_relation, 'WITH');
check('empty stomach → BEFORE', parseDoseText('OD empty stomach', '5 days').food_relation, 'BEFORE');
check('PC → AFTER', parseDoseText('1-1-1 pc', '5 days').food_relation, 'AFTER');

// ─────────────────────────────────────────────────────────────────────────────
// Section 7: Must return NONE (never guess)
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── Must return NONE (no guessing) ──');

const noneInputs = [
  ['apply locally', '5 days'],
  ['topical', '7 days'],
  ['inhale as directed', '1 month'],
  ['use as directed by doctor', '2 weeks'],
  ['one drop in each eye', '5 days'],
  ['gargle with warm water', '3 days'],
];

for (const [dosage, duration] of noneInputs) {
  const r = parseDoseText(dosage, duration);
  check(`NONE: "${dosage}"`, r.confidence, 'NONE');
  check(`NONE slots empty: "${dosage}"`, r.slots, []);
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 8: Duration parsing (via parseDurationDays)
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── Duration parsing ──');

check('5 days', parseDoseText('OD', '5 days').days, 5);
check('2 weeks', parseDoseText('OD', '2 weeks').days, 14);
check('1 month', parseDoseText('OD', '1 month').days, 30);
check('10d', parseDoseText('OD', '10d').days, 10);
check('3/7 (UK)', parseDoseText('OD', '3/7').days, 3);
check('3/52 (UK weeks)', parseDoseText('OD', '3/52').days, 21);
check('unparseable duration → null', parseDoseText('OD', 'as directed').days, null);

// ─────────────────────────────────────────────────────────────────────────────
// Section 9: resolveLanguage
// ─────────────────────────────────────────────────────────────────────────────
console.log('\n── resolveLanguage ──');

check('Hindi code', resolveLanguage('hi'), { code: 'hi', requested: 'Hindi', supported: true });
check('Tamil code', resolveLanguage('ta'), { code: 'ta', requested: 'Tamil', supported: true });
check('English code', resolveLanguage('en'), { code: 'en', requested: 'English', supported: true });
check('Hindi name', resolveLanguage('Hindi').code, 'hi');
check('Tamil name', resolveLanguage('Tamil').code, 'ta');
check('English name', resolveLanguage('English').code, 'en');

// Registration default — Bengali is the most common unsupported case
const bengali = resolveLanguage('Bengali');
check('Bengali → falls back to en', bengali.code, 'en');
check('Bengali → supported:false', bengali.supported, false);
check('Bengali → requested preserved', bengali.requested, 'Bengali');

check('Malayalam → unsupported', resolveLanguage('Malayalam').supported, false);
check('Odia → unsupported', resolveLanguage('Odia').supported, false);
check('Telugu → unsupported', resolveLanguage('Telugu').supported, false);
check('Assamese → unsupported', resolveLanguage('Assamese').supported, false);

check('null → English fallback', resolveLanguage(null), { code: 'en', requested: 'Unknown', supported: false });
check('empty string → English fallback', resolveLanguage('').code, 'en');

// ─────────────────────────────────────────────────────────────────────────────
// Summary
// ─────────────────────────────────────────────────────────────────────────────
console.log(`\n${'─'.repeat(50)}`);
console.log(`dose-schedule: ${passed + failed} tests — ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
