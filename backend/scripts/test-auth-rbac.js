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
// Phase 3: staff onboarding — invites, doctor applications, approve/reject/disable.
// Phase 5: desk registration (no account) and the patient's claim by date of birth.
// Phase 6: front desk — clinic queue, walk-ins with a named doctor, confirm, no records.
// Phase 7: consent — care link, app request, share code, emergency, revoke, access log, lookup.
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
  const IN_14_DAYS = new Date(Date.now() + 14 * 864e5);
  // Since Phase 3 an unlinked doctor is linked only through an invite.
  await prisma.staffInvite.create({
    data: { clinic_id: clinic.id, role: 'DOCTOR', phone: DOC_A_PHONE, name: `${TAG} Dr A`, specialization: 'GP', expires_at: IN_14_DAYS },
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
    'patient:register': ['POST', '/patients/register', {}],
    'record:read': ['GET', '/protected/doctor-only'],
    'record:write': ['POST', '/records', {}],
    'interaction:check': ['POST', '/records/interaction-check', {}],
    'report:upload': ['POST', '/records/not-a-uuid/upload'],
    'staff:manage': ['POST', '/doctors', {}],
    'clinic:update': ['PUT', '/clinics/not-a-uuid', {}],
    'clinic:create': ['POST', '/clinics', {}],
    'consent:respond': ['GET', '/consents/pending'],
    'consent:request': ['POST', '/consents', {}],
    'consent:emergency': ['POST', '/consents/emergency', {}],
    'audit:read': ['GET', '/audit/access'],
  };
  // Permissions whose endpoints arrive in a later phase.
  const LATER = [];

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

  // ═══════════════════════════════════════════════════════════
  // Phase 3: staff onboarding
  // ═══════════════════════════════════════════════════════════
  const emailToken = (uid, email, verified = true) =>
    token({ uid, provider: 'password', email, emailVerified: verified });
  const mail = (name) => `${name}-${TAG}@example.com`;
  const cadmin2 = await prisma.user.create({ data: { firebase_uid: `${TAG}-p3cadmin2`, email: mail('cadmin2'), role: 'CLINIC_ADMIN', clinic_id: clinic2.id } });
  const CADMIN2 = token({ uid: 'p3cadmin2', provider: 'password' });

  section('Phase 3 · /patients/me tells a new account where to go');
  r = await api('GET', '/patients/me', { token: token({ uid: 'p3newphone', phone: `+9192${N}` }) });
  ok('a phone sign-in with no profile → next REGISTER', r.status === 404 && r.body?.next === 'REGISTER', detail(r));
  r = await api('GET', '/patients/me', { token: emailToken('p3unverified', mail('unverified'), false) });
  ok('an unverified email sign-in → next VERIFY_EMAIL', r.status === 404 && r.body?.next === 'VERIFY_EMAIL', detail(r));
  r = await api('GET', '/patients/me', { token: emailToken('p3newmail', mail('newmail')) });
  ok('a verified email sign-in with no invite → next STAFF_APPLY', r.status === 404 && r.body?.next === 'STAFF_APPLY', detail(r));

  section('Phase 3 · invites');
  r = await api('POST', '/staff/invites', { token: ADMIN, body: { role: 'RECEPTIONIST', email: mail('Desk').toUpperCase(), name: 'Front Desk', clinic_id: clinic.id } });
  ok('ADMIN invites a receptionist by email', r.status === 201 && r.body?.data?.email === mail('desk'), detail(r));
  r = await api('POST', '/staff/invites', { token: ADMIN, body: { role: 'RECEPTIONIST', email: mail('desk'), name: 'Front Desk', clinic_id: clinic.id } });
  ok('a second open invite for the same email → 409', r.status === 409, detail(r));
  r = await api('POST', '/staff/invites', { token: ADMIN, body: { role: 'ADMIN', email: mail('boss'), name: 'Boss', clinic_id: clinic.id } });
  ok('ADMIN cannot be invited (bootstrap stays a script)', r.status === 400, detail(r));
  r = await api('POST', '/staff/invites', { token: ADMIN, body: { role: 'RECEPTIONIST', email: mail('recep'), name: 'Taken', clinic_id: clinic.id } });
  ok('an email that already has an account → 409', r.status === 409, detail(r));
  r = await api('POST', '/staff/invites', { token: AS.CLINIC_ADMIN, body: { role: 'RECEPTIONIST', email: mail('elsewhere'), name: 'Elsewhere', clinic_id: clinic2.id } });
  ok("a CLINIC_ADMIN cannot invite to another clinic", r.status === 403, detail(r));
  r = await api('POST', '/staff/invites', { token: AS.CLINIC_ADMIN, body: { role: 'DOCTOR', email: mail('newdoc'), name: 'New Doc', specialization: 'GP' } });
  ok('a CLINIC_ADMIN invite defaults to their own clinic', r.status === 201 && r.body?.data?.clinic_id === clinic.id, detail(r));

  r = await api('GET', '/patients/me', { token: emailToken('p3desk', mail('desk'), false) });
  ok('the invite is NOT accepted with an unverified email', r.status === 404, detail(r));
  ok('…and no account is created', (await prisma.user.count({ where: { firebase_uid: `${TAG}-p3desk` } })) === 0);
  const DESK = emailToken('p3desk', mail('desk'));
  r = await api('GET', '/patients/me', { token: DESK });
  ok('the invite IS accepted with the verified email', r.status === 200 && r.body?.data?.user?.role === 'RECEPTIONIST', detail(r));
  ok('…with the invite clinic and receptionist permissions',
    r.body?.data?.clinic?.id === clinic.id && JSON.stringify(r.body?.data?.permissions) === JSON.stringify(PERMISSIONS.RECEPTIONIST), detail(r));
  const deskUser = await prisma.user.findUnique({ where: { firebase_uid: `${TAG}-p3desk` } });
  ok('…and the invite is marked accepted',
    (await prisma.staffInvite.findFirst({ where: { email: mail('desk') } }))?.accepted_user_id === deskUser?.id);

  r = await api('GET', '/patients/me', { token: emailToken('p3newdoc', mail('newdoc')) });
  ok('a doctor invite with no existing Doctor row creates one', r.status === 200 && r.body?.data?.user?.role === 'DOCTOR' && r.body?.data?.specialization === 'GP', detail(r));

  await prisma.staffInvite.create({
    data: { clinic_id: clinic.id, role: 'RECEPTIONIST', email: mail('late'), name: 'Late', expires_at: new Date(Date.now() - 1000) },
  });
  r = await api('GET', '/patients/me', { token: emailToken('p3late', mail('late')) });
  ok('an expired invite is ignored', r.status === 404 && r.body?.next === 'STAFF_APPLY', detail(r));

  const LEGACY_PHONE = `+6017${N}`;
  const legacy = await prisma.doctor.create({
    data: { clinic_id: clinic.id, name: `${TAG} Dr Legacy`, specialization: 'GP', phone: LEGACY_PHONE },
  });
  await prisma.appointment.create({ data: { patient_id: patient2.id, doctor_id: legacy.id, clinic_id: clinic.id, slot_time: new Date() } });
  // What the migration inserts for every unlinked doctor.
  await prisma.staffInvite.create({
    data: { clinic_id: clinic.id, role: 'DOCTOR', phone: LEGACY_PHONE, name: legacy.name, specialization: 'GP', expires_at: IN_14_DAYS },
  });
  const LEGACY = token({ uid: 'p3legacy', phone: LEGACY_PHONE });
  r = await api('GET', '/patients/me', { token: LEGACY });
  ok('a legacy unlinked doctor is linked (same Doctor row)', r.status === 200 && r.body?.data?.id === legacy.id, detail(r));
  r = await api('GET', '/appointments', { token: LEGACY });
  ok('…with its appointments intact', r.status === 200 && r.body?.data?.length === 1 && r.body.data[0].doctor_id === legacy.id, detail(r));

  r = await api('GET', '/staff/invites', { token: AS.CLINIC_ADMIN });
  ok("a CLINIC_ADMIN lists only their clinic's invites, with a state",
    r.status === 200 && r.body.data.length > 0 && r.body.data.every((i) => i.clinic_id === clinic.id && i.state), detail(r));

  section('Phase 3 · POST /doctors is an invite alias');
  const ALIAS_PHONE = `+6018${N}`;
  r = await api('POST', '/doctors', { token: ADMIN, body: { name: `${TAG} Dr Alias`, clinic_id: clinic.id, specialization: 'GP', phone: ALIAS_PHONE } });
  const aliasDoctorId = r.body?.data?.id;
  ok('it returns 201 with the doctor (data.id is a Doctor id)', r.status === 201 && !!(await prisma.doctor.findUnique({ where: { id: aliasDoctorId || '00000000-0000-0000-0000-000000000000' } })), detail(r));
  ok('…and an invite', r.body?.data?.invite?.phone === ALIAS_PHONE && r.body?.data?.invite?.role === 'DOCTOR', detail(r));
  r = await api('GET', '/patients/me', { token: token({ uid: 'p3alias', phone: ALIAS_PHONE }) });
  ok('the doctor signs in and is linked to that row', r.status === 200 && r.body?.data?.id === aliasDoctorId, detail(r));

  section('Phase 3 · doctor applications');
  const APPLICATION = { name: `${TAG} Dr Applicant`, specialization: 'GP', registration_number: 'MMC-12345', registration_council: 'Malaysian Medical Council', clinic_id: clinic.id };
  r = await api('POST', '/staff/applications', { token: emailToken('p3unverified', mail('unverified'), false), body: APPLICATION });
  ok('an unverified email cannot apply', r.status === 403, detail(r));
  r = await api('POST', '/staff/applications', { token: AS.PATIENT, body: APPLICATION });
  ok('an existing account cannot apply', r.status === 409, detail(r));
  r = await api('POST', '/staff/applications', { token: emailToken('p3applicant', mail('applicant')), body: { ...APPLICATION, registration_number: '' } });
  ok('a registration number is required', r.status === 400, detail(r));

  const APPLICANT = emailToken('p3applicant', mail('applicant'));
  r = await api('POST', '/staff/applications', { token: APPLICANT, body: APPLICATION });
  ok('a verified email applies → DOCTOR PENDING', r.status === 201 && r.body?.data?.role === 'DOCTOR' && r.body?.data?.status === 'PENDING', detail(r));
  const applicantId = r.body?.data?.id;
  const applicantDoctorId = r.body?.data?.doctor?.id;
  r = await api('GET', '/patients/me', { token: APPLICANT });
  ok('a pending doctor has no permissions', r.status === 200 && r.body?.data?.status === 'PENDING' && r.body?.data?.permissions?.length === 0, detail(r));
  r = await api('GET', `/doctors?clinic_id=${clinic.id}`, { token: AS.PATIENT });
  ok('…is hidden from booking', r.status === 200 && !r.body.data.some((d) => d.id === applicantDoctorId), detail(r));
  r = await api('POST', '/appointments', { token: AS.PATIENT, body: { doctor_id: applicantDoctorId, clinic_id: clinic.id, slot_time: new Date(Date.now() + 864e5).toISOString() } });
  ok('…and cannot be booked by id', r.status === 404, detail(r));

  r = await api('GET', '/staff?status=PENDING', { token: AS.CLINIC_ADMIN });
  ok('the clinic admin sees the pending application with its registration number',
    r.status === 200 && r.body.data.some((u) => u.id === applicantId && u.doctor?.registration_number === 'MMC-12345'), detail(r));
  r = await api('GET', '/staff?status=PENDING', { token: CADMIN2 });
  ok("another clinic's admin does not see it", r.status === 200 && !r.body.data.some((u) => u.id === applicantId), detail(r));
  r = await api('POST', `/staff/${applicantId}/approve`, { token: CADMIN2 });
  ok("a CLINIC_ADMIN cannot approve another clinic's applicant", r.status === 403, detail(r));
  r = await api('POST', `/staff/${applicantId}/approve`, { token: AS.CLINIC_ADMIN });
  ok('the own clinic admin approves → ACTIVE', r.status === 200 && r.body?.data?.status === 'ACTIVE', detail(r));
  const verified = await prisma.doctor.findUnique({ where: { id: applicantDoctorId } });
  const cadminUser = await prisma.user.findUnique({ where: { firebase_uid: `${TAG}-p2cadmin` } });
  ok('…recording who verified the doctor and when', !!verified.verified_at && verified.verified_by_id === cadminUser.id);
  r = await api('GET', '/patients/me', { token: APPLICANT });
  ok('…the doctor now has doctor permissions', JSON.stringify(r.body?.data?.permissions) === JSON.stringify(PERMISSIONS.DOCTOR), detail(r));
  r = await api('GET', `/doctors?clinic_id=${clinic.id}`, { token: AS.PATIENT });
  ok('…and is bookable', r.body.data.some((d) => d.id === applicantDoctorId), detail(r));

  const REJECTED = emailToken('p3rejected', mail('rejected'));
  r = await api('POST', '/staff/applications', { token: REJECTED, body: { ...APPLICATION, name: `${TAG} Dr Rejected` } });
  r = await api('POST', `/staff/${r.body?.data?.id}/reject`, { token: AS.CLINIC_ADMIN });
  ok('a pending application can be rejected', r.status === 200, detail(r));
  r = await api('GET', '/patients/me', { token: REJECTED });
  ok('…which removes the account, so they may apply again', r.status === 404 && r.body?.next === 'STAFF_APPLY', detail(r));
  r = await api('POST', `/staff/${applicantId}/reject`, { token: AS.CLINIC_ADMIN });
  ok('an ACTIVE doctor cannot be "rejected"', r.status === 400, detail(r));

  section('Phase 3 · disable');
  r = await api('POST', `/staff/${cadminUser.id}/disable`, { token: AS.CLINIC_ADMIN });
  ok('you cannot disable yourself', r.status === 400, detail(r));
  r = await api('POST', `/staff/${cadmin2.id}/disable`, { token: AS.CLINIC_ADMIN });
  ok("a CLINIC_ADMIN cannot disable another clinic's staff", r.status === 403, detail(r));
  const adminUser = await prisma.user.findUnique({ where: { firebase_uid: `${TAG}-admin` } });
  r = await api('POST', `/staff/${adminUser.id}/disable`, { token: AS.CLINIC_ADMIN });
  ok('a CLINIC_ADMIN cannot disable a platform ADMIN', r.status === 403, detail(r));
  r = await api('POST', `/staff/${patientUser.id}/disable`, { token: ADMIN });
  ok('patients are not staff (404)', r.status === 404, detail(r));
  r = await api('POST', `/staff/${deskUser.id}/disable`, { token: AS.CLINIC_ADMIN });
  ok('the clinic admin disables their receptionist', r.status === 200 && r.body?.data?.status === 'DISABLED', detail(r));
  r = await api('GET', '/appointments', { token: DESK });
  ok('…who now gets 403 on every call', r.status === 403 && /disabled/.test(r.body?.message), detail(r));
  r = await api('POST', `/staff/${deskUser.id}/approve`, { token: AS.CLINIC_ADMIN });
  ok('approve re-enables a disabled account', r.status === 200 && r.body?.data?.status === 'ACTIVE', detail(r));

  // ═══════════════════════════════════════════════════════════
  // Phase 5: desk registration and claim
  // ═══════════════════════════════════════════════════════════
  const DESK_PHONE = `+9189${N}`;
  const LOCK_PHONE = `+9188${N}`;
  const recepUser = await prisma.user.findUnique({ where: { firebase_uid: `${TAG}-p2recep` } });

  section('Phase 5 · desk registration');
  r = await api('POST', '/patients/register', { token: AS.RECEPTIONIST, body: { ...PATIENT_FORM, dob: '1988-04-12' } });
  ok('a phone is required', r.status === 400, detail(r));
  r = await api('POST', '/patients/register', { token: AS.RECEPTIONIST, body: { ...PATIENT_FORM, dob: '1988-04-12', phone: DESK_PHONE.slice(3) } });
  const deskPatient = r.body?.data;
  ok('a receptionist registers a walk-in with no account (10-digit phone → E.164)',
    r.status === 201 && deskPatient?.user_id === null && deskPatient?.phone === DESK_PHONE && /^MWH-/.test(deskPatient?.health_id || ''), detail(r));
  ok('…recording who registered them', deskPatient?.registered_by_user_id === recepUser.id);
  r = await api('POST', '/patients/register', { token: AS.DOCTOR, body: { ...PATIENT_FORM, phone: DESK_PHONE } });
  ok('the same phone again → 409 with the existing health ID', r.status === 409 && r.body?.data?.health_id === deskPatient?.health_id, detail(r));

  section('Phase 5 · patients sign in without a phone');
  const GOOGLE_PATIENT = token({ uid: 'p5google', provider: 'google.com', email: mail('google'), emailVerified: true });
  r = await api('POST', '/patients', { token: GOOGLE_PATIENT, body: PATIENT_FORM });
  ok('a Google account without a linked phone cannot register as a patient', r.status === 400, detail(r));
  r = await api('POST', '/patients/claim', { token: GOOGLE_PATIENT, body: { dob: '1988-04-12' } });
  ok('…nor claim a profile', r.status === 404, detail(r));
  r = await api('POST', '/patients', { token: AS.DOCTOR, body: PATIENT_FORM });
  ok('a staff account cannot give itself a patient profile', r.status === 403, detail(r));

  section('Phase 5 · claim by date of birth');
  // A Google sign-in that linked the desk phone looks like this to the backend.
  const CLAIMER = token({ uid: 'p5claimer', phone: DESK_PHONE, provider: 'google.com', email: mail('claimer'), emailVerified: true });
  r = await api('GET', '/patients/me', { token: CLAIMER });
  ok('signing in on the desk phone → next CLAIM', r.status === 404 && r.body?.next === 'CLAIM', detail(r));
  r = await api('POST', '/patients/claim', { token: CLAIMER, body: { dob: '1988-4-12' } });
  ok('the date must be YYYY-MM-DD', r.status === 400, detail(r));
  r = await api('POST', '/patients/claim', { token: CLAIMER, body: { dob: '1988-12-04' } });
  ok('a wrong date of birth → 403 with attempts left', r.status === 403 && r.body?.attempts_left === 4, detail(r));
  ok('…and links nothing', (await prisma.patient.findUnique({ where: { id: deskPatient.id } })).user_id === null);
  r = await api('POST', '/patients/claim', { token: CLAIMER, body: { dob: '1988-04-12' } });
  ok('the right date of birth links the profile', r.status === 200 && r.body?.data?.id === deskPatient.id && r.body?.data?.permissions?.includes('self:profile'), detail(r));
  r = await api('GET', '/patients/me', { token: CLAIMER });
  ok('…/me now returns it', r.status === 200 && r.body?.data?.health_id === deskPatient.health_id, detail(r));
  r = await api('POST', '/patients/claim', { token: CLAIMER, body: { dob: '1988-04-12' } });
  ok('claiming twice → 409', r.status === 409, detail(r));

  r = await api('POST', '/patients/register', { token: AS.CLINIC_ADMIN, body: { ...PATIENT_FORM, dob: '1975-06-30', phone: LOCK_PHONE } });
  ok('a clinic admin can register at the desk too', r.status === 201, detail(r));
  const GUESSER = token({ uid: 'p5guesser', phone: LOCK_PHONE });
  const guesses = [];
  for (let i = 0; i < 5; i++) guesses.push(await api('POST', '/patients/claim', { token: GUESSER, body: { dob: `1975-01-0${i + 1}` } }));
  ok('4 wrong dates → 403, the 5th → 423 locked',
    guesses.slice(0, 4).every((g) => g.status === 403) && guesses[4].status === 423, guesses.map((g) => g.status).join());
  r = await api('POST', '/patients/claim', { token: GUESSER, body: { dob: '1975-06-30' } });
  ok('…and while locked even the right date is refused', r.status === 423, detail(r));
  const parallel = await Promise.all(Array.from({ length: 8 }, (_, i) =>
    api('POST', '/patients/claim', { token: GUESSER, body: { dob: `1975-02-0${i + 1}` } })));
  ok('…parallel guesses do not get past the lock', parallel.every((g) => g.status === 423), parallel.map((g) => g.status).join());

  // ═══════════════════════════════════════════════════════════
  // Phase 6: receptionist front desk
  // ═══════════════════════════════════════════════════════════
  section('Phase 6 · clinic queue and walk-ins');
  const inDays = (d) => new Date(Date.now() + d * 864e5);
  const pendingA = await prisma.appointment.create({ data: { patient_id: patient2.id, doctor_id: doctorA.id, clinic_id: clinic.id, slot_time: inDays(2) } });
  const pendingB = await prisma.appointment.create({ data: { patient_id: patient2.id, doctor_id: doctorB.id, clinic_id: clinic.id, slot_time: inDays(3) } });
  const pendingOther = await prisma.appointment.create({ data: { patient_id: patient2.id, doctor_id: doctorOther.id, clinic_id: clinic2.id, slot_time: inDays(2) } });

  r = await api('GET', '/appointments', { token: AS.RECEPTIONIST });
  const queueDoctors = new Set((r.body?.data || []).map((a) => a.doctor_id));
  ok('the receptionist queue lists every doctor at the clinic, each named',
    r.status === 200 && queueDoctors.has(doctorA.id) && queueDoctors.has(doctorB.id) &&
      r.body.data.every((a) => a.clinic_id === clinic.id && a.doctor?.name), detail(r));
  r = await api('POST', '/appointments', { token: AS.RECEPTIONIST, body: { patient_id: deskPatient.id } });
  ok('a receptionist walk-in must name the doctor', r.status === 400, detail(r));
  r = await api('POST', '/appointments', { token: AS.RECEPTIONIST, body: { patient_id: deskPatient.id, doctor_id: doctorOther.id, clinic_id: clinic.id } });
  ok("…and can't pass another clinic's doctor off as their own", r.status === 400, detail(r));
  r = await api('POST', '/appointments', { token: AS.RECEPTIONIST, body: { patient_id: deskPatient.id, doctor_id: doctorA.id } });
  const walkIn = r.body?.data;
  ok('a desk-registered patient is booked with a doctor, confirmed', r.status === 201 && walkIn?.status === 'confirmed' && walkIn?.clinic_id === clinic.id, detail(r));
  r = await api('GET', '/appointments', { token: DOC_A });
  ok('…and the doctor sees them in their queue', r.status === 200 && r.body.data.some((a) => a.id === walkIn?.id), detail(r));

  section('Phase 6 · confirm / reschedule / cancel at the clinic');
  r = await api('PATCH', `/appointments/${pendingA.id}/confirm`, { token: AS.PATIENT });
  ok('a patient cannot confirm', gateDenied(r), detail(r));
  r = await api('PATCH', `/appointments/${pendingA.id}/confirm`, { token: CADMIN2 });
  ok("another clinic's admin cannot confirm", r.status === 403, detail(r));
  r = await api('PATCH', `/appointments/${pendingB.id}/confirm`, { token: DOC_A });
  ok("a doctor cannot confirm a colleague's appointment", r.status === 403, detail(r));
  r = await api('PATCH', `/appointments/${pendingOther.id}/confirm`, { token: AS.RECEPTIONIST });
  ok("a receptionist cannot confirm another clinic's appointment", r.status === 403, detail(r));
  r = await api('PATCH', `/appointments/${pendingB.id}/confirm`, { token: AS.RECEPTIONIST });
  ok("a receptionist confirms any doctor's appointment at their clinic", r.status === 200 && r.body?.data?.status === 'confirmed', detail(r));
  r = await api('PATCH', `/appointments/${pendingB.id}/confirm`, { token: AS.RECEPTIONIST });
  ok('…but only once (it is no longer pending)', r.status === 400, detail(r));
  r = await api('PATCH', `/appointments/${pendingA.id}/confirm`, { token: DOC_A });
  ok('a doctor confirms their own', r.status === 200, detail(r));
  r = await api('PUT', `/appointments/${pendingA.id}`, { token: AS.RECEPTIONIST, body: { slot_time: inDays(4).toISOString() } });
  ok('a receptionist reschedules at their clinic', r.status === 200, detail(r));
  r = await api('PUT', `/appointments/${pendingOther.id}`, { token: AS.RECEPTIONIST, body: { slot_time: inDays(4).toISOString() } });
  ok('…not at another clinic', r.status === 403, detail(r));
  r = await api('PATCH', `/appointments/${pendingA.id}/cancel`, { token: AS.RECEPTIONIST });
  ok('a receptionist cancels at their clinic', r.status === 200, detail(r));

  section('Phase 6 · the front desk never sees records');
  for (const [method, endpoint] of [['GET', `/records/patient/${deskPatient.id}`], ['GET', `/records/${rec.id}`],
    ['POST', '/records'], ['POST', '/records/interaction-check'], ['POST', `/records/${rec.id}/upload`]]) {
    r = await api(method, endpoint, { token: AS.RECEPTIONIST, body: method === 'POST' ? { patient_id: deskPatient.id } : undefined });
    ok(`RECEPTIONIST ${method} ${endpoint.replace(/[0-9a-f-]{36}/g, ':id')} → 403`, r.status === 403, detail(r));
  }

  // ═══════════════════════════════════════════════════════════
  // Phase 7: consent
  // ═══════════════════════════════════════════════════════════
  const docP7User = await prisma.user.create({ data: { firebase_uid: `${TAG}-p7doc`, email: mail('p7doc'), role: 'DOCTOR' } });
  await prisma.doctor.create({ data: { user_id: docP7User.id, clinic_id: clinic2.id, name: `${TAG} Dr Far`, specialization: 'GP', email: mail('p7doc') } });
  const FAR = token({ uid: 'p7doc', provider: 'password' }); // a doctor at clinic2, no link to p7
  const p7User = await prisma.user.create({ data: { firebase_uid: `${TAG}-p7pat`, phone: `+9187${N}`, role: 'PATIENT' } });
  const p7 = await prisma.patient.create({
    data: { user_id: p7User.id, health_id: `MWH-${N.slice(-6)}`, name: `Zed ${TAG}`, phone: `+9187${N}`, dob: new Date('1980-03-03'), gender: 'Male', language_pref: 'Hindi' },
  });
  const P7 = token({ uid: 'p7pat', phone: `+9187${N}` });
  const p7Record = await prisma.medicalRecord.create({ data: { patient_id: p7.id, doctor_id: doctorA.id, visit_date: new Date(), diagnosis: 'Asthma', notes: '' } });
  const history = (tok, id = p7.id) => api('GET', `/records/patient/${id}`, { token: tok });
  const logs = (where) => prisma.patientAccessLog.findMany({ where: { patient_id: p7.id, ...where }, orderBy: { created_at: 'desc' } });

  section('Phase 7 · records need a care link, consent or emergency');
  r = await history(FAR);
  ok('a doctor at another clinic gets 403 CONSENT_REQUIRED', r.status === 403 && r.body?.code === 'CONSENT_REQUIRED', detail(r));
  r = await history(FAR, p7.health_id);
  ok('…by Health ID too', r.status === 403 && r.body?.code === 'CONSENT_REQUIRED', detail(r));
  r = await api('GET', `/records/${p7Record.id}`, { token: FAR });
  ok('…and for a single record', r.status === 403 && r.body?.code === 'CONSENT_REQUIRED', detail(r));
  r = await api('POST', '/records', { token: FAR, body: { patient_id: p7.id, diagnosis: 'Checkup' } });
  ok('…and to write a visit', r.status === 403 && r.body?.code === 'CONSENT_REQUIRED', detail(r));
  r = await api('POST', '/records/interaction-check', { token: FAR, body: { patient_id: p7.id, prescriptions: [] } });
  ok('…and to run an interaction check', r.status === 403 && r.body?.code === 'CONSENT_REQUIRED', detail(r));
  r = await api('POST', `/records/${p7Record.id}/upload`, { token: FAR });
  ok('…and to upload a report', r.status === 403 && r.body?.code === 'CONSENT_REQUIRED', detail(r));
  r = await history(FAR, '00000000-0000-4000-8000-000000000000');
  ok('an unknown patient is still a 404', r.status === 404, detail(r));
  ok('refused requests write no log rows', (await logs({})).length === 0);

  r = await history(DOC_A);
  let [row] = await logs({});
  ok('the doctor who wrote a record reads via CARE', r.status === 200 && row?.via === 'CARE' && row?.action === 'READ_HISTORY', detail(r));
  ok('…logged with who and which clinic', row?.user_id === (await prisma.user.findUnique({ where: { firebase_uid: `${TAG}-docA` } })).id && row?.clinic_id === clinic.id);
  const before7 = (await logs({})).length;
  await api('GET', `/records/${p7Record.id}`, { token: DOC_A });
  ok('every allowed read writes a row', (await logs({})).length === before7 + 1);
  r = await history(P7);
  ok("the patient reads their own history, and it isn't logged", r.status === 200 && (await logs({})).length === before7 + 1, detail(r));

  section('Phase 7 · lookup and search');
  r = await api('GET', `/patients/lookup?health_id=${p7.health_id.toLowerCase()}`, { token: FAR });
  ok('exact Health ID lookup → demographics, masked phone, access refused',
    r.status === 200 && r.body?.data?.name === p7.name && r.body.data.phone !== p7.phone && r.body.data.phone.endsWith(p7.phone.slice(-4)) &&
      r.body.data.access?.allowed === false, detail(r));
  r = await api('GET', `/patients/lookup?phone=${p7.phone.slice(3)}`, { token: DOC_A });
  ok('exact phone lookup reports CARE for the treating doctor', r.status === 200 && r.body?.data?.access?.via === 'CARE', detail(r));
  r = await api('GET', '/patients/lookup', { token: FAR });
  ok('lookup needs a Health ID or phone', r.status === 400, detail(r));
  r = await api('GET', '/patients/lookup?health_id=MWH-NOPE00', { token: FAR });
  ok('no match → 404', r.status === 404, detail(r));
  r = await api('GET', `/patients/search?q=${encodeURIComponent('Zed ' + TAG)}`, { token: FAR });
  ok("name search doesn't reach patients outside the caller's clinic", r.status === 200 && r.body.data.length === 0, detail(r));
  r = await api('GET', `/patients/search?q=${p7.health_id}`, { token: FAR });
  ok('…an exact Health ID does, with the phone masked', r.status === 200 && r.body.data.length === 1 && r.body.data[0].phone.includes('*'), detail(r));
  r = await api('GET', '/patients/search?q=Fixture%20Patient', { token: AS.RECEPTIONIST });
  ok("name search finds the clinic's own patients, phone shown", r.status === 200 && r.body.data.some((p) => p.id === patient.id && p.phone === patient.phone), detail(r));

  section('Phase 7 · in-app request');
  r = await api('POST', '/consents', { token: FAR, body: { patient_id: p7.id } });
  const req1 = r.body?.data;
  ok('the doctor asks → PENDING for 10 minutes', r.status === 201 && req1?.status === 'PENDING' && new Date(req1.expires_at) - Date.now() <= 10 * 60e3, detail(r));
  r = await api('GET', '/consents/pending', { token: P7 });
  ok('the patient sees it with the doctor and clinic', r.status === 200 && r.body.data.some((c) => c.id === req1?.id && c.doctor?.name && c.clinic?.id === clinic2.id), detail(r));
  r = await api('POST', `/consents/${req1?.id}/respond`, { token: AS.PATIENT, body: { approve: true } });
  ok("another patient can't answer it", r.status === 404, detail(r));
  r = await api('POST', `/consents/${req1?.id}/respond`, { token: P7, body: { approve: 'yes' } });
  ok('approve must be a boolean', r.status === 400, detail(r));
  r = await api('POST', `/consents/${req1?.id}/respond`, { token: P7, body: { approve: true } });
  ok('the patient approves → a 24-hour grant', r.status === 200 && r.body?.data?.status === 'APPROVED' && new Date(r.body.data.granted_until) - Date.now() > 23 * 3600e3, detail(r));
  r = await api('GET', `/consents/${req1?.id}`, { token: FAR });
  ok('the doctor polls it as APPROVED', r.status === 200 && r.body?.data?.status === 'APPROVED', detail(r));
  r = await history(FAR);
  [row] = await logs({});
  ok('…and reads the history via CONSENT, linked to the grant', r.status === 200 && row?.via === 'CONSENT' && row?.consent_id === req1?.id, detail(r));
  r = await api('POST', `/consents/${req1?.id}/respond`, { token: P7, body: { approve: false } });
  ok('an answered request cannot be answered again', r.status === 409, detail(r));
  r = await api('POST', `/consents/${req1?.id}/revoke`, { token: P7 });
  ok('the patient revokes it', r.status === 200 && r.body?.data?.status === 'REVOKED', detail(r));
  r = await history(FAR);
  ok('…and the doctor is refused again', r.status === 403 && r.body?.code === 'CONSENT_REQUIRED', detail(r));
  r = await api('POST', `/consents/${req1?.id}/revoke`, { token: P7 });
  ok('revoking twice → 409', r.status === 409, detail(r));

  r = await api('POST', '/consents', { token: FAR, body: { patient_id: p7.id } });
  const req2 = r.body?.data;
  r = await api('POST', `/consents/${req2?.id}/respond`, { token: P7, body: { approve: false } });
  ok('the patient denies → DENIED', r.status === 200 && r.body?.data?.status === 'DENIED', detail(r));
  r = await history(FAR);
  ok('…and the doctor gets 403', r.status === 403, detail(r));
  r = await api('POST', '/consents', { token: FAR, body: { patient_id: p7.id } });
  ok('a 3rd request in the hour is allowed', r.status === 201, detail(r));
  r = await api('POST', '/consents', { token: FAR, body: { patient_id: p7.id } });
  ok('the 4th → 429', r.status === 429, detail(r));

  const stale = await prisma.consentRequest.create({
    data: { patient_id: p7.id, doctor_id: (await prisma.doctor.findUnique({ where: { user_id: docP7User.id } })).id, clinic_id: clinic2.id, method: 'APP', status: 'PENDING', expires_at: new Date(Date.now() - 1000) },
  });
  r = await api('POST', `/consents/${stale.id}/respond`, { token: P7, body: { approve: true } });
  ok('an expired request cannot be approved', r.status === 409, detail(r));
  r = await api('GET', `/consents/${stale.id}`, { token: FAR });
  ok('…and polls as EXPIRED', r.body?.data?.status === 'EXPIRED', detail(r));
  r = await api('GET', `/consents/${stale.id}`, { token: DOC_A });
  ok("a doctor can't poll someone else's request", r.status === 404, detail(r));

  section('Phase 7 · share code');
  r = await api('POST', '/consents/share-code', { token: P7 });
  const code1 = r.body?.data?.code;
  ok('the patient gets a 6-digit code', r.status === 201 && /^\d{6}$/.test(code1 || ''), detail(r));
  ok('…stored only as a hash', (await prisma.consentRequest.findUnique({ where: { id: r.body?.data?.id } }))?.code_hash?.length === 64);
  const wrong = (c) => String((Number(c) + 1) % 1e6).padStart(6, '0');
  r = await api('POST', '/consents/redeem', { token: FAR, body: { patient_id: p7.id, code: '12' } });
  ok('the code must be 6 digits', r.status === 400, detail(r));
  r = await api('POST', '/consents/redeem', { token: FAR, body: { patient_id: p7.id, code: wrong(code1) } });
  ok('a wrong code → 403 with attempts left', r.status === 403 && r.body?.attempts_left === 4, detail(r));
  r = await api('POST', '/consents/redeem', { token: FAR, body: { patient_id: p7.id, code: code1 } });
  ok('the right code → a 24-hour grant', r.status === 200 && r.body?.data?.status === 'APPROVED', detail(r));
  r = await history(FAR);
  ok('…and the history opens', r.status === 200, detail(r));
  r = await api('POST', '/consents/redeem', { token: FAR, body: { patient_id: p7.id, code: code1 } });
  ok('a code works once', r.status === 404, detail(r));

  r = await api('POST', '/consents/share-code', { token: P7 });
  const code2 = r.body?.data?.code;
  const bad = [];
  for (let i = 0; i < 5; i++) bad.push((await api('POST', '/consents/redeem', { token: DOC_A, body: { patient_id: p7.id, code: wrong(code2) } })).status);
  r = await api('POST', '/consents/redeem', { token: DOC_A, body: { patient_id: p7.id, code: code2 } });
  ok('5 wrong codes lock it: even the right one → 423', bad.every((s) => s === 403) && r.status === 423, `${bad} then ${r.status}`);

  section('Phase 7 · emergency access');
  r = await api('GET', '/consents/mine', { token: P7 });
  const live = (r.body?.data?.consents || []).filter((c) => c.status === 'APPROVED');
  ok('the patient lists their grants', r.status === 200 && live.length === 1 && live[0].method === 'CODE', detail(r));
  await api('POST', `/consents/${live[0]?.id}/revoke`, { token: P7 });
  r = await api('POST', '/consents/emergency', { token: FAR, body: { patient_id: p7.id, reason: 'urgent' } });
  ok('emergency without a real reason → 400', r.status === 400, detail(r));
  const REASON = 'Unconscious on arrival, need allergy history';
  r = await api('POST', '/consents/emergency', { token: FAR, body: { patient_id: p7.id, reason: REASON } });
  ok('emergency with a reason → a 4-hour grant', r.status === 201 && r.body?.data?.method === 'EMERGENCY' && new Date(r.body.data.granted_until) - Date.now() <= 4 * 3600e3, detail(r));
  r = await history(FAR);
  [row] = await logs({});
  ok('…the history opens via EMERGENCY', r.status === 200 && row?.via === 'EMERGENCY', detail(r));
  r = await api('GET', '/consents/mine', { token: P7 });
  ok("…flagged in the patient's access history with the reason",
    r.body?.data?.access_log?.some((l) => l.via === 'EMERGENCY' && l.consent?.reason === REASON && l.user?.doctor?.clinic?.id === clinic2.id), detail(r));
  r = await api('GET', '/audit/access', { token: CADMIN2 });
  ok("…and in that clinic's audit list", r.status === 200 && r.body.data.some((l) => l.via === 'EMERGENCY' && l.patient?.id === p7.id), detail(r));
  r = await api('GET', `/audit/access?clinic_id=${clinic2.id}`, { token: AS.CLINIC_ADMIN });
  ok("a clinic admin can't read another clinic's audit list", r.status === 403, detail(r));
  r = await api('GET', '/audit/access', { token: AS.CLINIC_ADMIN });
  ok('…only their own', r.status === 200 && r.body.data.length > 0 && r.body.data.every((l) => l.clinic_id === clinic.id), detail(r));
  r = await api('GET', '/audit/access', { token: ADMIN });
  ok('ADMIN reads across clinics', r.status === 200 && new Set(r.body.data.map((l) => l.clinic_id)).size >= 2, detail(r));

  section('Phase 7 · a walk-in creates a care link');
  const p7b = await prisma.patient.create({
    data: { health_id: `MWH-B${N.slice(-5)}`, name: 'Walk-in Care', phone: `+9186${N}`, dob: new Date('1970-07-07'), gender: 'Female', language_pref: 'Tamil' },
  });
  r = await history(FAR, p7b.id);
  ok('no link before the visit', r.status === 403, detail(r));
  r = await api('POST', '/appointments', { token: CADMIN2, body: { patient_id: p7b.id, doctor_id: doctorOther.id } });
  const walk = r.body?.data;
  r = await history(FAR, p7b.id);
  const [careRow] = await prisma.patientAccessLog.findMany({ where: { patient_id: p7b.id } });
  ok('a walk-in at the clinic → CARE, logged with the appointment', r.status === 200 && careRow?.via === 'CARE' && careRow?.appointment_id === walk?.id, detail(r));
  await api('PATCH', `/appointments/${walk?.id}/cancel`, { token: CADMIN2 });
  r = await history(FAR, p7b.id);
  ok('a cancelled appointment is no care link', r.status === 403, detail(r));

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
    where: { OR: [{ id: { in: [patient.id, patient2.id, p7b.id] } }, { user_id: { in: userIds } }, { phone: { in: [DESK_PHONE, LOCK_PHONE] } }] },
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
