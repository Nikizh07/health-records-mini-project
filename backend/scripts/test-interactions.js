// backend/scripts/test-interactions.js
// ============================================================
// Drug interaction feature — end-to-end regression suite
// ============================================================
// Covers Phase 1 (the cross-clinic checker), Phase 2 (the audit wiring
// on save) and Phase 4 (the AI leg, against a fake provider), driving the real Express app over HTTP so the genuine
// authenticate → requireRole → controller → errorHandler stack runs.
//
// Firebase is stubbed in require.cache before the app loads, so no
// service account and no device are needed. Nothing in the app is
// modified; the stub lives only in this process.
//
// Usage:
//   DATABASE_URL=postgresql://... node scripts/test-interactions.js
//
// It creates its own clinics, doctors and patients (all prefixed with a
// timestamped tag) and deletes them again at the end. It never touches
// pre-existing rows, but point it at a development database regardless.
// ============================================================

'use strict';

const http = require('http');
const path = require('path');

const BACKEND = path.resolve(__dirname, '..');
const PORT = process.env.TEST_PORT || 3997;

process.env.PORT = String(PORT);
process.env.NODE_ENV = 'development';
// The AI leg stays off whatever backend/.env says; Phase 4 below switches it
// on against a fake provider in this process.
process.env.AI_ENABLED = 'false';

// ── Stub Firebase BEFORE anything requires it ────────────────
// A test token is "test.<base64 of the decoded-token JSON>".
const firebasePath = require.resolve(path.join(BACKEND, 'config/firebase'));
require.cache[firebasePath] = {
  id: firebasePath,
  filename: firebasePath,
  loaded: true,
  children: [],
  paths: [],
  exports: {
    auth: {
      verifyIdToken: async (token) => {
        if (typeof token !== 'string' || !token.startsWith('test.')) {
          const err = new Error('Invalid test token');
          err.code = 'auth/argument-error';
          throw err;
        }
        return JSON.parse(Buffer.from(token.slice(5), 'base64').toString('utf8'));
      },
    },
  },
};

const prisma = require(path.join(BACKEND, 'config/prisma'));
const { checkInteractions } = require(path.join(BACKEND, 'services/interactionChecker'));

