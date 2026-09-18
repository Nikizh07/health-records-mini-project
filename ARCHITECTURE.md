# Architecture

Complete technical reference for the Cloud-Based Digital Health Record & Appointment Management System, as of 2026-09-18.

`README.md` is the setup and quick-start guide. `MEMORY.md` is the running log of decisions and gotchas. `SNAPSHOT.md` is the file map. **This file is the "how it works" document.**

---

## 1. What the system is

A cross-clinic health record and appointment platform for migrant worker clinics. The defining product decision: **a patient's medical history follows the patient, not the clinic.** A doctor at Clinic B can see what Clinic A prescribed — which is what makes the drug-interaction detector possible, and what makes the consent system necessary.

Three actors and five roles:

| Role | Who | Sees records? |
|---|---|:-:|
| `PATIENT` | the worker | own only |
| `RECEPTIONIST` | front desk | **never** |
| `DOCTOR` | clinician | yes, gated by care link or consent |
| `CLINIC_ADMIN` | runs one clinic | **never** (staff + audit only) |
| `ADMIN` | platform operator | **never** (clinics + staff + audit only) |

Separation of duties is deliberate: administrative power and clinical data access are disjoint. A platform admin can create clinics and invite staff but cannot read a single diagnosis.

---

## 2. Topology

```
┌──────────────────────┐        Firebase ID token        ┌────────────────────────┐
│  Flutter app         │ ──────────────────────────────► │  Express API (:3000)   │
│  Android + Web       │        JSON over HTTPS          │  Node 22               │
│  (patient + clinic)  │ ◄────────────────────────────── │                        │
└──────────┬───────────┘                                 └───────┬────────────────┘
           │                                                     │
           │ sign-in (phone OTP, Google, email/password)          │ verifyIdToken
           ▼                                                     ▼
┌──────────────────────┐                                 ┌────────────────────────┐
│  Firebase Auth       │ ◄────── firebase-admin ───────── │  (identity only)       │
└──────────────────────┘                                 └───────┬────────────────┘
                                                                 │ Prisma 7 + pg
                                                                 ▼
                                                         ┌────────────────────────┐
                                                         │  PostgreSQL 16         │
                                                         └────────────────────────┘
                                                                 │
                                    optional, fails open         ▼
                                                         ┌────────────────────────┐
                                                         │  LLM provider          │
                                                         │  (OpenAI-compatible /  │
                                                         │   Bedrock / SageMaker) │
                                                         └────────────────────────┘
```

**The app never touches the database or storage directly.** Everything goes through the API. Firebase is the identity provider and nothing else — no Firestore, no Firebase Storage, no Cloud Functions.

---

## 3. Backend

### 3.1 Stack

| Concern | Choice |
|---|---|
| Runtime | Node.js 22 |
| HTTP | Express 4 |
| ORM | Prisma 7 with the `@prisma/adapter-pg` driver adapter over a `pg` Pool |
| Database | PostgreSQL 16 |
| Identity | `firebase-admin` 14 (token verification only) |
| Uploads | `multer` 2, local disk |
| Logging | `morgan` (dev only) |
| Optional | `@aws-sdk/client-bedrock-runtime`, `@aws-sdk/client-sagemaker-runtime` as `optionalDependencies`, lazily required |

Nine production dependencies. No test framework, no validation library, no DI container, no ORM abstraction on top of the ORM.

### 3.2 Layering

```
routes/        HTTP surface: path, method, and the middleware chain. No logic.
middleware/    Cross-cutting gates: authenticate → permission → patient access.
controllers/   Request handling, scope checks, Prisma queries, response shaping.
services/      Reusable domain logic (only where it earned its place).
config/        Singletons: prisma, firebase, and the permission table.
utils/         Pure functions: phone, health ID, drug names, prescription windows.
prisma/        Schema and migrations.
scripts/       Seeds, the role-setting bootstrap, and the two test suites.
```

Controllers call Prisma directly. Only two things were pulled into `services/`: the patient access resolver (used by middleware) and the drug interaction checker (used by two endpoints). Everything else stayed in its controller.

### 3.3 Entry point

`server.js` is seven ordered steps, each commented:

1. `dotenv` first, before anything reads `process.env`
2. create the Express app
3. global middleware: `cors()`, `express.json()`, `express.urlencoded()`, static `/uploads`, `morgan` in dev
4. mount `routes/index.js` at `/api`
5. `notFound` (after routes)
6. `errorHandler` (last, identified by its 4-argument signature)
7. listen on `PORT` (default 3000; Cloud Run/ECS inject their own)

`routes/index.js` is the single place every sub-router is mounted: `/health`, `/protected`, `/patients`, `/clinics`, `/doctors`, `/appointments`, `/records`, `/staff`, `/consents`, `/audit`.

