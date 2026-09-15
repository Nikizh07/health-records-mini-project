# Plan: Registration, RBAC and patient consent

**Status (2026-09-15): Phases 1–3 done. Phases 4–6 built and tested; their click-throughs in a real browser are pending. Phases 7–8 not started.** Build one phase at a time. Each phase leaves the app working and ends with its tests passing and a dated note in `MEMORY.md`.

## Context

Today every account is a Firebase phone OTP login (or anonymous guest), and authorisation is a flat three-role check. What the code does now:

- **Identity holes**
  - `createPatient` falls back to a `phone` from the request **body** when the token has none.
  - Guests get real patient rows with the phone `guest-<uid>`.
  - `authenticate.js` defaults any unknown user to `PATIENT` and trusts a `decodedToken.role` claim.
- **Doctor onboarding**
  - An ADMIN pre-creates an unlinked `Doctor` row by phone.
  - `/patients/me` links it on first login by exact phone **or last 10 digits**.
  - `getAuthenticatedDoctorId` and `getAppointments` also match doctors by phone.
- **RBAC gaps**
  - There are no clinic-scoped roles, no receptionist and no clinic admin.
  - `authorizePatientAccess` and the record controllers let **any** DOCTOR/ADMIN read **any** patient's full history.
  - `/patients/search` fuzzy-searches every patient by name.
  - ADMIN can write medical records.
  - `createMedicalRecord` falls back to `prisma.doctor.findFirst()`, so an ADMIN's visit is saved under a random doctor.
- **No consent.** There is no audit of who viewed a patient's records.

**Decisions taken (2026-09-13):**
- Doctors are onboarded by invite **and** by self-apply with approval.
- Consent is needed only outside a care link, and there is an emergency override.
- The fallback for patients without the app is a share code.
- Guest login stays in debug builds only.
- Firebase stays the identity provider. We only enable more sign-in providers in the console.

## Phase overview

| # | Phase | Side | Depends on | Ships |
|---|---|---|---|---|
| 1 | Identity hardening | Backend + tiny app | none | Security fixes only, no new features |
| 2 | Roles and permission table | Backend + app shell | 1 | 5 roles, one permission table, app gates by permission |
| 3 | Staff onboarding API | Backend | 2 | Invites, doctor applications, approve/reject/disable |
| 4 | Staff sign-in and onboarding UI | App | 3 | Email/Google login, verification, apply/pending, Staff admin screen |
| 5 | Patient sign-in and desk registration | Backend + app | 2 | Google/email + phone link for patients, desk registration, DOB claim |
| 6 | Receptionist front desk | Backend + app | 3, 5 | Clinic queue, walk-ins with doctor picker |
| 7 | Consent API | Backend | 2 | Access resolver, consent endpoints, access log, lookup |
| 8 | Consent UI | App | 7 | Doctor consent gate, patient popup, share code, privacy screen, audit list |

Phases 5 and 7 only need Phase 2, so they can run in parallel with 3–4.

---

# Design reference

Every phase points back to these sections.

## A. Identity

| Actor | Sign-in methods | Required before a DB profile |
|---|---|---|
| Patient | Phone OTP (primary), Google, email + password | A **verified phone** on the Firebase user. Google/email users link a phone with OTP |
| Staff (doctor, receptionist, clinic admin, admin) | Email + password, Google. Phone OTP stays allowed for the existing test doctor | `email_verified == true`, or a verified phone matching the invite |
| Guest | Anonymous | `kDebugMode` only in the app; the backend refuses it when `NODE_ENV=production` |

- **The DB is the only source of truth for role.** A user with no DB row has `role: null` and no permissions.
- **Every phone goes through `toE164()`** before it is stored or matched.

## B. Roles and permissions

**Roles:** `PATIENT`, `RECEPTIONIST`, `DOCTOR`, `CLINIC_ADMIN` (one clinic), `ADMIN` (platform). One role per user.