// Silence the request logger so the results stay readable.
const quiet = !process.env.VERBOSE;
if (quiet) {
  const write = process.stdout.write.bind(process.stdout);
  process.stdout.write = (chunk, ...rest) =>
    /^\x1b\[0m(GET|POST|PUT|DELETE|PATCH) /.test(String(chunk)) ? true : write(chunk, ...rest);
}

require(path.join(BACKEND, 'server.js'));

const BASE = `http://127.0.0.1:${PORT}/api`;
const TAG = 'ixtest-' + Date.now();

let passed = 0;
let failed = 0;

function ok(name, condition, detail = '') {
  if (condition) {
    passed += 1;
    console.log(`  \x1b[32m✔\x1b[0m ${name}`);
  } else {
    failed += 1;
    console.log(`  \x1b[31m✘ ${name}\x1b[0m ${detail}`);
  }
}

function section(title) {
  console.log(`\n\x1b[1m── ${title} ──\x1b[0m`);
}

function heading(title) {
  console.log(`\n\x1b[1m═══ ${title} ═══\x1b[0m`);
}

function tokenFor(uid) {
  return 'test.' + Buffer.from(JSON.stringify({ uid, phone_number: null })).toString('base64');
}

async function api(method, endpoint, { token, body } = {}) {
  const res = await fetch(BASE + endpoint, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  let json = null;
  try {
    json = await res.json();
  } catch (_) {
    /* non-JSON body */
  }
  return { status: res.status, body: json };
}

const SEVERITY_RANK = { CRITICAL: 0, MAJOR: 1, MODERATE: 2, MINOR: 3 };
const sortedWorstFirst = (severities) =>
  severities.every((s, i) => i === 0 || SEVERITY_RANK[severities[i - 1]] <= SEVERITY_RANK[s]);

const rx = (medicine_name, duration = '5 days') => ({ medicine_name, dosage: '1 unit', duration });
const daysAgo = (n) => new Date(Date.now() - n * 86400000);

async function main() {
  await new Promise((r) => setTimeout(r, 1200)); // let the server bind

  const patientIds = [];

  // ── fixtures ───────────────────────────────────────────────
  const clinicA = await prisma.clinic.create({
    data: { name: `${TAG} Clinic A`, location: 'A', contact_number: `${TAG}-ca` },
  });
  const clinicB = await prisma.clinic.create({
    data: { name: `${TAG} Clinic B`, location: 'B', contact_number: `${TAG}-cb` },
  });
  const doctorUser = await prisma.user.create({
    data: { firebase_uid: `${TAG}-doc`, phone: `${TAG}-du`, role: 'DOCTOR' },
  });
  const patientUser = await prisma.user.create({
    data: { firebase_uid: `${TAG}-pat`, phone: `${TAG}-pu`, role: 'PATIENT' },
  });
  const doctorA = await prisma.doctor.create({
    data: { clinic_id: clinicA.id, name: 'Dr A', specialization: 'GP', phone: `${TAG}-da` },
  });
  const doctorB = await prisma.doctor.create({
    data: { clinic_id: clinicB.id, user_id: doctorUser.id, name: 'Dr B', specialization: 'GP', phone: `${TAG}-db` },
  });

  let seq = 0;
  async function newPatient(userId = null) {
    seq += 1;
    const p = await prisma.patient.create({
      data: {
        ...(userId ? { user_id: userId } : {}),
        health_id: `MWH-${String(Date.now()).slice(-5)}${seq}`,
        name: `Patient ${seq}`,
        phone: `${TAG}-p${seq}`,
        dob: new Date('1990-01-01'),
        gender: 'M',
        language_pref: 'en',
      },
    });
    patientIds.push(p.id);
    return p;
  }

  const prescribe = (patientId, doctorId, meds, ago) =>
    prisma.medicalRecord.create({
      data: {
        patient_id: patientId,
        doctor_id: doctorId,
        visit_date: daysAgo(ago),
        diagnosis: 'Seeded history',
        notes: '',
        prescriptions: { create: meds },
      },
    });

  const DOC = tokenFor(`${TAG}-doc`);
  const PAT = tokenFor(`${TAG}-pat`);
  const IBU = [rx('Ibuprofen 400mg')];

  const patient = await newPatient(patientUser.id);
  // Clinic A: warfarin still running; an amoxicillin course long finished.
  await prescribe(patient.id, doctorA.id, [{ medicine_name: 'Warfarin 5mg', dosage: '5mg od', duration: '90 days' }], 30);
  await prescribe(patient.id, doctorA.id, [{ medicine_name: 'Amoxicillin 500mg', dosage: '500mg tds', duration: '5 days' }], 300);

  // ══════════════════════════════════════════════════════════
  heading('PHASE 1 — the cross-clinic checker');

  section('Auth and role gates');
  ok('no token → 401', (await api('POST', '/records/interaction-check', { body: {} })).status === 401);
  ok('bad token → 401', (await api('POST', '/records/interaction-check', { token: 'nope', body: {} })).status === 401);
  const asPatient = await api('POST', '/records/interaction-check', {
    token: PAT, body: { patient_id: patient.id, prescriptions: IBU },
  });
  ok('PATIENT role → 403', asPatient.status === 403, `got ${asPatient.status}`);

  section('Input validation');
  ok('missing patient_id → 400', (await api('POST', '/records/interaction-check', { token: DOC, body: { prescriptions: [] } })).status === 400);
  ok('malformed patient_id → 400', (await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: 'abc', prescriptions: [] } })).status === 400);
  ok('unknown patient → 404', (await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: '11111111-1111-4111-8111-111111111111', prescriptions: [] } })).status === 404);
  ok('prescriptions not an array → 400', (await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: 'ibuprofen' } })).status === 400);
  const emptyList = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: [] } });
  ok('empty list → 200 with no conflicts', emptyList.status === 200 && emptyList.body.data.conflicts.length === 0);

  section('A conflict started at another clinic');
  const check = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: IBU } });
  const conflicts = check.body?.data?.conflicts || [];
  const first = conflicts[0] || {};
  ok('200 OK', check.status === 200, `got ${check.status}`);
  ok('exactly one conflict', conflicts.length === 1, `got ${conflicts.length}`);
  ok('severity CRITICAL', first.severity === 'CRITICAL', first.severity);
  ok('scope EXISTING', first.scope === 'EXISTING', first.scope);
  ok('names the other clinic', first.clinic_name === `${TAG} Clinic A`, first.clinic_name);
  ok('reports the prescribing date', !!first.prescribed_on);
  ok('explains the mechanism', /bleeding/i.test(first.explanation || ''), first.explanation);
  ok('suggests an alternative', !!first.suggested_alternative, first.suggested_alternative);
  ok('source TABLE', first.source === 'TABLE', first.source);
  ok('ai_available false with AI switched off', check.body.data.ai_available === false);
  ok('returns a check_id', typeof check.body.data.check_id === 'string');

  section('Name normalisation');
  for (const variant of ['ibuprofen', 'IBUPROFEN 600mg', 'Ibuprofen 200 mg tablet', '  ibuprofen  ']) {
    const r = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: [rx(variant)] } });
    ok(`"${variant}" matches`, (r.body?.data?.conflicts || []).length === 1);
  }
  const brand = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: [rx('Brufen 400mg')] } });
  ok('brand name not matched by the table alone', (brand.body?.data?.conflicts || []).length === 0);

  section('Which past prescriptions still count');
  const expired = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: [rx('Methotrexate 2.5mg', '4 weeks')] } });
  ok('a finished course is ignored', !(expired.body?.data?.conflicts || []).some((c) => /amoxicillin/i.test(c.existing_drug || '')));
  const safe = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: [rx('Cetirizine 10mg')] } });
  ok('a safe drug returns nothing', (safe.body?.data?.conflicts || []).length === 0);

  const assumedPatient = await newPatient();
  await prescribe(assumedPatient.id, doctorA.id, [{ medicine_name: 'Warfarin 5mg', dosage: '5mg', duration: 'as directed' }], 20);
  const assumed = await checkInteractions({ patientId: assumedPatient.id, newPrescriptions: IBU });
  ok('unparseable duration still warns', assumed.conflicts.length === 1, JSON.stringify(assumed.conflicts));
  ok('  and is flagged ASSUMED', assumed.conflicts[0]?.confidence === 'ASSUMED', assumed.conflicts[0]?.confidence);

  const stalePatient = await newPatient();
  await prescribe(stalePatient.id, doctorA.id, [{ medicine_name: 'Warfarin 5mg', dosage: '5mg', duration: 'as directed' }], 200);
  const stale = await checkInteractions({ patientId: stalePatient.id, newPrescriptions: IBU });
  ok('unparseable and older than 90 days is dropped', stale.conflicts.length === 0, JSON.stringify(stale.conflicts));

  const shorthandPatient = await newPatient();
  await prescribe(shorthandPatient.id, doctorA.id, [{ medicine_name: 'Warfarin 5mg', dosage: '5mg', duration: '3/52' }], 7);
  const shorthand = await checkInteractions({ patientId: shorthandPatient.id, newPrescriptions: IBU });
  ok('UK shorthand "3/52" parsed as 3 weeks', shorthand.conflicts.length === 1 && shorthand.conflicts[0].confidence === 'CERTAIN', JSON.stringify(shorthand.conflicts));

  section('Severity ordering');
  const mixedPatient = await newPatient();
  await prescribe(mixedPatient.id, doctorA.id, [
    { medicine_name: 'Warfarin 5mg', dosage: '5mg', duration: '90 days' },
    { medicine_name: 'Lithium 300mg', dosage: '300mg', duration: '90 days' },
    { medicine_name: 'Lisinopril 10mg', dosage: '10mg', duration: '90 days' },
  ], 10);
  const mixed = await checkInteractions({ patientId: mixedPatient.id, newPrescriptions: IBU });
  const mixedSeverities = mixed.conflicts.map((c) => c.severity);
  ok('three distinct severities returned', new Set(mixedSeverities).size === 3, mixedSeverities.join(','));
  ok(`sorted worst first [${mixedSeverities.join(', ')}]`, sortedWorstFirst(mixedSeverities));

  section('Every check is audited');
  const auditRows = await prisma.interactionCheck.findMany({ where: { patient_id: patient.id } });
  ok(`audit rows written (${auditRows.length})`, auditRows.length > 0);
  ok('the requesting doctor is recorded', auditRows[0].doctor_id === doctorB.id);
  ok('rows start unlinked and not overridden', auditRows.every((a) => a.record_id === null && a.overridden === false));

  // ══════════════════════════════════════════════════════════
  heading('SAME-VISIT conflicts');

  section('Two conflicting drugs in one prescription');
  const svPatient = await newPatient(); // no history whatsoever
  const bothDrugs = [rx('Warfarin 5mg', '30 days'), rx('Ibuprofen 400mg')];
  const sv = await checkInteractions({ patientId: svPatient.id, newPrescriptions: bothDrugs });
  const svFirst = sv.conflicts[0] || {};
  ok('fires even with no prescription history', sv.conflicts.length === 1, JSON.stringify(sv.conflicts));
  ok('severity CRITICAL', svFirst.severity === 'CRITICAL', svFirst.severity);
  ok('scope SAME_VISIT', svFirst.scope === 'SAME_VISIT', svFirst.scope);
  ok('no clinic to attribute it to', svFirst.clinic_name === null);
  ok('no prescribing date', svFirst.prescribed_on === null);
  ok('confidence CERTAIN', svFirst.confidence === 'CERTAIN', svFirst.confidence);

  const reversed = await checkInteractions({ patientId: svPatient.id, newPrescriptions: [...bothDrugs].reverse() });
  ok('reported once regardless of drug order', reversed.conflicts.length === 1, JSON.stringify(reversed.conflicts));

  const triple = await checkInteractions({
    patientId: svPatient.id,
    newPrescriptions: [rx('Warfarin 5mg', '30 days'), rx('Ibuprofen 400mg'), rx('Aspirin 75mg')],
  });
  ok('all three pairs of three drugs found', triple.conflicts.length === 3, String(triple.conflicts.length));
  ok('all marked SAME_VISIT', triple.conflicts.every((c) => c.scope === 'SAME_VISIT'));
  ok('still sorted worst first', sortedWorstFirst(triple.conflicts.map((c) => c.severity)));

  const dupe = await checkInteractions({ patientId: svPatient.id, newPrescriptions: [rx('Ibuprofen 400mg'), rx('IBUPROFEN 600 mg tablet')] });
  ok('a drug does not conflict with itself', dupe.conflicts.length === 0, JSON.stringify(dupe.conflicts));

  const safePair = await checkInteractions({ patientId: svPatient.id, newPrescriptions: [rx('Cetirizine 10mg'), rx('Paracetamol 500mg')] });
  ok('a safe pair stays silent', safePair.conflicts.length === 0, JSON.stringify(safePair.conflicts));

  section('Overlap between the two legs');
  const overlapPatient = await newPatient();
  await prescribe(overlapPatient.id, doctorA.id, [{ medicine_name: 'Warfarin 5mg', dosage: '5mg', duration: '90 days' }], 10);
  const overlap = await checkInteractions({ patientId: overlapPatient.id, newPrescriptions: bothDrugs });
  ok('the pair is reported once, not twice', overlap.conflicts.length === 1, JSON.stringify(overlap.conflicts.map((c) => c.scope)));
  ok('the richer EXISTING conflict is the one kept', overlap.conflicts[0]?.scope === 'EXISTING', overlap.conflicts[0]?.scope);
  ok('so the clinic is still named', !!overlap.conflicts[0]?.clinic_name);

  // ══════════════════════════════════════════════════════════
  heading('PHASE 2 — audit wiring on save');

  section('A conflicted save needs a reason');
  const checkId = check.body.data.check_id;
  const noReason = await api('POST', '/records', {
    token: DOC, body: { patient_id: patient.id, diagnosis: 'Back pain', prescriptions: IBU, check_id: checkId },
  });
  ok('refused with 400', noReason.status === 400, `got ${noReason.status}`);
  ok('the message names override_reason', /override_reason/.test(noReason.body?.message || ''));
  ok('the message counts the interactions', /1 drug interaction/.test(noReason.body?.message || ''));
  ok('nothing was written', (await prisma.medicalRecord.count({ where: { patient_id: patient.id, diagnosis: 'Back pain' } })) === 0);
  ok('an empty reason is refused too', (await api('POST', '/records', { token: DOC, body: { patient_id: patient.id, diagnosis: 'Back pain', prescriptions: IBU, check_id: checkId, override_reason: '' } })).status === 400);
  ok('a whitespace-only reason is refused too', (await api('POST', '/records', { token: DOC, body: { patient_id: patient.id, diagnosis: 'Back pain', prescriptions: IBU, check_id: checkId, override_reason: '   ' } })).status === 400);

  section('With a reason it saves, and is audited');
  const saved = await api('POST', '/records', {
    token: DOC,
    body: { patient_id: patient.id, diagnosis: 'Back pain', prescriptions: IBU, check_id: checkId, override_reason: '  INR monitored weekly; patient counselled.  ' },
  });
  ok('created with 201', saved.status === 201, `got ${saved.status} ${saved.body?.message || ''}`);
  ok('the prescription persisted', (saved.body?.data?.prescriptions || []).length === 1);
  const savedRow = await prisma.interactionCheck.findUnique({ where: { id: checkId } });
  ok('the check is linked to the record', savedRow.record_id === saved.body.data.id);
  ok('overridden = true', savedRow.overridden === true);
  ok('the reason is stored, trimmed', savedRow.override_reason === 'INR monitored weekly; patient counselled.', JSON.stringify(savedRow.override_reason));
  ok('the server kept its own copy of the conflicts', Array.isArray(savedRow.conflicts) && savedRow.conflicts.length === 1);

  section('Checks cannot be reused or borrowed');
  const reuse = await api('POST', '/records', { token: DOC, body: { patient_id: patient.id, diagnosis: 'Another visit', prescriptions: IBU, check_id: checkId, override_reason: 'again' } });
  ok('a consumed check is refused', reuse.status === 400 && /already been linked/.test(reuse.body?.message || ''), reuse.body?.message);

  const otherPatient = await newPatient();
  const foreignCheck = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: otherPatient.id, prescriptions: IBU } });
  const borrowed = await api('POST', '/records', {
    token: DOC, body: { patient_id: patient.id, diagnosis: 'Cross patient', prescriptions: IBU, check_id: foreignCheck.body.data.check_id, override_reason: 'x' },
  });
  ok("another patient's check is refused", borrowed.status === 400 && /does not belong to this patient/.test(borrowed.body?.message || ''), borrowed.body?.message);

  const badUuid = await api('POST', '/records', { token: DOC, body: { patient_id: patient.id, diagnosis: 'Checkup', check_id: 'not-a-uuid' } });
  ok('a malformed check_id → 400', badUuid.status === 400 && /"check_id" must be a valid UUID/.test(badUuid.body?.message || ''), badUuid.body?.message);
  const unknown = await api('POST', '/records', { token: DOC, body: { patient_id: patient.id, diagnosis: 'Checkup', check_id: '11111111-1111-4111-8111-111111111111' } });
  ok('an unknown check_id → 404', unknown.status === 404 && /was not found/.test(unknown.body?.message || ''), unknown.body?.message);

  section('A clean check is not an override');
  const cleanCheck = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patient.id, prescriptions: [rx('Cetirizine 10mg')] } });
  const cleanSave = await api('POST', '/records', {
    token: DOC, body: { patient_id: patient.id, diagnosis: 'Allergic rhinitis', prescriptions: [rx('Cetirizine 10mg')], check_id: cleanCheck.body.data.check_id },
  });
  ok('saves with no reason at all', cleanSave.status === 201, `got ${cleanSave.status}`);
  const cleanRow = await prisma.interactionCheck.findUnique({ where: { id: cleanCheck.body.data.check_id } });
  ok('still linked to the record', cleanRow.record_id === cleanSave.body.data.id);
  ok('overridden = false', cleanRow.overridden === false, String(cleanRow.overridden));
  ok('no reason stored', cleanRow.override_reason === null);

  section('A same-visit conflict is enforced the same way');
  const svEnforcePatient = await newPatient();
  const svCheck = await api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: svEnforcePatient.id, prescriptions: bothDrugs } });
  ok('the check reports it', (svCheck.body?.data?.conflicts || []).length === 1 && svCheck.body.data.conflicts[0].scope === 'SAME_VISIT');
  const svRefused = await api('POST', '/records', { token: DOC, body: { patient_id: svEnforcePatient.id, diagnosis: 'Pain with clot risk', prescriptions: bothDrugs, check_id: svCheck.body.data.check_id } });
  ok('the save is refused without a reason', svRefused.status === 400, `got ${svRefused.status}`);
  const svSaved = await api('POST', '/records', { token: DOC, body: { patient_id: svEnforcePatient.id, diagnosis: 'Pain with clot risk', prescriptions: bothDrugs, check_id: svCheck.body.data.check_id, override_reason: 'Deliberate; bleeding risk discussed.' } });
  ok('and accepted with one', svSaved.status === 201, `got ${svSaved.status}`);
  const svRow = await prisma.interactionCheck.findUnique({ where: { id: svCheck.body.data.check_id } });
  ok('audited as an override', svRow.record_id === svSaved.body.data.id && svRow.overridden === true);
  ok('the stored conflict keeps its scope', svRow.conflicts[0]?.scope === 'SAME_VISIT');

  section('Nothing changes when no check is sent');
  const legacy = await api('POST', '/records', { token: DOC, body: { patient_id: patient.id, diagnosis: 'Legacy save', prescriptions: IBU } });
  ok('saves with 201 as before', legacy.status === 201, `got ${legacy.status}`);
  ok('prescriptions still persisted', (legacy.body?.data?.prescriptions || []).length === 1);
  ok('no audit row is invented', (await prisma.interactionCheck.count({ where: { record_id: legacy.body.data.id } })) === 0);

  const history = await api('GET', `/records/patient/${patient.id}`, { token: DOC });
  const historyRecords = history.body?.data?.records || history.body?.data || [];
  ok('history still reads back across clinics', history.status === 200 && new Set(historyRecords.map((r) => r.doctor?.clinic?.name).filter(Boolean)).size >= 2);

  // ══════════════════════════════════════════════════════════
  heading('PHASE 4 — the AI leg (fake OpenAI-compatible provider)');

  // A local /chat/completions endpoint. `aiReply` decides each response.
  let aiReply = () => ({ conflicts: [] });
  let aiRequests = [];
  const fakeAi = http.createServer((req, res) => {
    let raw = '';
    req.on('data', (chunk) => { raw += chunk; });
    req.on('end', async () => {
      aiRequests.push({ url: req.url, auth: req.headers.authorization, body: JSON.parse(raw) });
      const reply = await aiReply();
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
    AI_JSON_MODE: 'true',
    AI_TIMEOUT_MS: '1500',
  });

  const checkRx = (prescriptions, patientId = patient.id) =>
    api('POST', '/records/interaction-check', { token: DOC, body: { patient_id: patientId, prescriptions } });
  const aiConflict = (new_drug, existing_drug, severity, explanation = 'Model explanation.', suggested_alternative = null) =>
    ({ new_drug, existing_drug, severity, explanation, suggested_alternative });

  section('A brand name the table cannot match');
  aiReply = () => ({ conflicts: [aiConflict('Brufen 400mg', 'Warfarin 5mg', 'CRITICAL', 'Brufen is ibuprofen; bleeding risk.', 'Paracetamol')] });
  aiRequests = [];
  const brufen = await checkRx([rx('Brufen 400mg')]);
  const brufenConflict = brufen.body?.data?.conflicts?.[0] || {};
  ok('200 OK', brufen.status === 200, `got ${brufen.status}`);
  ok('ai_available true', brufen.body?.data?.ai_available === true);
  ok('Brufen + warfarin reported CRITICAL', brufenConflict.severity === 'CRITICAL' && brufenConflict.new_drug === 'Brufen 400mg', JSON.stringify(brufenConflict));
  ok('clinic and date come from the record, not the model', brufenConflict.clinic_name === `${TAG} Clinic A` && !!brufenConflict.prescribed_on);
  ok('source AI, scope EXISTING', brufenConflict.source === 'AI' && brufenConflict.scope === 'EXISTING');
  const brufenRow = await prisma.interactionCheck.findUnique({ where: { id: brufen.body.data.check_id } });
  ok('ai_provider recorded on the check row', brufenRow.ai_available === true && brufenRow.ai_provider === 'openai-compatible', brufenRow.ai_provider);

  section('What the provider is sent');
  const sent = aiRequests[0] || { body: { messages: [] } };
  const userMsg = sent.body.messages.find((m) => m.role === 'user')?.content || '';
  const systemMsg = sent.body.messages.find((m) => m.role === 'system')?.content || '';
  ok('POST /v1/chat/completions (trailing slash tolerated)', sent.url === '/v1/chat/completions', sent.url);
  ok('bearer key and model', sent.auth === 'Bearer fake-key' && sent.body.model === 'fake-model');
  ok('JSON mode and temperature 0', sent.body.response_format?.type === 'json_object' && sent.body.temperature === 0);
  ok('prompt lists the active cross-clinic med', userMsg.includes('Warfarin 5mg'));
  ok('prompt lists the new drug', userMsg.includes('Brufen 400mg'));
  ok('prompt carries the curated table', /ibuprofen \+ warfarin: CRITICAL/.test(userMsg));
  ok('system prompt comes from the prompt file', /Return JSON only/.test(systemMsg) && !systemMsg.includes('---USER---'));
  ok('no finished course is sent', !userMsg.includes('Amoxicillin'));

  section('Table and model agree on a pair');
  aiReply = () => ({ conflicts: [aiConflict('Warfarin 5mg', 'Ibuprofen 400mg', 'MINOR', 'Model prose for the pair.')] });
  const both = await checkRx(IBU);
  const bothList = both.body?.data?.conflicts || [];
  ok('reported once (model swapped the sides)', bothList.length === 1, JSON.stringify(bothList));
  ok('table severity wins', bothList[0]?.severity === 'CRITICAL', bothList[0]?.severity);
  ok("model's explanation kept", bothList[0]?.explanation === 'Model prose for the pair.');
  ok('table alternative kept when the model gives none', !!bothList[0]?.suggested_alternative);

  section('Model output is not trusted blindly');
  aiReply = () => ({ conflicts: [
    aiConflict('Brufen 400mg', 'Digoxin 250mcg', 'MAJOR'),          // not in either list
    aiConflict('Brufen 400mg', 'Warfarin 5mg', 'SEVERE'),           // unknown severity
    { new_drug: 'Brufen 400mg', existing_drug: 'Warfarin 5mg' },     // missing fields
  ] });
  const junk = await checkRx([rx('Brufen 400mg')]);
  ok('invented drugs and malformed entries dropped', junk.body?.data?.conflicts?.length === 0, JSON.stringify(junk.body?.data?.conflicts));
  ok('  and the AI still counts as available', junk.body?.data?.ai_available === true);

  aiReply = () => 'Sure! Here you go:\n```json\n' + JSON.stringify({ conflicts: [aiConflict('Brufen 400mg', 'Warfarin 5mg', 'MAJOR', 'Has a } brace.')] }) + '\n```';
  const fenced = await checkRx([rx('Brufen 400mg')]);
  ok('prose and code fences around the JSON tolerated', fenced.body?.data?.conflicts?.[0]?.explanation === 'Has a } brace.', JSON.stringify(fenced.body?.data));

  section('Same-visit pair only the model knows');
  const freshPatient = await newPatient();
  aiReply = () => ({ conflicts: [aiConflict('Brufen 400mg', 'Coumadin 5mg', 'CRITICAL')] });
  const aiSv = await checkRx([rx('Brufen 400mg'), rx('Coumadin 5mg')], freshPatient.id);
  const svAi = aiSv.body?.data?.conflicts?.[0] || {};
  ok('reported as SAME_VISIT with no clinic or date', svAi.scope === 'SAME_VISIT' && svAi.clinic_name === null && svAi.prescribed_on === null, JSON.stringify(svAi));

  section('Fail open');
  const expectTableOnly = (r, label) => {
    const list = r.body?.data?.conflicts || [];
    ok(`${label} → 200, table-only CRITICAL, ai_available false`,
      r.status === 200 && r.body.data.ai_available === false && list.length === 1 && list[0].source === 'TABLE' && list[0].severity === 'CRITICAL',
      JSON.stringify(r.body));
  };
  const quietErrors = console.error;
  console.error = () => {};
  try {
    aiReply = () => 'I cannot help with that.';
    expectTableOnly(await checkRx(IBU), 'unparseable reply');
    aiReply = () => ({ result: 'no conflicts key' });
    expectTableOnly(await checkRx(IBU), 'wrong JSON shape');
    aiReply = () => 'HTTP500';
    expectTableOnly(await checkRx(IBU), 'provider HTTP 500');

    aiReply = () => new Promise((r) => setTimeout(() => r({ conflicts: [] }), 4000));
    const slowStart = Date.now();
    const slow = await checkRx(IBU);
    const slowMs = Date.now() - slowStart;
    expectTableOnly(slow, 'provider slower than AI_TIMEOUT_MS');
    ok(`  gave up within the timeout (${slowMs} ms)`, slowMs < 3000);

    process.env.AI_BASE_URL = 'http://127.0.0.1:1/v1';
    expectTableOnly(await checkRx(IBU), 'unreachable host');
    process.env.AI_BASE_URL = `http://127.0.0.1:${fakeAi.address().port}/v1`;
  } finally {
    console.error = quietErrors;
  }

  aiRequests = [];
  process.env.AI_ENABLED = 'false';
  expectTableOnly(await checkRx(IBU), 'AI_ENABLED=false');
  ok('  and the provider is never called', aiRequests.length === 0);

  process.env.AI_ENABLED = 'true';
  process.env.AI_PROVIDER = 'no-such-provider';
  console.warn = () => {};
  expectTableOnly(await checkRx(IBU), 'unknown AI_PROVIDER');
  process.env.AI_PROVIDER = 'openai-compatible';
  delete process.env.AI_API_KEY;
  expectTableOnly(await checkRx(IBU), 'provider missing its key');

  await new Promise((r) => fakeAi.close(r));

  // ── cleanup ────────────────────────────────────────────────
  await prisma.interactionCheck.deleteMany({ where: { patient_id: { in: patientIds } } });
  await prisma.medicalRecord.deleteMany({ where: { patient_id: { in: patientIds } } });
  await prisma.patient.deleteMany({ where: { id: { in: patientIds } } });
  await prisma.doctor.deleteMany({ where: { id: { in: [doctorA.id, doctorB.id] } } });
  await prisma.user.deleteMany({ where: { id: { in: [doctorUser.id, patientUser.id] } } });
  await prisma.clinic.deleteMany({ where: { id: { in: [clinicA.id, clinicB.id] } } });

  const leftover =
    (await prisma.medicalRecord.count({ where: { patient_id: { in: patientIds } } })) +
    (await prisma.interactionCheck.count({ where: { patient_id: { in: patientIds } } })) +
    (await prisma.patient.count({ where: { id: { in: patientIds } } }));
  ok('fixtures removed', leftover === 0, `${leftover} rows left behind`);

  console.log(`\n${'═'.repeat(52)}`);
  console.log(`  ${failed === 0 ? '\x1b[32m' : '\x1b[31m'}${passed} passed, ${failed} failed\x1b[0m`);
  console.log(`${'═'.repeat(52)}\n`);

  await prisma.$disconnect();
  process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (err) => {
  console.error('\n❌ Suite aborted:', err);
  await prisma.$disconnect();
  process.exit(1);
});