### 3.4 The request pipeline

This is the core of the design. Everything else is CRUD hanging off it.

```
HTTP request
  │
  ├─ cors, json body parser
  ├─ /api router → sub-router
  │
  ├─ authenticate            who are you?                   → req.user      (401 / 403)
  ├─ requirePermission(...)  may your role do this at all?  → 403
  ├─ requirePatientAccess()  is this patient yours?         → 403 CONSENT_REQUIRED
  │                          (records routes only; writes the audit row)
  ├─ controller              is this resource in your scope? → 400 / 403 / 404
  │                          then Prisma
  │
  └─ errorHandler            single exit for anything thrown
```

#### `middleware/authenticate.js`

1. Parses `Authorization: Bearer <token>`; missing or malformed → 401.
2. `auth.verifyIdToken()`; invalid or expired → 401 with a specific message per Firebase error code.
3. **Anonymous (guest) tokens are refused when `NODE_ENV=production`** → 401.
4. Loads the `users` row by `firebase_uid`, including its `patient` and `doctor` profiles.
5. `status === 'DISABLED'` → 403 on every route, regardless of a valid token.
6. Builds `req.user`:

```js
{
  uid, phone_number, email, email_verified, sign_in_provider,
  role,          // from the DB only
  status,        // ACTIVE | PENDING | DISABLED
  clinic_id,     // doctor.clinic_id ?? user.clinic_id
  permissions,   // computed from role + status
  db_id, patient_id, doctor_id,
  firebase       // the raw decoded token
}
```

Three load-bearing decisions live in this file:

- **The database is the only source of role.** There is no `role` claim read from the token and no `PATIENT` default. A signed-in Firebase user with no `users` row gets `role: null`, no permissions, and 403 everywhere until they register or an invite links them.
- **`phone_number` is the verified token phone, never a value from the request body or the DB.** This closed the original hole where a caller could claim any phone.
- **A database failure becomes `next(error)` → 500, not 401.** The Flutter client ends the session on 401/403, so returning 401 during a DB outage used to log every user out.

#### `middleware/requirePermission.js`

Twenty lines. Passes when `req.user.permissions` contains **any** of the listed permissions, otherwise 403 with the message `Requires permission: <list>`. That exact message matters: the test matrix distinguishes a gate refusal from a controller refusal by it.

#### `config/permissions.js` — the one table

```js
PATIENT:      ['self:profile', 'consent:respond']
RECEPTIONIST: ['patient:register', 'patient:lookup', 'appointment:manage']
DOCTOR:       ['patient:register', 'patient:lookup', 'appointment:manage',
               'record:read', 'record:write', 'interaction:check', 'report:upload',
               'consent:request', 'consent:emergency']
CLINIC_ADMIN: ['patient:register', 'patient:lookup', 'appointment:manage',
               'staff:manage', 'clinic:update', 'audit:read']
ADMIN:        ['staff:manage', 'clinic:update', 'clinic:create', 'audit:read']
```

Plus two helpers:

- `permissionsFor(role, status)` returns `[]` unless the status is `ACTIVE`. **PENDING and DISABLED accounts are powerless by construction**, not by scattered checks.
- `outsideOwnClinic(user, clinicId)` is the shared clinic-scope test, with the platform `ADMIN` exempt.

This file is the contract in three directions at once: the API gates on it, `/patients/me` ships the permission array to the Flutter app (which builds its navigation and dashboard tiles from it, never from the role name), and `scripts/test-auth-rbac.js` **generates its role × endpoint matrix from this file**, so the table, the routes and the tests cannot drift apart. The suite fails if a permission has neither an endpoint nor an explicit `LATER` entry.

### 3.5 Authorization is three layers

| Layer | Question | Enforced by |
|---|---|---|
| Permission | Can this **role** do this action at all? | `requirePermission` on the route |
| Scope | Is this resource in **your** clinic / yours? | controllers, via `outsideOwnClinic` |
| Patient access | May you go near **this patient's history**? | `requirePatientAccess` → `resolveAccess` |

