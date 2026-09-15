// backend/scripts/test-auth-rbac.js
// ============================================================
// Registration / RBAC / consent — end-to-end regression suite
// ============================================================
// Grows one section per phase of AUTH_RBAC_CONSENT_PLAN.md.
// Phase 1: identity hardening — role from the DB only, phone only from the
// verified token, no phone-based identity fallbacks, guests refused in
// production.
// Phase 2: roles + permission table — a role × endpoint matrix generated from
// config/permissions.js, account status, clinic scope.
//
// Same harness as scripts/test-interactions.js: Firebase is stubbed in
// require.cache before the app loads and the real Express app is driven over
// HTTP, so authenticate → requirePermission → controller → errorHandler all run.
//
// Usage:
//   node scripts/test-auth-rbac.js          (DATABASE_URL from backend/.env)
//
// Fixtures are tagged and removed at the end. Point it at a development DB.
// ============================================================

'use strict';

const path = require('path');

const BACKEND = path.resolve(__dirname, '..');
const PORT = process.env.TEST_PORT || 3996;

process.env.PORT = String(PORT);
process.env.NODE_ENV = 'development';
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
const { toE164 } = require(path.join(BACKEND, 'utils/phone'));
const { PERMISSIONS } = require(path.join(BACKEND, 'config/permissions'));

