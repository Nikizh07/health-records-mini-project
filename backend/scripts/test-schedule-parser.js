// backend/scripts/test-schedule-parser.js
// ============================================================
// Offline regression suite for services/doseScheduleParser.js (Phase 2).
// No DB, no credentials, no internet: the AI leg runs against a fake
// OpenAI-compatible server on 127.0.0.1, exactly as test-interactions.js does.
//   node scripts/test-schedule-parser.js
// ============================================================
'use strict';

const assert = require('assert');
const http = require('http');

const { parseSchedules, renderSchedulePrompt } = require('../services/doseScheduleParser');

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

const ok = (label, cond, detail = '') => check(label + (cond ? '' : ` ${detail}`), Boolean(cond), true);

// The two rows every section uses: one the regex parses, one it cannot.
const RX = [
  { medicine_name: 'Amoxicillin 500mg', dosage: '1-0-1 after food', duration: '5 days' },
  { medicine_name: 'Vitamin D3', dosage: 'as directed', duration: '1 month' },
];

async function main() {
  // ───────────────────────────────────────────────────────────────────────────
  console.log('\n── Prompt rendering ──');
  // ───────────────────────────────────────────────────────────────────────────
  {
    const { system, user } = renderSchedulePrompt(RX);
    ok('system half is non-empty', system.length > 50);
    ok('user half lists both medicines', user.includes('Amoxicillin 500mg') && user.includes('Vitamin D3'));
    ok('user half carries the free text the doctor typed', user.includes('1-0-1 after food') && user.includes('as directed'));
    ok('no unfilled placeholders survive', !/\{\{\w+\}\}/.test(system + user));
  }

  // ───────────────────────────────────────────────────────────────────────────
  console.log('\n── AI disabled: deterministic only ──');
  // ───────────────────────────────────────────────────────────────────────────
  process.env.AI_ENABLED = 'false';
  {
    const r = await parseSchedules({ prescriptions: RX });
    check('one schedule per prescription, in input order', r.schedules.length, 2);
    check('ai_available false', r.ai_available, false);
    check('ai_provider null', r.ai_provider, null);
    check('regex hit → slots', r.schedules[0].slots, ['MORNING', 'NIGHT']);
    check('regex hit → food_relation', r.schedules[0].food_relation, 'AFTER');
    check('regex hit → schedule_source PARSED', r.schedules[0].schedule_source, 'PARSED');
    check('regex hit → days from duration', r.schedules[0].days, 5);
    check('unparseable → no slots', r.schedules[1].slots, []);
    check('unparseable → confidence NONE', r.schedules[1].confidence, 'NONE');
    check('unparseable → schedule_source null', r.schedules[1].schedule_source, null);
  }
  {
    const r = await parseSchedules({ prescriptions: [] });
    check('empty input → empty schedules', r.schedules, []);
    check('empty input → ai_available false', r.ai_available, false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  console.log('\n── AI leg (fake openai-compatible provider) ──');
  // ───────────────────────────────────────────────────────────────────────────
  let aiReply = () => ({ schedules: [] });
  let aiRequests = [];
  const fakeAi = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      aiRequests.push({ url: req.url, body: JSON.parse(raw) });
      const reply = aiReply();
      if (reply === 'HTTP500') { res.writeHead(500); res.end('boom'); return; }
      const content = typeof reply === 'string' ? reply : JSON.stringify(reply);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ message: { content } }] }));
    });
  });
  await new Promise((r) => fakeAi.listen(0, '127.0.0.1', r));

  Object.assign(process.env, {
    AI_ENABLED: 'true',
    AI_PROVIDER: 'openai-compatible',
    AI_BASE_URL: `http://127.0.0.1:${fakeAi.address().port}/v1/`,
    AI_API_KEY: 'fake-key',
    AI_MODEL: 'fake-model',
    AI_TIMEOUT_MS: '2000',
  });

  // 1. The model fills the gap the regex could not.
  aiRequests = [];
  aiReply = () => ({
    schedules: [
      { index: 0, medicine_name: 'Amoxicillin 500mg', slots: ['MORNING'], food_relation: 'BEFORE', pills_per_dose: 3, prn: false, prn_condition: null, days: 99 },
      { index: 1, medicine_name: 'Vitamin D3', slots: ['MORNING'], food_relation: 'WITH', pills_per_dose: 1, prn: false, prn_condition: null, days: 30 },
    ],
  });
  {
    const r = await parseSchedules({ prescriptions: RX });
    check('ai_available true', r.ai_available, true);
    check('ai_provider named', r.ai_provider, 'openai-compatible');
    ok('exactly one model call', aiRequests.length === 1, `(got ${aiRequests.length})`);

    // The clamp: the regex hit wins on every field it filled.
    check('AI may not override a regex slot hit', r.schedules[0].slots, ['MORNING', 'NIGHT']);
    check('AI may not override a regex food_relation', r.schedules[0].food_relation, 'AFTER');
    check('AI may not override a regex pills_per_dose', r.schedules[0].pills_per_dose, 1);
    check('AI may not override a parsed duration', r.schedules[0].days, 5);
    check('a regex row stays PARSED', r.schedules[0].schedule_source, 'PARSED');

    // The gap: the model is allowed to fill it.
    check('AI fills the empty slots', r.schedules[1].slots, ['MORNING']);
    check('AI fills the empty food_relation', r.schedules[1].food_relation, 'WITH');
    check('AI-filled row is sourced AI', r.schedules[1].schedule_source, 'AI');
    check('AI-filled row is never CERTAIN', r.schedules[1].confidence, 'PARTIAL');
  }

  // 2. A model answer naming a drug that is not the row at that index is dropped.
  aiReply = () => ({
    schedules: [{ index: 1, medicine_name: 'Metformin 500mg', slots: ['NIGHT'], prn: false, days: 30 }],
  });
  {
    const r = await parseSchedules({ prescriptions: RX });
    check('a wrong medicine name is discarded', r.schedules[1].slots, []);
    check('the discarded row stays unsourced', r.schedules[1].schedule_source, null);
  }

  // 3. An index outside the input range is dropped rather than shifting rows.
  aiReply = () => ({ schedules: [{ index: 7, medicine_name: 'Vitamin D3', slots: ['NIGHT'], prn: false }] });
  {
    const r = await parseSchedules({ prescriptions: RX });
    check('an out-of-range index is discarded', r.schedules[1].slots, []);
    check('the row count is unchanged', r.schedules.length, 2);
  }

  // 4. Junk slot values are dropped; a row left with nothing usable stays NONE.
  aiReply = () => ({
    schedules: [{ index: 1, medicine_name: 'Vitamin D3', slots: ['TEATIME', 'NIGHT'], food_relation: 'SOMETIMES', pills_per_dose: -4, prn: false }],
  });
  {
    const r = await parseSchedules({ prescriptions: RX });
    check('unknown slot names are dropped, valid ones kept', r.schedules[1].slots, ['NIGHT']);
    check('an invalid food_relation is dropped', r.schedules[1].food_relation, null);
    check('a negative pills_per_dose is dropped', r.schedules[1].pills_per_dose, null);
  }

  // 5. PRN the regex missed: the model may declare it, condition and all.
  aiReply = () => ({
    schedules: [{ index: 1, medicine_name: 'Vitamin D3', slots: [], prn: true, prn_condition: 'body pain' }],
  });
  {
    const r = await parseSchedules({ prescriptions: RX });
    check('AI may fill prn on a gap row', r.schedules[1].prn, true);
    check('AI may fill prn_condition', r.schedules[1].prn_condition, 'body pain');
    check('AI-declared prn is sourced AI', r.schedules[1].schedule_source, 'AI');
  }

  // 6. A regex PRN hit is not overridden into a schedule.
  aiReply = () => ({
    schedules: [{ index: 0, medicine_name: 'Paracetamol 650mg', slots: ['MORNING', 'NIGHT'], prn: false }],
  });
  {
    const prn = [{ medicine_name: 'Paracetamol 650mg', dosage: 'SOS if fever', duration: '3 days' }];
    const r = await parseSchedules({ prescriptions: prn });
    check('a regex PRN hit keeps prn true', r.schedules[0].prn, true);
    check('a regex PRN hit gains no slots', r.schedules[0].slots, []);
    check('a regex PRN hit stays PARSED', r.schedules[0].schedule_source, 'PARSED');
  }

  // 7. A row the caller sent with no medicine name still occupies its position,
  //    so the client can map answers back by index (Phase 6 autofills by row).
  aiReply = () => ({ schedules: [{ index: 0, medicine_name: 'Vitamin D3', slots: ['NIGHT'], prn: false }] });
  {
    const withBlank = [
      { medicine_name: '   ', dosage: '1-0-1', duration: '5 days' },
      { medicine_name: 'Vitamin D3', dosage: 'as directed', duration: '1 month' },
    ];
    const r = await parseSchedules({ prescriptions: withBlank });
    check('one schedule per INPUT row, blanks included', r.schedules.length, 2);
    check('the nameless row is unplaced', r.schedules[0].schedule_source, null);
    check('the nameless row keeps its (empty) name', r.schedules[0].medicine_name, '');
    check('the named row is still at its own index', r.schedules[1].medicine_name, 'Vitamin D3');
    check('the model answer lands on the named row, not the blank one', r.schedules[1].slots, ['NIGHT']);
    check('the blank row gained nothing', r.schedules[0].slots, []);
  }

  // 8. Every AI failure mode falls back to the deterministic parse.
  for (const [label, reply] of [
    ['an HTTP error', 'HTTP500'],
    ['unparseable output', 'I am afraid I cannot do that.'],
    ['valid JSON with no schedules array', { result: 'ok' }],
  ]) {
    aiReply = () => reply;
    const r = await parseSchedules({ prescriptions: RX });
    check(`${label} → ai_available false`, r.ai_available, false);
    check(`${label} → deterministic result stands`, r.schedules[0].slots, ['MORNING', 'NIGHT']);
    check(`${label} → gap row left empty`, r.schedules[1].slots, []);
  }

  await new Promise((r) => fakeAi.close(r));

  console.log(`\n${'─'.repeat(50)}`);
  console.log(`schedule-parser: ${passed + failed} tests — ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