Two layers, both enforced on the server:
1. **Permission**: can this role do this action? One table in `backend/config/permissions.js`, sent to the app in `/me`.
2. **Scope**: is this resource yours? Checked in controllers: staff are limited to `req.user.clinic_id`, patients to themselves, and patient history goes through the access resolver (§D).

| Permission | PAT | RECEP | DOC | CLINIC_ADMIN | ADMIN |
|---|:-:|:-:|:-:|:-:|:-:|
| `self:profile` (own profile, own records, own appointments) | ✓ | | | | |
| `consent:respond` (approve/deny, share code, revoke, own access log) | ✓ | | | | |
| `patient:register` (register a walk-in patient) | | ✓ | ✓ | ✓ | |
| `patient:lookup` (exact health ID/phone → demographics; name search limited to own-clinic patients) | | ✓ | ✓ | ✓ | |
| `appointment:manage` (clinic queue, walk-in, confirm/reschedule/cancel) | | ✓ | own | ✓ | |
| `record:read` (history, subject to care link or consent) | | | ✓ | | |
| `record:write`, `interaction:check`, `report:upload` | | | ✓ | | |
| `consent:request`, `consent:emergency` | | | ✓ | | |
| `staff:manage` (invite, approve/reject applications, disable) | | | | own clinic | all |
| `clinic:update` | | | | own clinic | all |
| `clinic:create` | | | | | ✓ |
| `audit:read` (consent and access log) | | | | own clinic | all |

**Separation of duties:** receptionists and admins see demographics and appointments, **never** records or prescriptions.

**Bootstrap:** `scripts/set-user-role.js` still creates the first ADMIN. The ADMIN creates a clinic and invites its CLINIC_ADMIN.

## C. Registration flows

- **Patient, self:** sign in (phone OTP, or Google/email then a phone-link OTP) → `/me` returns `next: 'REGISTER'` → registration form → `POST /patients`. The phone comes only from the token.
- **Patient, at the desk:**
  - Staff register them with a phone and no account (`user_id = null`).
  - When the patient later signs in with OTP on that phone, `/me` returns `next: 'CLAIM'` and asks for the date of birth.
  - The DOB check stops a mistyped phone from handing someone's history to whoever owns that number.
- **Staff, invite:**
  - An admin creates a `StaffInvite` (role, email or phone, clinic; expires in 14 days).
  - On the invitee's first `/me`, the invite is accepted **only if** the matching identifier is verified.
  - For DOCTOR, an existing unlinked `Doctor` with the same phone or email is linked, so its appointments are kept.
  - No email is sent: the admin tells the person to sign in at the portal URL.
- **Doctor, self-apply:**
  - Verified email or Google → `next: 'STAFF_APPLY'` → application with clinic and registration number → `User` DOCTOR **PENDING**.
  - The clinic admin checks the council register by hand and approves or rejects.
  - Pending doctors are hidden from booking.
- **Disable:** a disabled user gets 403 on every call, even with a valid Firebase token.

## D. Patient access and consent

`resolveAccess(user, patientId)` → `{ allowed, via: SELF|CARE|CONSENT|EMERGENCY }`:
- **SELF**: the patient themselves.
- **CARE**: the doctor wrote a record for this patient, or there is a non-cancelled appointment at the doctor's clinic within ±30 days. A walk-in booking creates a care link, which covers patients at the desk without the app.
- **CONSENT / EMERGENCY**: an `APPROVED` consent for this doctor with `granted_until > now`.

**Consent flows:**
1. **In-app popup**
   - The doctor requests access → `PENDING`, expires in 10 minutes, at most 3 requests per doctor and patient per hour.
   - The patient app polls every 10 s and shows "Dr. X, Clinic Y wants to see your medical history for 24 hours. Allow / Deny".
   - The doctor's screen polls every 3 s.
2. **Share code**
   - The patient generates a 6-digit code: valid 10 minutes, single use, stored hashed.
   - The doctor enters it → 24-hour grant. 5 wrong attempts invalidate the code.