Layer 2 examples: a `DOCTOR` manages only their own schedule (booking a walk-in onto a colleague's schedule is 403); a `RECEPTIONIST` and `CLINIC_ADMIN` manage any appointment at their own clinic and nothing beyond it; a `CLINIC_ADMIN` cannot approve, disable or even list staff outside their clinic, and cannot touch a platform `ADMIN`.

### 3.6 Patient access and consent — `services/patientAccess.js`

`resolveAccess(user, patientId)` → `{ allowed, via, consent_id?, appointment_id? }`, tried in order:

1. **SELF** — `user.patient_id === patientId`.
2. Otherwise, bail out immediately unless the caller holds `record:read` **and** has a doctor profile. This single line is why receptionists, clinic admins and platform admins can never reach records by any path.
3. **CARE** — this doctor wrote a record for this patient, **or** the patient has a non-cancelled appointment at this doctor's clinic within **±30 days**. A walk-in booking therefore creates a care link, which is how patients with no smartphone are covered.
4. **CONSENT / EMERGENCY** — an `APPROVED` `ConsentRequest` for this doctor with `granted_until > now`; `via` is `EMERGENCY` when the grant's method was emergency, otherwise `CONSENT`.
5. Anything else → denied.

`middleware/requirePatientAccess(action, locate)` wraps the resolver:

- **Three locators**, because the five record routes name the patient in three different places: `fromParam('patientId')`, `fromBody` (`body.patient_id`), `fromRecord` (look up the record, take its `patient_id`).
- Refusal → 403 with `code: 'CONSENT_REQUIRED'` and `patient_id`, but only for callers who hold `consent:request` (a doctor who can actually do something about it); everyone else gets a plain 403. The Flutter client keys its entire consent gate off that `code`.
- Every allowed **non-SELF** access writes a `PatientAccessLog` row **before** the controller runs, and **fails closed**: if the audit row cannot be written, the request fails. No silent unlogged reads.
- **SELF reads are deliberately not logged** — the patient app polls its own records every 10 seconds and would flood the table.

Two documented sharp edges:

- It **passes through when it cannot identify the patient** (malformed id, no such patient or record) and relies on the controller behind it to answer 400/404. The consequence: the locator must find patients *exactly* as the controller does. The history route accepts a bare health ID as well as a UUID, so the locator does too. Change one without the other and a request slips past the gate.
- On the upload route it is placed **before multer**, so a refused upload never lands on disk.

`middleware/authorizePatientAccess.js` still exists and is separate: it guards `GET|PUT /patients/:id` demographics, where `patient:lookup` staff are meant to pass. The record routes stopped using it in Phase 2.

### 3.7 Consent flows

Backed by `ConsentRequest` and driven by `controllers/consent.controller.js`. All state changes are conditional `updateMany` calls, so concurrent requests cannot race past a limit.

1. **In-app request** — the doctor `POST /consents`; the row is `PENDING`, expires in 10 minutes, limit 3 per doctor/patient per hour (4th → 429). The patient app polls `GET /consents/pending` every 10 s and shows an Allow/Deny dialog; the doctor's screen polls its own request every 3 s. Approval grants 24 hours. A new request from the same doctor retires their previous pending one, so the patient never sees a stack of popups.
2. **Share code** — for patients without the app on hand. `POST /consents/share-code` returns a 6-digit code, valid 10 minutes, single use, stored as `sha256(id:code)`. The doctor redeems with **`{patient_id, code}`** — not a bare code, which would be guessable across every live code in the system. The attempt counter is taken atomically *before* comparing; 5 wrong tries → 423 and the code is dead. Generating a new code retires the old one.
3. **Emergency** — `POST /consents/emergency` with a reason of at least 20 characters → a 4-hour grant, flagged red in the clinic audit list and in the patient's own access history.
4. **Revoke** — the patient can end any live grant at any time; the next read is 403.

Status is **computed on read**: a lapsed `PENDING` or an expired grant reads as `EXPIRED`. Nothing sweeps the table, so there is no cron job and no drift between what the DB says and what the API reports.

### 3.8 Staff onboarding

Two ways in, and exactly one bootstrap.

- **Bootstrap (CLI only, by design):** `node scripts/set-user-role.js <phone|email> ADMIN`. The account must have signed into Firebase once; if it has no `users` row the script creates one from the Firebase account. The same script can set any of the five roles (clinic roles need a `clinic_id`). This is the only account creation path with no UI — everything downstream happens in the app.
- **Invite:** `POST /staff/invites` (`staff:manage`) creates a `StaffInvite` for `RECEPTIONIST`, `DOCTOR` or `CLINIC_ADMIN` — never `ADMIN`. It carries a role, clinic, name, an email or a phone, and a 14-day expiry. **No email is sent**; the admin tells the person the portal URL. On the invitee's first `GET /patients/me`, `acceptInvite` runs: it takes the newest open invite matching the token phone or a **verified** email, creates the user with the invite's role and clinic, and for a `DOCTOR` links an existing unlinked `Doctor` row with the same phone or email — keeping its appointment history — or creates one. An identifier that already has a `users` row, or already has an open invite, is refused with 409.
- **Self-apply:** `POST /staff/applications` from a signed-in user with a verified email and no DB row → a `User` with role `DOCTOR` and status `PENDING`, plus a `Doctor` row with a registration number and council. Pending doctors have no permissions, are hidden from `GET /doctors`, and `bookAppointment` refuses them by id. A clinic admin checks the council register by hand, then `POST /staff/:userId/approve` (also re-enables a `DISABLED` account, and stamps `verified_at`/`verified_by_id` on first approval) or `reject` (deletes the pending user and Doctor row, so they can apply again). Nobody can act on their own account.

`POST /doctors` is kept as a compatibility alias: it creates **both** the invite and the unlinked `Doctor` row, so the existing Postman collection and admin screens keep working.

### 3.9 Patient registration

- **Self-service:** sign in (phone OTP, or Google/email then an OTP phone-link) → `/patients/me` returns `next: 'REGISTER'` → `POST /patients`. The phone comes only from the token. A staff account calling this gets 403 rather than being handed a patient profile.
- **At the desk:** `POST /patients/register` (`patient:register`) creates a `Patient` with `user_id = null` from `{name, dob, gender, language_pref, phone}`. A duplicate phone returns 409 **with the existing health ID**, so the front desk can find the person instead of creating a second chart.
- **Claim:** when that patient later signs in with OTP on the same number, `/patients/me` returns `next: 'CLAIM'` and asks for the date of birth. `POST /patients/claim {dob}` links the account on a match; a mismatch is 403 with `attempts_left`. **Five wrong dates lock the claim for 24 hours** (423) — a lock, not a permanent bar, since there is no unlock screen. The attempt is taken atomically before comparing, so parallel guesses cannot beat the limit.

The DOB check is the point of the whole flow: without it, a mistyped phone number at the front desk would hand someone else's medical history to whoever owns that number.

### 3.10 `GET /patients/me` — the session control tower

One endpoint decides where every session belongs. It returns a full profile for a known user, otherwise a 404 carrying a `next`:

| `next` | Meaning | App destination |
|---|---|---|
| `REGISTER` | phone/guest sign-in, no patient row | patient registration form |
| `CLAIM` | the verified phone matches an unlinked patient | DOB claim screen |
| `VERIFY_EMAIL` | email sign-in, not yet verified | verification screen |
| `STAFF_APPLY` | verified email, no invite | doctor application |

It also runs `acceptInvite` before giving up, and reports `status: 'PENDING'` for applicants awaiting approval. Its payload always includes `permissions`, `status` and `clinic` for every role.

### 3.11 Drug interaction detector

The system's other distinctive feature, and the reason cross-clinic history exists.

`services/interactionChecker.js` loads every prescription the patient is probably still taking **across all clinics** (deliberately not filtered by clinic or doctor — seeing Clinic A's drugs at Clinic B is the entire point), then checks:

- each new drug against each active drug, and
- each new drug against the other new drugs **in the same prescription** (a pair written together in one visit),

against the curated `drug_interactions` table (56 seeded pairs). Conflicts carry a `scope`: `EXISTING` (names the source `clinic_name` and `prescribed_on`) or `SAME_VISIT` (both null, confidence `CERTAIN`). Results are ranked most severe first. Dedupe is by ordered pair, and the existing-medication leg runs first so the richer conflict wins when both legs find the same pair.

`utils/drugName.js` `normaliseDrugName()` is the contract between the seeder and the checker — if one side changes normalisation and the other doesn't, lookups silently return nothing with no error. `utils/prescriptionWindow.js` decides whether a prescription is still active; an unparseable duration counts as active for 90 days and marks the conflict `confidence: 'ASSUMED'` (a false warning is cheaper than a missed one).

**Audit wiring:** `POST /records/interaction-check` stores an `InteractionCheck` row and returns its `check_id`. `createMedicalRecord` accepts `check_id` and `override_reason`; with a `check_id` the conflicts are re-read **from the stored row, never from the request body**. If that row recorded conflicts, a non-empty `override_reason` is required or the save is refused with 400. After the record is written, the check row is linked back with `record_id`, `overridden` and the reason. A check row is single-use — reusing one that already has a `record_id` is a 400 — so the audit trail can say exactly which save the doctor was warned about. `overridden` is true only when conflicts were actually found, so the trail never claims a dismissed warning that was never shown.

### 3.12 The AI layer

`services/ai/` is a pluggable provider registry, configured **entirely by environment variables** — no code change to switch models.

```js
PROVIDERS = {
  'openai-compatible': ...,  // plain fetch; OpenAI, Gemini's compat endpoint,
                             // Groq, OpenRouter, Ollama, vLLM, any custom URL
  bedrock:  ...,             // @aws-sdk/client-bedrock-runtime, lazily required
  sagemaker: ...,            // @aws-sdk/client-sagemaker-runtime, lazily required
}
```

Every provider exports `{ name, isConfigured(), complete({system, user}) -> string }`. Adding one is a file in `providers/` plus a line in the registry. The prompt lives in `prompts/drug-interaction.md`, not in code — split into system and user by a `---USER---` line, with `{{placeholders}}`, cached only in production so prompt edits need no restart in dev.

**Every failure mode collapses into one `AiUnavailableError`** — unconfigured, unknown `AI_PROVIDER`, missing key, network error, timeout, unparseable output. The caller catches one thing and **fails open**: the curated table's results stand, the response is flagged `ai_available: false`, and the save proceeds. A clinic is never blocked on an LLM outage. The model is also constrained after the fact: it may only name the drug pair, a pair naming a drug absent from both lists is dropped, and the table's severity beats the model's.

### 3.13 Data model

`prisma/schema.prisma`, three clusters:

**Identity and organisation**

- `User` — `firebase_uid` (unique), nullable unique `phone` and `email`, `role`, `status`, optional `clinic_id`. Optional 1:1 `Patient` and `Doctor` profiles.
- `Clinic` — name, location, contact, coordinates.
- `Doctor` — `clinic_id`, name, specialization, nullable unique phone/email, `registration_number`, `registration_council`, `verified_at`, `verified_by_id`.
- `StaffInvite` — clinic, role, email or phone, name, specialization, `invited_by_id` (nullable, for the legacy backfill), `accepted_user_id`, `expires_at`.

**Clinical**

- `Patient` — `health_id` (`MWH-XXXXXX`, unique), name, unique phone, dob, gender, `language_pref`, `registered_by_user_id` (plain UUID, no FK, so removing a staff user never blocks), `claim_failures`, `claim_locked_until`.
- `Appointment` — patient, doctor, clinic, `slot_time`, status (`pending`/`confirmed`/`completed`/`cancelled`).
- `MedicalRecord` — patient, doctor, optional appointment, `visit_date`, diagnosis, notes → `Prescription[]` (`medicine_name`, `dosage`, `duration`).
- `DrugInteraction` — curated reference pairs with severity and mechanism.
- `InteractionCheck` — `checked_drugs` and `conflicts` as JSON, `ai_available`, `overridden`, `override_reason`, `record_id`.

**Consent and audit**

- `ConsentRequest` — patient, doctor, clinic, `method` (`APP`/`CODE`/`EMERGENCY`), `status` (`PENDING`/`APPROVED`/`DENIED`/`EXPIRED`/`REVOKED`), `reason`, `code_hash`, `attempts`, `expires_at`, `granted_until`, `responded_at`. Indexed on `(patient_id, doctor_id, status)`.
- `PatientAccessLog` — patient, `user_id` (**nullable FK with SET NULL, so audit rows outlive a deleted user**), `clinic_id` (the reader's clinic at the time), `via`, `consent_id`, `appointment_id`, `action`. Indexed on `patient_id`.

Enums (`Role`, `UserStatus`, `AppointmentStatus`, `ConsentMethod`, `ConsentStatus`, `AccessVia`, `InteractionSeverity`) push a large share of validation into the database.

**Prisma 7 specifics:** the client is a module singleton over a `pg` `Pool` through the `PrismaPg` driver adapter (`config/prisma.js`), and the datasource URL lives in `prisma.config.ts`, **not** in `schema.prisma`. `config/db.js` is an unused raw pool — ignore it.

Migrations are one per feature phase, applied with `npx prisma migrate deploy`:
`init_schema`, `add_drug_interactions`, `add_history_indexes`, `add_roles_status`, `add_staff_onboarding`, `add_patient_registered_by`, `add_consent`.

### 3.14 Endpoint map

Every router does `router.use(authenticate)` once at the top, then gates per route. Literal paths are declared **before** `/:id` so `/interaction-check`, `/lookup` and `/pending` are not swallowed by the wildcard.

| Method & path | Permission | Notes |
|---|---|---|
| `GET /api/health` | — | unauthenticated; never touches the DB |
| `POST /api/patients` | signed in | self-registration; phone from the token only |
| `POST /api/patients/register` | `patient:register` | desk registration; duplicate phone → 409 + health ID |
| `POST /api/patients/claim` | signed in | DOB claim; 5 failures → 423 for 24 h |
| `GET /api/patients/me` | signed in | profile, or 404 + `next`; accepts invites |
| `GET /api/patients/search` | `patient:lookup` | name search limited to the caller's clinic |
| `GET /api/patients/lookup` | `patient:lookup` | exact health ID or phone; phone masked; returns `access {allowed, via}` |
| `GET\|PUT /api/patients/:id` | `authorizePatientAccess` | demographics |
| `POST /api/appointments` | `self:profile` or `appointment:manage` | patient booking (pending) or staff walk-in (confirmed) |
| `GET /api/appointments/me` | `self:profile` | |
| `GET /api/appointments` | `appointment:manage` | clinic queue, scoped |
| `PUT /api/appointments/:id` | either | reschedule |
| `PATCH /api/appointments/:id/cancel` | either | |
| `PATCH /api/appointments/:id/confirm` | `appointment:manage` | pending → confirmed |
| `POST /api/records` | `record:write` + patient access | `check_id` / `override_reason` audit wiring |
| `POST /api/records/interaction-check` | `interaction:check` + patient access | |
| `GET /api/records/patient/:patientId` | `self:profile` or `record:read` + patient access | cross-clinic history |
| `GET /api/records/:id` | `self:profile` or `record:read` + patient access | |
| `POST /api/records/:id/upload` | `report:upload` + patient access | gate runs **before** multer |
| `POST /api/staff/applications` | verified email, no row | → DOCTOR PENDING |
| `POST\|GET /api/staff/invites` | `staff:manage` | clinic-scoped for CLINIC_ADMIN |
| `GET /api/staff` | `staff:manage` | `?status=` |
| `POST /api/staff/:userId/approve\|reject\|disable` | `staff:manage` | |
| `POST /api/consents` | `consent:request` | 3/hour cap |
| `GET /api/consents/:id` | `consent:request` | doctor polls at 3 s |
| `POST /api/consents/redeem` | `consent:request` | `{patient_id, code}` |
| `POST /api/consents/emergency` | `consent:emergency` | reason ≥ 20 chars |
| `GET /api/consents/pending` | `consent:respond` | patient polls at 10 s |
| `POST /api/consents/:id/respond` | `consent:respond` | allow / deny |
| `POST /api/consents/share-code` | `consent:respond` | |
| `GET /api/consents/mine` | `consent:respond` | active grants |
| `POST /api/consents/:id/revoke` | `consent:respond` | |
| `GET /api/audit/access` | `audit:read` | `?clinic_id=`, scoped |
| `GET\|POST /api/clinics`, `GET\|PUT /api/clinics/:id` | reads open; `clinic:create` / `clinic:update` | |
| `GET\|POST /api/doctors`, `GET\|PUT /api/doctors/:id` | reads open; `staff:manage` | list hides non-ACTIVE doctors |

### 3.15 Cross-cutting concerns

- **Errors** — controllers throw or `next(err)` with a `statusCode`; `middleware/errorHandler.js` is the single exit, exposing stack traces only outside production.
- **Response envelopes** — two shapes are in use: controllers answer `{success, data}` / `{success, error, message}`, while the error handler answers `{status, statusCode, message}`. Worth unifying.
- **Uploads** — `multer` to `uploads/reports/`, 5 MB cap, PDF/PNG/JPG/JPEG/WEBP only, randomized `report-<timestamp>-<random>` filenames. Stored as a relative `report_file_url`, which the app resolves against `API_BASE_URL`.
- **Health ID** — `utils/healthId.js` generates `MWH-XXXXXX` from crypto-random bytes over an alphabet that excludes `0/O/1/I`, and collision-checks against the DB.
- **Phone normalisation** — `utils/phone.js` `toE164()` runs on **every** phone before it is stored or matched, with a `+91` default for bare 10-digit numbers. Uniform normalisation is what allowed the old last-10-digits matching hole to be removed.
- **Singletons** — `config/prisma.js` and `config/firebase.js` initialise once at module load.

### 3.16 Testing

No test framework. Two runnable Node scripts that drive the **real** HTTP stack:

| Script | Covers | Count |
|---|---|---|
| `scripts/test-auth-rbac.js` | identity, RBAC matrix, staff onboarding, patient claim, front desk, consent and audit | 302 assertions |
| `scripts/test-interactions.js` | the drug interaction detector, Phases 1–4 including a fake in-process AI provider | 112 assertions |

Both stub `config/firebase.js` in `require.cache` with an `auth.verifyIdToken` that base64-decodes a fake token, so the real `authenticate → requirePermission → controller → errorHandler` stack runs untouched with no credentials and no device. Fixtures clean themselves up. The RBAC matrix is generated from `config/permissions.js`, and asserts on the gate's own 403 message so a controller-level 403 cannot mask a loosened gate.

Also: `scripts/test-ai-provider.js` smoke-tests whichever provider `.env` configures, and `postman/` holds the full collection and environment.

### 3.17 Deployment and operations

- **Image** — `node:22-slim` (glibc, for Prisma's query engine), OpenSSL installed, dependency layer cached, `prisma generate` at build time with a placeholder `DATABASE_URL`, non-root `node` user, `PORT` defaulting to 3000.
- **Local database** — `backend/docker-compose.yml` defines `migrant-clinic-db` (postgres:16, :5432, volume `migrant_clinic_pgdata`), reading `POSTGRES_PASSWORD` from `backend/.env`.
- **CI** — `.github/workflows/build-apk.yml` builds an Android APK on every push to `main` touching `mobile_app/**`. The backend image workflow is the file `.github/workflows/deploy-container` — **no `.yml` extension, so GitHub Actions has never run it**. Nothing auto-deploys.
- **Secrets** — `backend/.env` and `backend/config/firebase-adminsdk.json`, both gitignored and dockerignored. Never commit, print or publish them.

---

## 4. Integrations

| Integration | How it is wired | Failure behaviour |
|---|---|---|
| **Firebase Auth** | Client SDK signs in (phone OTP, Google, email/password, anonymous in debug). Backend verifies ID tokens with `firebase-admin`; `config/firebase.js` loads a service-account key file and falls back to Application Default Credentials if it is missing. | Invalid/expired token → 401. **The ADC fallback will fail on AWS** — the key must be injected as `FIREBASE_SERVICE_ACCOUNT_JSON`. |
| **PostgreSQL** | Prisma 7 client over a `pg` Pool via the `PrismaPg` driver adapter; `DATABASE_URL` from `.env`, configured in `prisma.config.ts`. | A DB error inside `authenticate` is a 500, deliberately not a 401. `/api/health` never touches the DB, so a stopped database only shows up at login. |
| **LLM provider** | `AI_PROVIDER` selects `openai-compatible` / `bedrock` / `sagemaker`; `AI_*` env vars supply URL, key and model. Prompt from `prompts/drug-interaction.md`. | **Fails open.** Any error → `ai_available: false`, curated table results stand, the save proceeds. |
| **File storage** | `multer` to local disk, served by `express.static` at `/uploads`. | Planned move to private S3 with presigned URLs (`AWS_MIGRATION_PLAN.md`). |
| **Google Sign-In** | Firebase provider; `signInWithPopup` on web, `signInWithProvider` on mobile. Needs an OAuth client, enabled in the Firebase console, and the Android SHA-1/SHA-256 registered. | CI-built APKs are signed with each runner's throwaway debug keystore, so Google sign-in fails on them until a fixed keystore is used. |
| **Geolocation** | `geolocator` in the app, for nearest-clinic sorting. Clinic coordinates live on the `Clinic` row. | Falls back to unsorted list. |
| **Docker / GHCR** | `backend/Dockerfile`; `scripts/push-docker-ghcr.ps1` for a manual push. | — |
| **Postman** | `backend/postman/` collection + environment, kept in step with each phase. | — |

**Not integrated, despite the branding:** Google Cloud Storage was never implemented, there is no Cloud SQL connector, and nothing auto-deploys to Cloud Run. The code is plain Postgres over `DATABASE_URL` and local disk.

---

## 5. Frontend

### 5.1 Stack

| Concern | Choice |
|---|---|
| Framework | Flutter (Dart SDK ^3.12.2), targeting **Android and Web** |
| State | `flutter_riverpod` 2 |
| Routing | `go_router` 17, with a `ShellRoute` around every signed-in page |
| HTTP | `dio` 5, one shared client factory |
| Auth | `firebase_core` + `firebase_auth` 5 |
| Offline cache | `hive` + `hive_flutter` |
| Secure storage | `flutter_secure_storage` |
| i18n | `flutter_localizations` + `intl`, generated ARB localisations in **en / hi / ta** |
| Misc | `google_fonts`, `url_launcher`, `geolocator`, `flutter_native_splash`, `flutter_launcher_icons` |

### 5.2 Structure

```
lib/
  core/         constants (API_BASE_URL via --dart-define), errors, network, theme,
                utils (incl. poll.dart: visibility-aware polling)
  data/services/ one service per API area, each built with createApiClient()
  providers/    Riverpod providers: auth, appointments, records, admin, consent, doctor, locale
  presentation/ screens grouped by area (auth, dashboard, appointments, records,
                doctor, reception, admin, consent, profile, clinic shell) + shared widgets
  routes/       app_router.dart — the single GoRouter
  l10n/         generated localisations (en, hi, ta)
```

### 5.3 How it talks to the backend

`core/network/api_client.dart` exposes one `createApiClient()` factory: a `Dio` with the base URL, 10-second timeouts, and an interceptor that **swaps in a fresh Firebase ID token on every request**. Tokens expire after an hour, so capturing one at login is not enough — this was a real bug. If the refresh fails offline, the old token is sent and callers fall back to the cache. **Every service must be built with this factory**; a hand-rolled `Dio` will silently ship stale tokens.

`API_BASE_URL` comes from `--dart-define`, and `AppConstants.validateNetworkSecurity()` makes a **release** build throw at launch on a non-HTTPS endpoint — which is why local clinic-side testing uses `flutter build web --profile`.

### 5.4 Session and navigation

`AuthStatus` has 13 states, well beyond signed-in/out: `restoring`, `initial`, `otpSending`, `otpSent`, `verifying`, `authenticated`, `needsRegistration`, `needsPhoneLink`, `needsClaim`, `needsEmailVerification`, `needsStaffApplication`, `pendingApproval`, `error`.

`statusForProfile()` maps the `GET /patients/me` result (a profile, or `{next: ...}`) onto that enum, and **`AuthState.route` is the single place that says where a session belongs**. The login, OTP, verification, application and claim screens and the shell all navigate by it, so a browser reload on any deep URL with an unverified or pending account lands correctly.

`clinic_shell.dart` is a `ShellRoute` wrapping every signed-in route. It waits for session restore, redirects signed-out users to `/login`, and gates each staff page by **permission, not role** (`routePermissions`), filtering the navigation rail and dashboard tiles from the same map. Staff get a `NavigationRail` at ≥800 px. It also hosts `ConsentPopupHost` for anyone holding `consent:respond`, so the Allow/Deny dialog finds the patient on whatever screen they are on.

Routes: `/login`, `/verify-otp`, `/register`, `/link-phone`, `/claim`, `/verify-email`, `/staff-apply`, then inside the shell `/`, `/records`, `/records/:id`, `/appointments`, `/book-appointment`, `/profile`, `/privacy`, `/doctor/today-appointments`, `/doctor/add-record`, `/doctor/patients`, `/admin/staff`, `/admin/clinics`, `/admin/audit`.

### 5.5 Offline and live updates

`LocalCacheService` (Hive) stores the profile, records and appointments per patient, so the app opens and shows data without a network — an earlier build logged users out on a cold offline start. `CachedResult` carries whether data came from the network or the cache, and `OfflineBanner` surfaces it.

There is no push. Five things poll while their screen is open: the doctor's queue, the patient's appointments, the patient's records and pending consent requests at 10 seconds, and the doctor's own outstanding consent request at 3 seconds. All of them go through `core/utils/poll.dart` `schedulePoll(ref)` rather than a hand-rolled `Timer` + `invalidateSelf`, and it **stops the clock while the browser tab is hidden** (`appVisibleProvider`, an `AppLifecycleListener`), refreshing immediately on return — 5 minutes hidden costs 3 API calls instead of 33. A merely unfocused window still counts as visible; only `hidden`/`paused` pause it, and if lifecycle events never arrive it stays visible, i.e. the old behaviour.

This matters on the server side too: since Phase 8 put the consent popup host on every signed-in page, each tick costs a `verifyIdToken` plus a `users` lookup, and a records poll also pays the `requirePatientAccess` patient lookup. Push (FCM or websockets) is the real fix.

### 5.6 Testing

`flutter test` runs `clinic_shell_test.dart` (permission gating), `clinic_flow_test.dart` (the real router and screens against fake services with an in-memory Hive box), `poll_test.dart` (polling cadence under `fakeAsync`, since a widget test cannot prove it — `AppLifecycleState.hidden` stops the test binding pumping frames), `widget_test.dart`, and `interaction_contract_test.dart` — the only test that proves the Dart client and the Node API agree on field names; it skips unless a live backend token is passed, so CI stays green.

---

## 6. Known gaps

Ordered by how much they matter.

1. **`/uploads` is served with no authentication.** A medical report URL is public to anyone holding it, which bypasses the entire consent system. Closes with the S3 presigned-URL work in `AWS_MIGRATION_PLAN.md`.
2. **`cors()` is wide open** with no origin list — fine locally, wrong on a public domain.
3. **`PUT /patients/:id` lets any `patient:lookup` staff edit any patient's demographics**, not just their own clinic's.
4. **A receptionist could book a fake appointment to manufacture a care link.** It is visible in the access log; add review if it is abused.
5. **Two response envelopes** (controllers vs the error handler).
6. **No invite emails** — an admin has to pass the portal URL along by hand. Needs SES after the AWS move.
7. **Consent is polling, not push.** Move to FCM if 10 seconds is too slow or too costly.
8. **Registration numbers are verified by hand** — there is no council registry API.
9. **Staff-facing screens are English-only.** The patient-facing consent popup is the first thing worth translating.
10. **No multi-role users** (a clinic admin who is also a doctor) and **no staff MFA** (needs Firebase Identity Platform).
11. The backend deploy workflow is **missing its `.yml` extension**, so it has never run.