const quiet = !process.env.VERBOSE;
if (quiet) {
  const write = process.stdout.write.bind(process.stdout);
  process.stdout.write = (chunk, ...rest) =>
    /^\x1b\[0m(GET|POST|PUT|DELETE|PATCH) /.test(String(chunk)) ? true : write(chunk, ...rest);
  const error = console.error.bind(console);
  console.error = (...args) => (/^❌/.test(String(args[0])) ? undefined : error(...args));
}

require(path.join(BACKEND, 'server.js'));

const BASE = `http://127.0.0.1:${PORT}/api`;
const TAG = 'authtest-' + Date.now();
const N = String(Date.now()).slice(-8); // unique digits for E.164 fixtures

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

const section = (title) => console.log(`\n\x1b[1m── ${title} ──\x1b[0m`);

/** Fake Firebase ID token. provider: 'phone' | 'password' | 'anonymous' | ... */
function token({ uid, phone = null, provider = 'phone', email = null, emailVerified = false, extra = {} }) {
  const decoded = {
    uid: `${TAG}-${uid}`,
    phone_number: phone,
    email,
    email_verified: emailVerified,
    firebase: { sign_in_provider: provider },
    ...extra,
  };
  return 'test.' + Buffer.from(JSON.stringify(decoded)).toString('base64');
}

async function api(method, endpoint, { token: tok, body } = {}) {
  const res = await fetch(BASE + endpoint, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(tok ? { Authorization: `Bearer ${tok}` } : {}),
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

const gateDenied = (r) => r.status === 403 && /Requires permission/.test(r.body?.message || '');
const detail = (r) => `(got ${r.status}: ${r.body?.message || ''})`;

async function main() {
  await new Promise((r) => setTimeout(r, 1200)); // let the server bind

  const PATIENT_FORM = { name: 'Test Patient', dob: '1990-01-01', gender: 'Male', language_pref: 'English' };

  // ── fixtures ───────────────────────────────────────────────
  const clinic = await prisma.clinic.create({
    data: { name: `${TAG} Clinic`, location: 'Test', contact_number: `${TAG}-c` },
  });
  const DOC_A_PHONE = `+6012${N}`;
  const doctorA = await prisma.doctor.create({
    data: { clinic_id: clinic.id, name: `${TAG} Dr A`, specialization: 'GP', phone: DOC_A_PHONE },
  });
  const doctorB = await prisma.doctor.create({
    data: { clinic_id: clinic.id, name: `${TAG} Dr B`, specialization: 'GP', phone: `+6014${N}` },
  });
  await prisma.user.create({ data: { firebase_uid: `${TAG}-admin`, phone: `${TAG}-admin`, role: 'ADMIN' } });
  await prisma.user.create({ data: { firebase_uid: `${TAG}-nodoc`, phone: `${TAG}-nodoc`, role: 'DOCTOR' } });
  const patient = await prisma.patient.create({
    data: { health_id: `${TAG}-hid`, name: 'Fixture Patient', phone: `+9197${N}`, dob: new Date('1985-05-05'), gender: 'Female', language_pref: 'Tamil' },
  });
  await prisma.appointment.create({
    data: { patient_id: patient.id, doctor_id: doctorB.id, clinic_id: clinic.id, slot_time: new Date() },
  });

  const ADMIN = token({ uid: 'admin' });
  const NO_DOC = token({ uid: 'nodoc' });

  // ───────────────────────────────────────────────────────────
  section('toE164');
  ok('spaces and dashes are stripped', toE164('+91 99999-00001') === '+919999900001');
  ok('a bare 10-digit number gets +91', toE164('9999900001') === '+919999900001');
  ok('a 00 international prefix becomes +', toE164('0065 6123 4567') === '+6561234567');
  ok('a short number without a country code is refused', toE164('61234567') === null);
  ok('the guest placeholder is not a phone', toE164('guest-abc') === null);
  ok('non-strings are refused', toE164(null) === null && toE164(9999900001) === null);

  // ───────────────────────────────────────────────────────────
  section('The role comes from the database only');
  const stranger = token({ uid: 'stranger', provider: 'password', email: 'x@example.com', extra: { role: 'ADMIN' } });
  let r = await api('GET', '/appointments', { token: stranger });
  ok('an unregistered user claiming ADMIN in the token gets 403 on staff routes', r.status === 403, detail(r));
  r = await api('GET', '/appointments/me', { token: stranger });
  ok('an unregistered user is not treated as a PATIENT', r.status === 403, detail(r));
  r = await api('POST', '/records', { token: stranger, body: { patient_id: patient.id, diagnosis: 'Checkup' } });
  ok('an unregistered user cannot write records', r.status === 403, detail(r));

  // ───────────────────────────────────────────────────────────
  section('Patient registration takes the phone from the token only');
  const noPhone = token({ uid: 'nophone', provider: 'password', email: 'np@example.com', emailVerified: true });
  r = await api('POST', '/patients', { token: noPhone, body: { ...PATIENT_FORM, phone: `+9196${N}` } });
  ok('a phone in the body is not accepted without a verified token phone', r.status === 400, detail(r));
  ok('no user row is created for it', (await prisma.user.count({ where: { firebase_uid: `${TAG}-nophone` } })) === 0);

  const REG_PHONE = `+9195${N}`;
  r = await api('POST', '/patients', {
    token: token({ uid: 'reg', phone: REG_PHONE }),
    body: { ...PATIENT_FORM, phone: `+9194${N}` },
  });
  ok('registration with a verified phone succeeds', r.status === 201, detail(r));
  ok('the stored phone is the token phone, not the body phone', r.body?.data?.phone === REG_PHONE, `(got ${r.body?.data?.phone})`);

  // ───────────────────────────────────────────────────────────
  section('Guest (anonymous) sign-in');
  const guest = token({ uid: 'guest', provider: 'anonymous' });
  r = await api('POST', '/patients', { token: guest, body: PATIENT_FORM });
  ok('outside production a guest can register', r.status === 201, detail(r));
  ok('the guest gets the placeholder phone', r.body?.data?.phone === `guest-${TAG}-guest`);
  process.env.NODE_ENV = 'production';
  r = await api('GET', '/patients/me', { token: guest });
  ok('in production a guest token is refused with 401', r.status === 401, detail(r));
  r = await api('GET', '/patients/me', { token: token({ uid: 'reg', phone: REG_PHONE }) });
  ok('in production a phone user is unaffected', r.status === 200, detail(r));
  process.env.NODE_ENV = 'development';

  // ───────────────────────────────────────────────────────────
  section('Doctor account linking needs an exact phone match');
  const lookalike = token({ uid: 'lookalike', phone: `+91${DOC_A_PHONE.slice(-10)}` });
  r = await api('GET', '/patients/me', { token: lookalike });
  ok('same last 10 digits, different country code → not linked', r.status === 404, detail(r));
  ok('the doctor row stays unlinked', (await prisma.doctor.findUnique({ where: { id: doctorA.id } })).user_id === null);

  const DOC_A = token({ uid: 'docA', phone: DOC_A_PHONE });
  r = await api('GET', '/patients/me', { token: DOC_A });
  ok('the exact verified phone links the doctor', r.status === 200 && r.body?.data?.user?.role === 'DOCTOR', detail(r));
  ok('the doctor row is now linked', (await prisma.doctor.findUnique({ where: { id: doctorA.id } })).user_id !== null);

  r = await api('POST', '/doctors', {
    token: ADMIN,
    body: { name: `${TAG} Dr C`, clinic_id: clinic.id, specialization: 'GP', phone: `0060 13${N}` },
  });
  ok('POST /doctors stores the phone as E.164', r.status === 201 && r.body?.data?.phone === `+6013${N}`, detail(r));
  r = await api('POST', '/doctors', {
    token: ADMIN,
    body: { name: `${TAG} Dr D`, clinic_id: clinic.id, specialization: 'GP', phone: '61234567' },
  });
  ok('POST /doctors refuses a phone without a country code', r.status === 400, detail(r));

  // ───────────────────────────────────────────────────────────
  section('Visit records are saved under the right doctor');
  r = await api('POST', '/records', { token: DOC_A, body: { patient_id: patient.id, diagnosis: 'Checkup', doctor_id: doctorB.id } });
  ok('a doctor cannot save a visit under another doctor', r.status === 403, detail(r));
  r = await api('POST', '/records', { token: DOC_A, body: { patient_id: patient.id, diagnosis: 'Checkup' } });
  ok('a doctor saves under their own profile', r.status === 201, detail(r));
  ok('…and the record names that doctor',
    (await prisma.medicalRecord.count({ where: { patient_id: patient.id, doctor_id: doctorA.id } })) === 1);

  const before = await prisma.medicalRecord.count({ where: { patient_id: patient.id } });
  r = await api('POST', '/records', { token: ADMIN, body: { patient_id: patient.id, diagnosis: 'Checkup' } });
  ok('an ADMIN cannot save a visit (record:write is DOCTOR only, since Phase 2)', r.status === 403, detail(r));
  r = await api('POST', '/records', { token: ADMIN, body: { patient_id: patient.id, diagnosis: 'Checkup', doctor_id: doctorB.id } });
  ok('…not even naming the doctor', r.status === 403, detail(r));
  ok('…and nothing is saved', (await prisma.medicalRecord.count({ where: { patient_id: patient.id } })) === before);
  r = await api('POST', '/records', { token: NO_DOC, body: { patient_id: patient.id, diagnosis: 'Checkup' } });
  ok('a DOCTOR role with no doctor profile cannot save', r.status === 403, detail(r));

  // ───────────────────────────────────────────────────────────
  section('Appointment lists are scoped, with no phone fallbacks');
  r = await api('GET', '/appointments', { token: NO_DOC });
  ok('a DOCTOR role with no doctor profile gets 403, not every appointment', r.status === 403, detail(r));
  r = await api('GET', '/appointments', { token: DOC_A });
  ok('a linked doctor only sees their own schedule',
    r.status === 200 && Array.isArray(r.body?.data) && r.body.data.every((a) => a.doctor_id === doctorA.id), detail(r));

  await prisma.user.create({ data: { firebase_uid: `${TAG}-phonematch`, phone: `${TAG}-pm`, role: 'PATIENT' } });
  r = await api('GET', '/appointments/me', { token: token({ uid: 'phonematch', phone: patient.phone }) });
  ok("a matching phone does not unlock another patient's appointments", r.status === 404, detail(r));


  // ═══════════════════════════════════════════════════════════
  // Phase 2: roles and permission table
  // ═══════════════════════════════════════════════════════════
  const clinic2 = await prisma.clinic.create({
    data: { name: `${TAG} Clinic 2`, location: 'Test', contact_number: `${TAG}-c2` },
  });
  const doctorOther = await prisma.doctor.create({
    data: { clinic_id: clinic2.id, name: `${TAG} Dr Other`, specialization: 'GP', phone: `+6015${N}` },
  });
  const patientUser = await prisma.user.create({ data: { firebase_uid: `${TAG}-p2pat`, phone: `+9193${N}`, role: 'PATIENT' } });
  const patient2 = await prisma.patient.create({
    data: { user_id: patientUser.id, health_id: `${TAG}-hid2`, name: 'P2 Patient', phone: `+9193${N}`, dob: new Date('1991-01-01'), gender: 'Male', language_pref: 'Hindi' },
  });
  await prisma.user.create({ data: { firebase_uid: `${TAG}-p2recep`, email: `recep-${TAG}@example.com`, role: 'RECEPTIONIST', clinic_id: clinic.id } });
  await prisma.user.create({ data: { firebase_uid: `${TAG}-p2cadmin`, email: `cadmin-${TAG}@example.com`, role: 'CLINIC_ADMIN', clinic_id: clinic.id } });
  const pendingUser = await prisma.user.create({ data: { firebase_uid: `${TAG}-p2pending`, email: `pending-${TAG}@example.com`, role: 'DOCTOR', status: 'PENDING' } });
  await prisma.doctor.create({ data: { user_id: pendingUser.id, clinic_id: clinic.id, name: `${TAG} Dr Pending`, specialization: 'GP', email: `pending-${TAG}@example.com` } });
  await prisma.user.create({ data: { firebase_uid: `${TAG}-p2disabled`, email: `disabled-${TAG}@example.com`, role: 'ADMIN', status: 'DISABLED' } });

  const AS = {
    PATIENT: token({ uid: 'p2pat', phone: `+9193${N}` }),
    RECEPTIONIST: token({ uid: 'p2recep', provider: 'password' }),
    DOCTOR: DOC_A, // linked to doctorA at `clinic` above
    CLINIC_ADMIN: token({ uid: 'p2cadmin', provider: 'password' }),
    ADMIN,
  };
  const PENDING = token({ uid: 'p2pending', provider: 'password' });
  const DISABLED = token({ uid: 'p2disabled', provider: 'password' });

  // One request per permission, gated by that permission alone. A holder gets
  // past the gate; everyone else gets the gate's own 403. The message is checked
  // because a controller can also answer 403 and would hide a loosened gate.
  const ENDPOINTS = {
    'self:profile': ['GET', '/appointments/me'],
    'patient:lookup': ['GET', '/patients/search?q=a'],
    'appointment:manage': ['GET', '/appointments?status=bogus'],
    'record:read': ['GET', '/protected/doctor-only'],
    'record:write': ['POST', '/records', {}],
    'interaction:check': ['POST', '/records/interaction-check', {}],
    'report:upload': ['POST', '/records/not-a-uuid/upload'],
    'staff:manage': ['POST', '/doctors', {}],
    'clinic:update': ['PUT', '/clinics/not-a-uuid', {}],
    'clinic:create': ['POST', '/clinics', {}],
  };
  // Permissions whose endpoints arrive in a later phase.
  const LATER = ['consent:respond', 'patient:register', 'consent:request', 'consent:emergency', 'audit:read'];

  section('Phase 2 · every permission in the table is tested');
  const allPerms = [...new Set(Object.values(PERMISSIONS).flat())];
  const untested = allPerms.filter((p) => !ENDPOINTS[p] && !LATER.includes(p));
  ok('every permission has an endpoint in the matrix or is listed as later', untested.length === 0, `(untested: ${untested})`);
  ok('the table has exactly the 5 roles', Object.keys(PERMISSIONS).sort().join() === 'ADMIN,CLINIC_ADMIN,DOCTOR,PATIENT,RECEPTIONIST');

  section('Phase 2 · role × endpoint matrix (from config/permissions.js)');
  for (const [perm, [method, endpoint, body]] of Object.entries(ENDPOINTS)) {
    for (const [role, tok] of Object.entries(AS)) {
      const has = PERMISSIONS[role].includes(perm);
      r = await api(method, endpoint, { token: tok, body });
      ok(`${role.padEnd(12)} ${has ? 'passes' : 'blocked'}  ${perm} (${method} ${endpoint})`,
        has ? r.status !== 401 && !gateDenied(r) : gateDenied(r), detail(r));
    }
    r = await api(method, endpoint, { token: PENDING, body });
    ok(`PENDING      blocked  ${perm}`, gateDenied(r), detail(r));
  }

  section('Phase 2 · /patients/me sends permissions, status and clinic');
  for (const [role, tok] of Object.entries(AS)) {
    r = await api('GET', '/patients/me', { token: tok });
    ok(`${role} /me lists exactly its table permissions`,
      r.status === 200 && JSON.stringify(r.body?.data?.permissions) === JSON.stringify(PERMISSIONS[role]), detail(r));
  }
  r = await api('GET', '/patients/me', { token: AS.CLINIC_ADMIN });
  ok('a clinic admin gets a staff profile with its clinic', r.body?.data?.status === 'ACTIVE' && r.body?.data?.clinic?.id === clinic.id, detail(r));
  r = await api('GET', '/patients/me', { token: AS.DOCTOR });
  ok("a doctor's clinic is the doctor row's clinic", r.body?.data?.clinic?.id === clinic.id, detail(r));
  r = await api('GET', '/patients/me', { token: PENDING });
  ok('a PENDING user can load /me, with status PENDING and no permissions',
    r.status === 200 && r.body?.data?.status === 'PENDING' && r.body?.data?.permissions?.length === 0, detail(r));

  section('Phase 2 · account status');
  r = await api('GET', '/patients/me', { token: DISABLED });
  ok('a DISABLED user gets 403 even on /me', r.status === 403, detail(r));
  r = await api('GET', '/clinics', { token: DISABLED });
  ok('…and on open authenticated routes', r.status === 403, detail(r));

  section('Phase 2 · records are DOCTOR only (plus a patient\'s own)');
  for (const role of ['ADMIN', 'RECEPTIONIST', 'CLINIC_ADMIN']) {
    r = await api('GET', `/records/patient/${patient.id}`, { token: AS[role] });
    ok(`${role} cannot read a patient's history`, r.status === 403, detail(r));
  }
  const rec = await prisma.medicalRecord.findFirst({ where: { patient_id: patient.id } });
  r = await api('GET', `/records/${rec.id}`, { token: AS.RECEPTIONIST });
  ok('RECEPTIONIST cannot read a single record', r.status === 403, detail(r));
  r = await api('GET', `/records/patient/${patient.id}`, { token: AS.DOCTOR });
  ok('DOCTOR can read the history', r.status === 200, detail(r));
  r = await api('GET', `/records/patient/${patient2.id}`, { token: AS.PATIENT });
  ok('a patient reads their own history', r.status === 200, detail(r));
  r = await api('GET', `/records/patient/${patient.id}`, { token: AS.PATIENT });
  ok("a patient cannot read someone else's history", r.status === 403, detail(r));
  r = await api('GET', `/patients/${patient.id}`, { token: AS.ADMIN });
  ok('ADMIN no longer opens patient profiles (no patient:lookup)', r.status === 403, detail(r));
  r = await api('GET', `/patients/${patient.id}`, { token: AS.RECEPTIONIST });
  ok('RECEPTIONIST opens patient demographics (patient:lookup)', r.status === 200, detail(r));

  section('Phase 2 · clinic scope');
  r = await api('PUT', `/clinics/${clinic2.id}`, { token: AS.CLINIC_ADMIN, body: { location: 'Elsewhere' } });
  ok("a CLINIC_ADMIN cannot update another clinic", r.status === 403, detail(r));
  r = await api('PUT', `/clinics/${clinic.id}`, { token: AS.CLINIC_ADMIN, body: { location: 'Moved' } });
  ok('a CLINIC_ADMIN updates their own clinic', r.status === 200, detail(r));
  r = await api('PUT', `/clinics/${clinic2.id}`, { token: ADMIN, body: { location: 'Anywhere' } });
  ok('ADMIN updates any clinic', r.status === 200, detail(r));
  r = await api('POST', '/doctors', { token: AS.CLINIC_ADMIN, body: { name: `${TAG} Dr X`, clinic_id: clinic2.id, specialization: 'GP', phone: `+6016${N}` } });
  ok("a CLINIC_ADMIN cannot add a doctor to another clinic", r.status === 403, detail(r));
  r = await api('PUT', `/doctors/${doctorOther.id}`, { token: AS.CLINIC_ADMIN, body: { name: 'Renamed' } });
  ok("a CLINIC_ADMIN cannot edit another clinic's doctor", r.status === 403, detail(r));
  r = await api('PUT', `/doctors/${doctorB.id}`, { token: AS.CLINIC_ADMIN, body: { clinic_id: clinic2.id } });
  ok('a CLINIC_ADMIN cannot move their doctor to another clinic', r.status === 403, detail(r));
  r = await api('PUT', `/doctors/${doctorB.id}`, { token: AS.CLINIC_ADMIN, body: { specialization: 'Dermatology' } });
  ok('a CLINIC_ADMIN edits their own doctor', r.status === 200, detail(r));

  await prisma.appointment.create({
    data: { patient_id: patient2.id, doctor_id: doctorOther.id, clinic_id: clinic2.id, slot_time: new Date() },
  });
  r = await api('GET', '/appointments', { token: AS.RECEPTIONIST });
  ok("clinic staff list only their own clinic's appointments",
    r.status === 200 && r.body.data.length > 0 && r.body.data.every((a) => a.clinic_id === clinic.id), detail(r));
  r = await api('GET', `/appointments?clinic_id=${clinic2.id}`, { token: AS.RECEPTIONIST });
  ok('…and cannot ask for another clinic', r.status === 403, detail(r));
  r = await api('POST', '/appointments', { token: AS.RECEPTIONIST, body: { patient_id: patient2.id, doctor_id: doctorOther.id } });
  ok("a walk-in with another clinic's doctor is refused", r.status === 403, detail(r));
  r = await api('POST', '/appointments', { token: AS.DOCTOR, body: { patient_id: patient2.id, doctor_id: doctorB.id } });
  ok("a doctor cannot book a walk-in on a colleague's schedule", r.status === 403, detail(r));
  r = await api('POST', '/appointments', { token: AS.RECEPTIONIST, body: { patient_id: patient2.id, doctor_id: doctorB.id } });
  ok('a receptionist books a walk-in with their own clinic\'s doctor', r.status === 201, detail(r));
  const otherAppt = await prisma.appointment.findFirst({ where: { clinic_id: clinic2.id } });
  r = await api('PATCH', `/appointments/${otherAppt.id}/cancel`, { token: AS.CLINIC_ADMIN });
  ok("a CLINIC_ADMIN cannot cancel another clinic's appointment", r.status === 403, detail(r));
  r = await api('PATCH', `/appointments/${otherAppt.id}/cancel`, { token: ADMIN });
  ok('ADMIN no longer manages appointments', r.status === 403, detail(r));
  r = await api('PATCH', `/appointments/${otherAppt.id}/cancel`, { token: AS.PATIENT });
  ok('the patient cancels their own appointment', r.status === 200, detail(r));

  // ───────────────────────────────────────────────────────────
  section('A database failure is a 500, not a logout');
  const findUnique = prisma.user.findUnique;
  prisma.user.findUnique = async () => {
    throw new Error('simulated DB outage');
  };
  r = await api('GET', '/patients/me', { token: DOC_A });
  prisma.user.findUnique = findUnique;
  ok('the app is not sent a 401/403 that would end the session', r.status === 500, detail(r));

  // ── cleanup ────────────────────────────────────────────────
  const users = await prisma.user.findMany({ where: { firebase_uid: { startsWith: TAG } }, select: { id: true } });
  const userIds = users.map((u) => u.id);
  const patients = await prisma.patient.findMany({
    where: { OR: [{ id: { in: [patient.id, patient2.id] } }, { user_id: { in: userIds } }] },
    select: { id: true },
  });
  const patientIds = patients.map((p) => p.id);
  await prisma.medicalRecord.deleteMany({ where: { patient_id: { in: patientIds } } });
  await prisma.appointment.deleteMany({ where: { patient_id: { in: patientIds } } });
  await prisma.patient.deleteMany({ where: { id: { in: patientIds } } });
  const clinicIds = [clinic.id, clinic2.id];
  await prisma.appointment.deleteMany({ where: { clinic_id: { in: clinicIds } } });
  await prisma.doctor.deleteMany({ where: { clinic_id: { in: clinicIds } } });
  await prisma.user.deleteMany({ where: { id: { in: userIds } } });
  await prisma.clinic.deleteMany({ where: { id: { in: clinicIds } } });

  const leftover =
    (await prisma.user.count({ where: { firebase_uid: { startsWith: TAG } } })) +
    (await prisma.patient.count({ where: { id: { in: patientIds } } })) +
    (await prisma.clinic.count({ where: { id: { in: clinicIds } } }));
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