3. **Emergency:** a reason of at least 20 characters → 4-hour grant, flagged in the clinic audit list and the patient's access history.
4. **Revoke:** the patient can end any grant.

Every allowed read of patient data writes a `PatientAccessLog` row.

---

# Phases

## Phase 1: Identity hardening ✅ done 2026-09-13

**Goal:** close the identity holes without changing any flow. The app works exactly as before for real users.

**Backend**
- New `backend/utils/phone.js`: `toE164(raw)` with a `+91` default, matching the app.
- `middleware/authenticate.js`:
  - Take the role from the DB only: drop the `decodedToken.role` fallback and the `'PATIENT'` default.
  - Attach `email_verified` and `sign_in_provider`.
  - Return 401 for `sign_in_provider=anonymous` when `NODE_ENV=production`.
- `middleware/requireRole.js`: no `'PATIENT'` default, so `role: null` gets 403.
- `controllers/patient.controller.js`:
  - `createPatient` uses only the token phone, except for a guest outside production.
  - `getMyProfile` doctor linking uses exact `toE164` match only; the last-10-digit match is removed.
- `controllers/record.controller.js`:
  - Remove the phone fallback in `getAuthenticatedDoctorId` (~line 91).
  - Remove the `prisma.doctor.findFirst()` fallback (~line 156). An ADMIN without a doctor must pass `doctor_id`, as walk-ins already require.
- `controllers/appointment.controller.js`: remove the phone `OR` in `getAppointments` (~line 339).

**App**
- `login_screen.dart`: show "Continue as guest" only `if (kDebugMode)`.

**Tests**
- New `backend/scripts/test-auth-rbac.js`, following `scripts/test-interactions.js`: Firebase stubbed in `require.cache`, fake token decoding to `{uid, phone_number, email, email_verified, firebase.sign_in_provider}`, real HTTP, self-cleaning fixtures.
- Cases:
  - A body phone is ignored.
  - Anonymous gets 401 in production and works in development.
  - An unknown user gets 403 on role-gated routes.
  - A doctor with the right last 10 digits but a different country code is not linked.
  - An ADMIN `POST /records` with no `doctor_id` gets 400, not a random doctor.
- `scripts/test-interactions.js` still passes 112/112.

**Done when:** both test scripts pass and the test doctor `+919999900001` still logs in and saves a visit.

## Phase 2: Roles and permission table ✅ done 2026-09-15

**Goal:** 5 roles, one permission table, and the app gating by permission. There are no new screens yet; ADMIN loses record access.

**Schema (migration `add_roles_status`)**
- `Role` += `RECEPTIONIST`, `CLINIC_ADMIN`. New enum `UserStatus { ACTIVE PENDING DISABLED }`.
- `User`: `phone` nullable (still unique); new `email String? @unique`, `status @default(ACTIVE)`, `clinic_id String?` → `Clinic`.
- `Doctor`: `phone` nullable (unique); new `email String? @unique`.

**Backend**
- New `backend/config/permissions.js`: the §B table plus `permissionsFor(role, status)`, which returns nothing unless the status is `ACTIVE`.
- New `middleware/requirePermission.js`. Replace every `requireRole(...)` in `routes/*.js` and the inline role check in `patient.routes.js` `/search`, then delete `requireRole.js`.
- `authenticate.js`: DISABLED → 403. Attach `status`, `clinic_id` (`doctor.clinic_id ?? user.clinic_id`) and `permissions`.
- `/patients/me` adds `permissions`, `status` and `clinic` to every role's payload.
- Clinic scope in controllers: doctor and clinic endpoints check `req.user.clinic_id` for `CLINIC_ADMIN`. `record:*` is DOCTOR only.
- `scripts/set-user-role.js`: accept an email as well as a phone, and all 5 roles.

**App**
- `providers/auth_provider.dart`: add `can(permission)`, reading `patientProfile['permissions']`.
- `clinic/clinic_shell.dart`: `canAccess` by permission, and navigation entries filtered by permission, not role.
- `test/clinic_shell_test.dart`: update to permissions.

**Tests**
- `test-auth-rbac.js`: a role × endpoint matrix **generated from `permissions.js`**, so the table and the tests can't drift.
- Also: ADMIN and RECEPTIONIST get 403 on `/records/*`, a DISABLED user gets 403, a PENDING user has no permissions.

**Done when:** the matrix passes, `flutter test` is green, and the doctor and admin portals still open with the right nav.

## Phase 3: Staff onboarding API ✅ done 2026-09-15

**Goal:** doctors and staff can be invited or apply, and admins can approve, reject and disable. API only.

**Schema (migration `add_staff_onboarding`)**
- New `StaffInvite { id, clinic_id, role, email?, phone?, name, specialization?, invited_by_id, accepted_user_id?, expires_at, created_at }`.
- `Doctor`: new `registration_number`, `registration_council`, `verified_at`, `verified_by_id`.
- Data SQL: insert a `StaffInvite` for every `Doctor` with `user_id IS NULL`.

**Backend**
- New `routes/staff.routes.js` + `controllers/staff.controller.js`, mounted in `routes/index.js`:
  - `POST /staff/invites`, `GET /staff/invites` (`staff:manage`, own clinic for CLINIC_ADMIN).
  - `POST /staff/applications` (signed-in user with no DB row and a verified email) → `User` DOCTOR PENDING + `Doctor`.
  - `GET /staff?status=` and `POST /staff/:userId/approve|reject|disable` (`staff:manage`).
- `getMyProfile`:
  - Before returning 404, accept a matching unexpired invite with a verified identifier. This replaces the old doctor phone linking and links an existing unlinked `Doctor`.
  - With no invite, return `next: 'REGISTER'` (phone login) or `next: 'STAFF_APPLY'` (email login). PENDING users get `status: 'PENDING'`.
- `POST /doctors` becomes a thin alias that creates a DOCTOR invite, so the current admin screen keeps working.
- `getAllDoctors` hides doctors whose user is not `ACTIVE`.

**Tests**
- An invite is accepted with a verified email and rejected with an unverified one.
- An expired invite is ignored.
- A legacy unlinked doctor is linked with its appointments intact.
- Application → PENDING → no permissions, hidden from booking → approve → ACTIVE.
- A CLINIC_ADMIN can't manage another clinic's staff.

**Done when:** the tests pass and the existing `POST /doctors` Postman request still works.

## Phase 4: Staff sign-in and onboarding UI 🟡 built 2026-09-15, user click-through pending

**Goal:** staff can sign in with email or Google, verify email, apply, see a pending screen, and admins manage staff in the app.

**Firebase console (the user does this):** enable Email/Password and Google, add the web origins to Authorized domains, and register the Android SHA-1.

**App**
- `data/services/auth_service.dart`: add `signInWithEmail`, `signUpWithEmail` (plus `sendEmailVerification`), `sendPasswordReset`, `signInWithGoogle` (`signInWithPopup` on web, `signInWithProvider` on mobile) and `reloadUser`. No new packages: `firebase_auth` 5 covers these.
- `providers/auth_provider.dart`: new statuses `needsEmailVerification`, `needsStaffApplication`, `pendingApproval`, driven by `/me` `next` and `status`.
- `login_screen.dart`: Patient / Clinic staff tabs, with the staff tab as the default on web. The staff tab has email, password, Google and "forgot password".
- New in `presentation/screens/auth/`:
  - `email_verification_screen.dart`: resend, and "I've verified" → reload.
  - `staff_application_screen.dart`: application form plus the awaiting-approval state.
- `admin/admin_screens.dart`: "Manage doctors" becomes "Staff": invite dialog, pending applications with the registration number and approve/reject, disable.
- New `data/services/staff_service.dart` (built with `createApiClient()`).
- Routes in `routes/app_router.dart`; strings in `l10n/app_en/hi/ta.arb`.

**Tests:** `clinic_flow_test.dart` cases for the staff tab, pending screen and Staff admin screen with fake services.

**Done when (the user clicks):**
1. The admin invites a doctor by email.
2. The doctor signs up and verifies the email, then lands on the doctor portal.
3. A second doctor self-applies and sees the pending screen.
4. The clinic admin approves, and the second doctor lands on the portal.

## Phase 5: Patient sign-in and desk registration 🟡 built 2026-09-15, user click-through pending

**Goal:** patients can use Google or email (with a linked phone), and staff can register a patient who is later claimed by DOB.

**Schema (migration `add_patient_registered_by`)**
- `Patient`: new `registered_by_user_id String?`.

**Backend**
- `POST /patients` with `patient:register` takes `{name, dob, gender, language_pref, phone}` and creates a `Patient` with `user_id = null`. A duplicate phone returns 409 with the existing health ID.
- `getMyProfile`: an unlinked patient with the same verified E.164 phone → `next: 'CLAIM'`.
- New `POST /patients/claim {dob}`: a match links the account; a mismatch gets 403. Lock the claim after 5 failures.

**App**
- `auth_service.dart`: add `startPhoneLink` / `confirmPhoneLink` (`linkWithPhoneNumber` on web; `verifyPhoneNumber` + `linkWithCredential` on mobile).
- `auth_provider.dart`: new statuses `needsPhoneLink` and `needsClaim`.
- Patient tab of `login_screen.dart`: add Google and email next to phone OTP. Reuse `otp_verification_screen.dart` for phone linking.
- New `auth/claim_profile_screen.dart` (DOB).

**Tests**
- Desk registration with no account.
- Duplicate phone gets 409.
- A wrong DOB is rejected; the right DOB links the account.
- A Google patient without a phone can't `POST /patients`.

**Done when:** a patient registered by staff signs in on their phone, enters their DOB, and sees their profile.

## Phase 6: Receptionist front desk 🟡 built 2026-09-15, user click-through pending

*As built:* the scoping below was already in place from Phase 2; the backend adds `PATCH /appointments/:id/confirm`. The app reuses the queue and patient lookup screens by permission instead of new routes (see `MEMORY.md`).

**Goal:** a receptionist runs the clinic queue and registers walk-ins, and never sees records.

**Backend**
- `appointment.controller.js`:
  - `appointment:manage` is scoped to `req.user.clinic_id` for RECEPTIONIST and CLINIC_ADMIN.
  - The queue lists all doctors at the clinic.
  - A walk-in requires a `doctor_id` from the same clinic.
  - Confirm/reschedule/cancel works for any appointment at the clinic.
- `routes/appointment.routes.js`: move to the permissions.

**App**
- New `presentation/screens/reception/reception_screens.dart`:
  - Clinic queue: reuse the `DoctorTodayAppointmentsScreen` cards and grid, with a doctor column.
  - Register-patient dialog (Phase 5 endpoint).
  - Walk-in with a doctor picker.
- `clinic_shell.dart`: receptionist navigation (Front desk, Patients).

**Tests**
- A receptionist books a walk-in at their own clinic and gets 403 for another clinic.
- A receptionist gets 403 on `/records/*`.
- Flutter: a receptionist flow in `clinic_flow_test.dart`.

**Done when:** a receptionist registers a walk-in, books them with a doctor, and the doctor sees them in the queue.

## Phase 7: Consent API

**Goal:** doctor reads of patient data require a care link, consent or emergency, and every read is logged.

**Schema (migration `add_consent`)**
- New `ConsentRequest { id, patient_id, doctor_id?, clinic_id?, method APP|CODE|EMERGENCY, status PENDING|APPROVED|DENIED|EXPIRED|REVOKED, reason?, code_hash?, attempts, expires_at, granted_until?, responded_at?, created_at }`, indexed on `(patient_id, doctor_id, status)`.
- New `PatientAccessLog { id, patient_id, user_id, via, consent_id?, appointment_id?, action, created_at }`, indexed on `patient_id`.

**Backend**
- New `backend/services/patientAccess.js`: `resolveAccess` (§D).
- New `middleware/requirePatientAccess.js`: runs the resolver, writes the log row, and returns 403 `{ code: 'CONSENT_REQUIRED' }` when denied. It replaces `authorizePatientAccess.js` and the role checks in `record.controller.js`, and applies to:
  - `GET /records/patient/:id`
  - `GET /records/:id`
  - `POST /records`
  - `POST /records/interaction-check`
  - `POST /records/:id/upload`
- `GET /patients/lookup?health_id=|phone=` (exact): demographics, a masked phone and `access: {allowed, via}`.
- `/patients/search`: limited to patients with an appointment at the caller's clinic.
- New `routes/consent.routes.js` + `controllers/consent.controller.js`:
  - `POST /consents` and `GET /consents/:id` (doctor).
  - `GET /consents/pending` and `POST /consents/:id/respond` (patient).
  - `POST /consents/share-code` (patient) and `POST /consents/redeem` (doctor).
  - `POST /consents/emergency` (doctor).
  - `GET /consents/mine` and `POST /consents/:id/revoke` (patient).
  - `GET /audit/access?clinic_id=` (`audit:read`).

**Tests**
- Request → approve → read; deny → 403.
- An expired request can't be approved.
- The 4th request in an hour → 429.
- Share-code redeem works; 5 bad attempts lock the code.
- Emergency without a reason → 400.
- A walk-in creates CARE access.
- A revoked grant → 403.
- Every allowed read writes a log row.
- `test-interactions.js`: add a fixture appointment so the doctor has a care link, then confirm 112/112.

**Done when:** the tests pass, and a doctor at another clinic gets `CONSENT_REQUIRED` over HTTP.

## Phase 8: Consent UI

**Goal:** doctors request access in the app, patients answer in a popup or share a code, and everyone can see the history.

**App**
- New `data/services/consent_service.dart` and `providers/consent_provider.dart`: a pending-request poll every 10 s using the existing `Timer` + `invalidateSelf` pattern.
- `doctor/doctor_screens.dart`:
  - `_PatientHistory` sits behind a new `_ConsentGate`: Request access (waiting state with a 3 s poll) / Enter share code / Emergency access (reason).
  - The visit form and interaction check handle the `CONSENT_REQUIRED` 403 the same way.
- `clinic/clinic_shell.dart`: for patients, host the consent popup listener (dialog closed with its own `dialogContext`; see the ShellRoute gotcha in `MEMORY.md`).
- New `presentation/screens/profile/privacy_screen.dart` (patient): share code, active grants with revoke, and access history.
- `admin/admin_screens.dart`: an audit list for `audit:read`, with emergency grants highlighted.
- Strings in `l10n`.

**Tests:** `clinic_flow_test.dart` cases for the consent gate states and the patient popup with fake services.

**Done when (the user clicks):**
1. A doctor at another clinic looks up the patient and requests access.
2. The popup appears on the patient's phone; the patient approves and the history loads.
3. The share-code path works.
4. The emergency path works and appears in the audit list and the patient's access history.

---

## Docs, per phase

- Add a dated note to `MEMORY.md` and update `SNAPSHOT.md` for new files.
- Add new endpoints to `backend/postman/`.
- Update `README.md` after Phases 4 and 8.

## Known gaps left out of scope

- `/uploads` is served without auth, so report files bypass consent until the S3 presigned-URL work in `AWS_MIGRATION_PLAN.md`.
- A receptionist could book a fake appointment to create a care link. It is visible in the access log; add review if it's abused.
- No invite emails: add SES after the AWS move.
- Registration numbers are checked by hand: there is no council registry API.
- Consent uses polling rather than push: move to FCM if the 10 s poll is too slow or too costly.
- Multi-role users (a clinic admin who is also a doctor) and staff MFA (needs Firebase Identity Platform) are not covered.
