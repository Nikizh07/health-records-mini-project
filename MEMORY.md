# Project Memory

Running context for this project: what it is, what's decided, and what's in progress.
**Keep this file current:** add decisions, status changes and gotchas as they happen, and date them.

## What this is
Cloud-based digital health record and appointment system for migrant worker clinics.
- **Backend** (`backend/`): Node.js 22, Express 4, Prisma 7 with the `@prisma/adapter-pg` driver adapter, PostgreSQL, Multer for uploads.
- **Mobile** (`mobile_app/`): Flutter, locales en / hi / ta. It talks only to the backend API (`API_BASE_URL` via `--dart-define`) and never touches the DB or storage directly.
- **Auth**: Firebase Auth on the client. The backend verifies Firebase ID tokens with `firebase-admin` (`middleware/authenticate.js`). Roles are PATIENT / RECEPTIONIST / DOCTOR / CLINIC_ADMIN / ADMIN; routes are gated by permission (`config/permissions.js` + `middleware/requirePermission.js`), since 2026-09-15.
- **Patients** get a health ID in the form `MWH-XXXXXX` (`utils/healthId.js`). Medical history is visible across clinics by design.

## Current infrastructure (as of 2026-09-12)
- Branded as GCP (Cloud Run / Cloud SQL / GCS), but the code is barely tied to GCP:
  - DB is plain Postgres via `DATABASE_URL`, with no Cloud SQL connector.
  - GCS was **never implemented**. Reports are saved to local disk (`backend/uploads/reports/`) and served from `/uploads`.
  - CI: `.github/workflows/build-apk.yml` builds an Android APK on every push to `main` touching `mobile_app/**`. The backend image workflow is the file `.github/workflows/deploy-container` — **no `.yml` extension, so Actions has never run it**. Nothing auto-deploys either way.

## In progress: AWS migration
- **Decision (2026-09-11):** move the DB → RDS Postgres, storage → private S3 with presigned URLs, and the backend → ECS Fargate. **Keep Firebase exactly as is.**
- Full plan: `AWS_MIGRATION_PLAN.md`.
- **Status: plan only. No code changes made yet.**

## In progress: AI cross-clinic medication conflict detector
- **Decision (2026-09-12):** warn a doctor at save time when a new prescription conflicts with a drug another clinic already started. Full plan: `thinking-archive/AI_DRUG_INTERACTION_PLAN.md`.
- Two knowledge sources: a seeded `drug_interactions` reference table (deterministic, always runs) **plus** an LLM leg.
- **The AI provider is pluggable, configured by env vars only** (2026-09-12). One adapter contract (`isConfigured()` + `complete({system,user})`) with three implementations: `openai-compatible` (plain `fetch`, no deps — covers OpenAI, Gemini's compat endpoint, Groq, OpenRouter, Ollama, vLLM, any custom URL), `bedrock`, and `sagemaker`. Adding a provider = one file + one registry line. AWS SDKs are `optionalDependencies`, lazily required.
- **The prompt lives in `backend/prompts/drug-interaction.md`, not in code** — `{{placeholders}}`, split into system/user by a `---USER---` line, cached only in production so prompt edits need no restart.
- Bedrock model ids are region-specific: get the exact id from `aws bedrock list-foundation-models --region ap-south-1 --by-provider meta`, never guess. SageMaker has no standard payload shape — the adapter targets HuggingFace TGI and the mapping is meant to be edited.
- **Fails open by design**: if the AI provider is unreachable the save still proceeds, flagged `ai_available: false`, and the curated table still fires. Never block a clinic on an LLM outage.
- Conflicts warn but don't block; the doctor must give an override reason, and every check is stored in `interaction_checks` for audit.
- **Status (2026-09-12): Phase 1 done** — schema (`drug_interactions`, `interaction_checks`, `InteractionSeverity`) + 2 migrations, `utils/drugName.js`, `utils/prescriptionWindow.js`, `services/interactionChecker.js`, `scripts/seed-drug-interactions.js` (56 curated pairs), and `POST /api/records/interaction-check`. Verified end to end against the local DB and over HTTP with a real doctor token; test rows cleaned up. Phases 2-4 followed; see the changelog (Phase 4 on 2026-09-13).
- Gotcha: `utils/drugName.js` `normaliseDrugName()` is the contract between the seeder and the checker. If one side changes how names are normalised and the other doesn't, lookups silently return nothing — there is no error.
- Gotcha: an unparseable `duration` makes a prescription count as active for 90 days (`ASSUMED_ACTIVE_DAYS`) and marks the conflict `confidence: "ASSUMED"`. Deliberate: a false warning is cheaper than a missed one.
- ~~Known gap: same-visit pairs don't fire~~ — closed 2026-09-12.

## Planned: registration, RBAC and patient consent
- **Plan (2026-09-13):** `AUTH_RBAC_CONSENT_PLAN.md`. **Status: Phases 1-3 done; Phases 4-6 built and tested (2026-09-15), user click-throughs pending; next is 7.**
- Split into 8 phases, one migration per phase (2026-09-13):
  1. identity hardening
  2. roles + permission table
  3. staff onboarding API
  4. staff sign-in UI
  5. patient sign-in + desk registration
  6. receptionist front desk
  7. consent API
  8. consent UI
- Phases 5 and 7 only need Phase 2. Start with Phase 1.
- Decisions:
  - Doctors join by clinic-admin invite **or** by self-applying with a registration number (PENDING until approved).
  - Consent is needed only outside a care link (an appointment at the doctor's clinic within ±30 days, or a record the doctor wrote), with an audited emergency override.
  - Patients without the app use a 6-digit share code.
  - Guest login stays in debug builds only.
- New roles `RECEPTIONIST` and `CLINIC_ADMIN`. A single permission table in `backend/config/permissions.js` is sent to the app via `/me`. Receptionists and admins never read records.
- Holes found in current code, fixed by the plan:
  - `createPatient` trusts a body `phone`.
  - Doctor linking matches the last 10 phone digits.
  - Any DOCTOR/ADMIN reads any patient's history.
  - `createMedicalRecord` falls back to `prisma.doctor.findFirst()` for an ADMIN.

## Known gotchas
- `backend/config/firebase.js` falls back to Google ADC when the key file is missing. That will fail on AWS, and the key is dockerignored, so it must be injected as the `FIREBASE_SERVICE_ACCOUNT_JSON` secret.
- `backend/config/db.js` is unused. `config/prisma.js` is the real DB client.
- `report_file_url` is a relative path (`/uploads/reports/...`). Since 2026-09-11 the app resolves it against `API_BASE_URL`. The backend serves `/uploads` **without auth** — medical files are public to anyone with the URL until the S3 move.
- All API services must build their client with `createApiClient()` (`mobile_app/lib/core/network/api_client.dart`). It swaps in a fresh Firebase ID token per request; tokens expire after 1 hour.
- The clinic side targets **Flutter web** for PC use. Linux/Windows desktop builds can't do Firebase phone auth. Release builds refuse a non-HTTPS `API_BASE_URL` (`AppConstants.validateNetworkSecurity`), so test locally with `flutter build web --profile` or `flutter run -d chrome`.
- The first ADMIN still has to be created with `backend/scripts/set-user-role.js <phone> ADMIN`. The account must have signed in once. Guest accounts are stored with the phone `guest-<uid>`.
- Since the `ShellRoute` (2026-09-11), `showDialog` puts dialogs on the **root** navigator, but `Navigator.of(screenContext)` resolves to the shell's nested one. Close dialogs with the builder's own context (`builder: (dialogContext) => … Navigator.of(dialogContext).pop()`) or with `Navigator.of(context, rootNavigator: true).pop()`. Otherwise the dialog stays open, as with the booking "Done" button and the reschedule loading dialog, which are now fixed.
- Screens should rely on `AppTheme` (buttons, inputs, cards, app bars) rather than per-widget `styleFrom` overrides.

## Changelog
- **2026-09-15: Auth/RBAC Phase 6 — receptionist front desk.**
  - **Backend was mostly done already**: Phase 2 had scoped `appointment:manage` (clinic-wide queue for RECEPTIONIST/CLINIC_ADMIN, walk-in doctor must be at the caller's clinic, reschedule/cancel scoped) and moved the routes to permissions. The only gap was that **no confirm action existed**, so new `PATCH /appointments/:id/confirm` (pending → confirmed, conditional `updateMany`, same `outsideStaffScope`). Postman `04. Appointment Module` request 6.
  - **No new routes or nav entries, unlike the plan.** The existing `/doctor/today-appointments` and `/doctor/patients` screens adapt by permission, so the receptionist nav is Queue + Patients:
    - Queue without `record:write` → "Clinic Queue": each card names the doctor and has Confirm (pending) / Cancel (with a confirm dialog) instead of Start consultation.
    - `/doctor/patients` is now gated by `patient:lookup` (was `record:read`). Without `record:read` the right side is `FrontDeskPatientPanel` (demographics + Walk-in with a doctor picker) and **no records call is made**. "Register patient" in the app bar for anyone with `patient:register` (doctors too) selects the new patient.
  - New `presentation/screens/reception/reception_screens.dart` holds those pieces (register dialog, patient panel, doctor picker, queue actions). `AppointmentService.createWalkIn` takes an optional `doctorId`; new `confirmAppointment`; new `PatientService.registerAtDesk`.
  - Dashboard header for receptionist/clinic admin now shows the clinic name instead of "Health ID: MWH-PENDING".
  - Tests: `test-auth-rbac.js` 221/221 (clinic queue across doctors, walk-in needs a doctor, doctor/clinic mismatch, doctor sees the walk-in, confirm scope for patient/other clinic/colleague, confirm twice → 400, reschedule/cancel, receptionist 403 on all five `/records` routes); `test-interactions.js` 112/112; `flutter test` 17 passed, 2 skipped (new receptionist flow); `flutter analyze` clean.
  - **Gotcha:** don't run `dart format` on `doctor_screens.dart`: the file isn't formatted, so it rewrites ~1300 lines. Format only new files.
  - **Gotcha:** the `migrant-clinic-db` container is still the old `docker run` one, so `docker compose up -d` fails on the name conflict; `docker start migrant-clinic-db` works.
  - Known gaps: the queue has no doctor filter; `/patients/search` still searches every patient for the front desk until Phase 7; user click-through pending (receptionist registers a walk-in, books a doctor, the doctor sees it).
- **2026-09-15: Auth/RBAC Phase 5 — patient sign-in and desk registration.**
  - Migration `20260915180000_add_patient_registered_by`: `patients` += `registered_by_user_id` (plain UUID, no FK, so removing a staff user never blocks), `claim_failures`, `claim_locked_until`.
  - **Desk registration is `POST /patients/register`, not `POST /patients` as the plan said**: the Phase 2 matrix test decides pass/fail from the permission gate's 403 message, so `patient:register` needs its own gated route. Body `{name, dob, gender, language_pref, phone}`; the phone goes through `toE164` (10 digits get +91). Duplicate phone → 409 with the existing patient in `data`.
  - `/patients/me` 404 now can say **`next: 'CLAIM'`**: the verified token phone matches a patient with `user_id = null`. Checked before REGISTER, in both 404 branches.
  - `POST /patients/claim {dob: YYYY-MM-DD}`: 403 with `attempts_left` on a wrong date. **5 wrong dates lock the claim for 24 hours (423)** rather than forever, since there is no unlock screen. The attempt is taken atomically (`updateMany … claim_failures < 5`) before comparing, so parallel guesses can't beat the limit (tested with 8 in parallel).
  - `POST /patients` now refuses a staff account (403) instead of giving it a patient profile.
  - App: the patient side has **Continue with Google** and **Use email and password** next to phone OTP. The choice is stored (`SecureStorageService.savePatientIntent`) because the backend can't tell a patient's Google account from a staff one: `/me` says STAFF_APPLY for both. A patient-side sign-in whose Firebase user has no phone goes to **`/link-phone`** (`LoginScreen(linkPhone: true)`), and the OTP links the phone (`linkWithPhoneNumber` on web, `linkWithCredential` on mobile) instead of signing in. Then `/me` says REGISTER or CLAIM.
  - Only staff email sign-ups get the verification email; patients need a verified phone, not email.
  - New `auth/claim_profile_screen.dart` (`/claim`). Linking a phone that already has its own Firebase account fails with "This number already has an account. Sign out and sign in with the phone number instead."
  - Tests: `test-auth-rbac.js` 201/201 (desk registration, 409, E.164, Google without phone refused, staff can't self-register, CLAIM, wrong/right DOB, twice → 409, lock, parallel guesses); `test-interactions.js` 112/112; `flutter test` 16 passed, 2 skipped. Postman: `03. Patient Module` requests 5 and 6.
  - **Gotcha:** `npx prisma migrate diff … | tee migration.sql` also captures npm's `npm notice` lines, so the deploy fails on line 1 and is recorded as failed. Fix with `prisma migrate resolve --rolled-back <name>` and deploy again.
  - Known gaps: no desk-registration screen until Phase 6 (API only). A mistyped desk phone blocks its real owner from self-registering (phone is unique); staff must correct it, and there is no edit-phone endpoint yet.
- **2026-09-15: Auth/RBAC Phase 4 — staff sign-in and onboarding UI.** App only; no backend change.
  - `auth_service.dart`: `signInWithEmail`, `signUpWithEmail` (sends the verification email), `sendEmailVerification`, `sendPasswordReset`, `signInWithGoogle` (popup on web, `signInWithProvider` on mobile), `reloadUser`. No new packages.
  - `PatientService.getMyProfile` now returns `{'next': ...}` on a 404 instead of null. `statusForProfile()` in `auth_provider.dart` maps it: `VERIFY_EMAIL` → `needsEmailVerification`, `STAFF_APPLY` → `needsStaffApplication`, a `PENDING` profile → `pendingApproval`. Only real profiles are cached.
  - **`AuthState.route` is the one place that says where a session belongs** (`/`, `/register`, `/verify-email`, `/staff-apply`). The login, OTP, verify and apply screens and `ClinicShell` all navigate by it, so a web reload on any shell URL with an unverified or pending account is redirected too (before, an unregistered restore landed on an empty dashboard).
  - Login: a Patient / Clinic staff segmented switch, staff by default on web (`kIsWeb`). Guest login shows only on the patient side.
  - New `auth/email_verification_screen.dart` (I've verified → `recheck()` reloads the Firebase user and re-reads `/me`) and `auth/staff_application_screen.dart` (form, then "Waiting for approval" with Check again).
  - `/admin/doctors` is now **`/admin/staff`** (`AdminStaffScreen`): Applications / Staff / Invites tabs, approve, reject and disable with a confirm, enable a disabled account (approve endpoint), and an invite dialog. The clinic picker shows only for a platform ADMIN; a CLINIC_ADMIN's invite goes to their own clinic by API default. The old doctor directory, `adminDoctorsProvider`, `AdminService.getAllDoctors/createDoctor` are deleted; `POST /doctors` stays for Postman.
  - **Strings are not in l10n**, although the plan said so: the login, admin and doctor screens they sit in are English-only today. Move them with the rest of the staff UI if Hindi/Tamil staff screens are ever wanted.
  - Tests: `flutter analyze` clean; `flutter test` 14 passed, 2 skipped. New cases: Staff screen (approve, disable with confirm, invites, invite dialog), staff-tab email sign-in → pending screen, unverified email redirected from `/admin/staff` to verification.
  - **Gotcha:** on PC a snackbar is shown by the shell's full-width Scaffold, so it covers the page's FAB for its 4 s (queued snackbars stack up). The widget test clears snackbars before tapping *Invite*.
  - Not done: the plan's four browser steps (invite → sign up → verify → portal; self-apply → pending → approve → portal).
  - **Firebase project config (2026-09-15, project `migrant-workers-89bb8`), checked and set through the API with the backend service account** (`google-auth-library` from `backend/node_modules`; Identity Toolkit admin v2 `projects/<id>/config`, Firebase Management `androidApps/<appId>/sha`):
    - Email/Password was **already enabled**. Authorized domains are `localhost` + the two Firebase domains (ports don't matter, so :5000/:5001 work).
    - Added the local debug keystore SHA-1 `20:5D:43:DD:…:5F:33` and SHA-256 to the Android app.
    - **Google cannot be enabled through the API**: `defaultSupportedIdpConfigs` needs an OAuth client ID + secret, which only the console creates. The user enabled it in the console on 2026-09-15.
    - **Gotcha:** the `config` GET response includes `signIn.hashConfig.signerKey` (the password-hash key). Filter to the fields you need; never dump the whole response.
    - **Gotcha:** CI APKs are signed with each runner's throwaway debug keystore, so Google sign-in fails on them until a fixed keystore (as a secret) is used and its SHA registered.
- **2026-09-15: Auth/RBAC Phase 3 — staff onboarding API.**
  - Migration `20260915120000_add_staff_onboarding`: new `staff_invites`; `doctors` += `registration_number`, `registration_council`, `verified_at`, `verified_by_id`. `invited_by_id` is nullable because the data SQL inserts an invite for every unlinked doctor with no inviter. **Those legacy invites last 90 days, not 14**, so no pre-created doctor is stranded. Locally that was 4 seeded doctors (Sarah Tan, Rajiv Menon, Li Wei, Ananya Sharma).
  - New `routes/staff.routes.js` + `controllers/staff.controller.js`: `POST/GET /staff/invites`, `POST /staff/applications`, `GET /staff?status=`, `POST /staff/:userId/approve|reject|disable`.
  - **Invites are the only way a staff account gets linked.** `/patients/me` runs `acceptInvite` when there is no users row: it takes the newest open invite matching the token phone or a **verified** email, creates the user with the invite role and clinic, and for a DOCTOR links an unlinked Doctor with the same phone/email (keeping its appointments) or creates one. The old phone linking is gone.
  - A 404 from `/patients/me` now carries `next`: `REGISTER` (phone/guest sign-in, or PATIENT without a patient row), `VERIFY_EMAIL` (email not verified; not in the plan, but applying and accepting both need it), `STAFF_APPLY` (verified email).
  - Invite rules: roles RECEPTIONIST/DOCTOR/CLINIC_ADMIN only (ADMIN stays the script). An identifier that already has a users row, or already has an open invite, gets 409. A CLINIC_ADMIN invite defaults to, and is limited to, their own clinic.
  - **`POST /doctors` creates the invite AND the unlinked Doctor row**, returning the doctor with `data.invite`. The plan said invite only, but the Postman collection saves `data.id` as `doctor_id` for later requests and the admin screen lists doctors, so both keep working.
  - Decisions: **reject deletes the pending user and Doctor row** (nothing to keep, since pending doctors can't be booked), so they can apply again. **Approve also re-enables a DISABLED account.** It sets `verified_at`/`verified_by_id` only on the first approval. Nobody can act on their own account; a CLINIC_ADMIN can't touch platform ADMINs or other clinics.
  - Pending/disabled doctors are hidden from `GET /doctors`, and `bookAppointment` also refuses them by id. Unlinked doctors (no user yet) stay bookable, as before.
  - Postman: new folder `06. Staff Onboarding`, env vars `applicant_token` and `staff_user_id`.
  - Tests: `test-auth-rbac.js` 177/177; mutation-checked (accepting an unverified email fails 2 tests). `test-interactions.js` 112/112; `flutter test` green.
  - Known gap: an invite for someone who already has an account (e.g. a patient) is refused with 409. There is no role change for existing accounts yet.
- **2026-09-15: Auth/RBAC Phase 2 — roles and permission table.**
  - Migration `20260915000000_add_roles_status`: `Role` += `RECEPTIONIST`, `CLINIC_ADMIN`; new `UserStatus` (ACTIVE/PENDING/DISABLED); `users.phone` nullable, new `users.email` (unique), `users.status`, `users.clinic_id`; `doctors.phone` nullable, new `doctors.email` (unique). Generated with `prisma migrate diff` because `migrate dev` refuses a non-interactive shell.
  - `config/permissions.js` is the §B table. `permissionsFor(role, status)` is empty unless ACTIVE. `outsideOwnClinic(user, clinicId)` is the shared clinic-scope check (ADMIN is exempt).
  - `requireRole.js` is deleted; every route uses `requirePermission(...)` (any-of). `authenticate` 403s DISABLED users on every route and attaches `status`, `clinic_id` (`doctor.clinic_id ?? user.clinic_id`) and `permissions`.
  - `/patients/me` (and the `POST /patients` response, which the app stores as the profile) include `permissions`, `status`, `clinic`. CLINIC_ADMIN/RECEPTIONIST get a staff payload instead of falling into the patient 404.
  - **ADMIN lost** record read/write, patient lookup/profile access and appointment management (the table gives it none). Its app nav is now Dashboard, Doctors, Clinics, Profile.
  - **Appointment scope was pulled forward from Phase 6** because the new roles hold `appointment:manage` and would otherwise see every appointment: a DOCTOR manages only their own schedule (a walk-in on a colleague's schedule is 403), other staff only their clinic (list, walk-in doctor, reschedule, cancel).
  - `/patients/search` is still unscoped for any `patient:lookup` holder (now including receptionists and clinic admins); Phase 7 limits it to the caller's clinic.
  - `scripts/set-user-role.js` takes a phone or email and all 5 roles; `CLINIC_ADMIN`/`RECEPTIONIST` need a `clinic_id` arg. With no users row it creates one from the Firebase account (needs the service-account key).
  - App: `AuthState.can(permission)`; `ClinicShell.routePermissions` maps each staff page to its API permission, nav and dashboard tiles are filtered by it, and an unknown `/doctor/*` or `/admin/*` page is closed.
  - Tests: `test-auth-rbac.js` 131/131, with the role × endpoint matrix generated from `permissions.js`. It also fails if a permission has neither an endpoint nor a `LATER` entry.
  - **Gotcha:** the matrix must check the gate's own 403 message (`Requires permission`). A controller can also 403 (e.g. "No doctor profile"), which hid a deliberately loosened gate until the check was added. `test-interactions.js` 112/112.
- **2026-09-13: Auth/RBAC Phase 1 — identity hardening.** No new features; the holes are closed.
  - `middleware/authenticate.js`: the role comes **only** from the `users` row. A signed-in Firebase user with no row has `role: null` and gets 403 on every role-gated route (they used to count as PATIENT, and a `role` claim in the token was trusted). `req.user.phone_number` is now the verified token phone only, with no DB fallback. It also attaches `email_verified` and `sign_in_provider`.
  - Anonymous tokens get 401 when `NODE_ENV=production`.
  - **A DB error in `authenticate` is now a 500, not a 401.** The app ends the session on 401/403, so a DB outage used to log everyone out.
  - New `utils/phone.js` `toE164()`: a bare 10-digit number gets +91; anything else needs its country code.
    - `createPatient` takes the phone only from the token; the body `phone` is ignored.
    - Doctor linking in `/patients/me` is an exact E.164 match (the last-10-digit match is gone).
    - `POST/PUT /doctors` store E.164 and refuse numbers without a country code.
  - Phone-based identity fallbacks removed: `getAuthenticatedDoctorId`, `getAuthenticatedPatientId`, and the phone `OR` in `getAppointments`.
  - `createMedicalRecord`: the `doctor.findFirst()` fallback is gone.
    - A **DOCTOR always saves under their own profile**: a different body `doctor_id` gets 403. This was not in the plan but is the same hole.
    - An ADMIN must name the doctor (body `doctor_id` or the appointment's doctor).
  - `getAppointments`: a DOCTOR with no linked profile gets 403. Before, they got **every** appointment unfiltered (not in the plan, found while tracing).
  - App: "Continue as guest" is shown only when `!kReleaseMode`. This deviates from the plan's `kDebugMode`, so the `web-doctor` **profile** build keeps it for local testing.
  - Tests: new `scripts/test-auth-rbac.js`, 35/35. Against the pre-Phase-1 code, 13 of them fail, including an **unregistered user being able to write medical records**. `test-interactions.js` 112/112; `flutter analyze` clean; `flutter test` 12 passed, 2 skipped.
  - Not yet done: a manual click-through by the user (test doctor `+919999900001` logs in and saves a visit; guest patient flow on :5000).
- **2026-09-13: Root docs tidied into `thinking-archive/`.**
  - Moved there: the stale Firebase/guest setup notes (`START_HERE`, `QUICK_START`, `SUMMARY`, `*FIREBASE*`, `ENABLE_ANONYMOUS_AUTH`, `GUEST_LOGIN_SETUP`, `check-firebase-config.sh`), `DEVLOG.md`, `doctor-creds.txt` and the built `AI_DRUG_INTERACTION_PLAN.md`.
  - The root keeps `README`, `CLAUDE`, `MEMORY`, `SNAPSHOT` and the two open plans (AWS, auth/RBAC).
  - References in code comments, `README`, `AWS_MIGRATION_PLAN.md` and this file point at the new path.
- **2026-09-13: Drug interaction Phase 4 — the AI leg is built.** `backend/services/ai/` (registry + three adapters), `backend/prompts/drug-interaction.md`, `scripts/test-ai-provider.js`. The AI leg runs only when `AI_*` is set in `backend/.env`. The local `.env` has none, so the running app still behaves table-only.
  - **The model names only the pair.** Clinic, date, scope and confidence come from the patient's records. A pair naming a drug that isn't in either list is dropped, and table severity beats the model's.
  - **Any AI failure is a fail-open** (`ai_available: false`, table results stand): timeouts, HTTP errors, unparseable output, an unknown `AI_PROVIDER` or a missing key.
  - `scripts/test-interactions.js` now forces `AI_ENABLED=false` for Phases 1-3 and tests Phase 4 against an in-process fake provider: 112/112.
  - **Not done: no real model has been called** (no Ollama or key on this machine). Next: `node scripts/test-ai-provider.js` against a real provider, then the Brufen check through the API.
  - **Gotcha:** the Bedrock SDK speaks HTTP/2, so a fake HTTP/1 endpoint gives "Protocol error". Use an h2c server with `AWS_ENDPOINT_URL`. The SageMaker SDK is fine on HTTP/1.
  - **Gotcha:** HuggingFace TGI rejects `temperature: 0`; the SageMaker adapter sends `do_sample: false` instead.
- **2026-09-13: Drug interaction Phase 3 — the doctor can finally see it.** The visit form runs the pre-flight check and sends `check_id`, so Phases 1-2 stop being dead code.
  - `record_service.dart`: new `checkDrugInteractions()`; `createMedicalRecord` takes `checkId` / `overrideReason`.
  - `doctor_screens.dart`: `_InteractionBanner` + `_ConflictTile` above the save button, a reason field, and the button turning red and relabelling to **Save Anyway**. The banner branches on `scope` — a `SAME_VISIT` conflict reads "Both drugs are in this prescription" instead of naming a clinic.
  - **A clean check saves in one press** (the plan said always stop after the check). Conflicts stop the save; nothing found falls straight through, still sending `check_id` so the audit row is linked.
  - **The "AI check unavailable" note only appears alongside the banner.** `ai_available` is false on every response until Phase 4, so a standalone note would be permanent noise. With nothing found the screen makes no claim at all rather than a green all-clear it cannot back.
  - **An unreachable check warns once, then lets the next press save without it** — a clinic on a flaky connection must still be able to record the visit.
  - Editing any prescription field clears the stored verdict (`onChanged` on all three inputs plus add/remove), so an edited drug list is re-checked rather than saved against a stale warning.
  - `flutter analyze` clean; `flutter test` 12 passed, 2 skipped.
  - **Gotcha:** the visit form scrolls, so `tester.tap()` on the save button misses on the 800px test view — call `tester.ensureVisible(button)` first. The old Ctrl+Enter test never hit this because a key event needs no hit test.
  - New `test/interaction_contract_test.dart` — the only test that proves the Dart client and the Node API agree on field names (everything else uses a fake). Needs `HttpOverrides.global = null`, and skips unless `TEST_ID_TOKEN` / `TEST_PATIENT_ID` are passed, so CI stays green. Verified for real against the backend.
  - Browser walkthrough done by the user (2026-09-13): the banner shows in the `web-doctor` build, and the check row was stored (warfarin vs ibuprofen, CRITICAL, `EXISTING`).
  - **Gotcha:** a tab loaded before `flutter build web --profile` keeps running the old JS, so it saves with no check call and no error. Hard-reload after every rebuild. The tell is a `POST /api/records` in the backend log with no `POST /api/records/interaction-check` before it.
  - Test data left behind: patient `nihha` has an unchecked warfarin + ibuprofen record from 2026-09-13, saved by a stale tab.
- **2026-09-12: Same-visit drug conflicts now fire.** `findTableConflicts` (`backend/services/interactionChecker.js`) checks pairs *within* the new prescription list as well as new-vs-active.
  - The gap: the function returned early when the patient had no active medications — exactly the case where a same-visit pair is the only thing that can fire. Warfarin + ibuprofen written together in one visit produced a clean result on a CRITICAL interaction.
  - Fixed **before** Phase 3 on purpose: a same-visit conflict has no source clinic or date, so the conflict object the banner renders changes shape. Building the banner first would have meant rebuilding it.
  - Conflicts now carry **`scope`**: `'EXISTING'` (names `clinic_name` + `prescribed_on`) or `'SAME_VISIT'` (**both `null`**, `confidence: 'CERTAIN'`). **Phase 3's banner must branch on this** or it will render a null clinic.
  - Dedupe moved from a directional key to the ordered pair, so an interaction is reported once however it is reached. The existing leg runs first, so where both legs hit the same pair the richer `EXISTING` conflict wins and the clinic is never lost.
  - Phase 2 needed no change — a same-visit conflict demands an `override_reason` through the same path.
  - New `backend/scripts/test-interactions.js`: 80 assertions over real HTTP, Firebase stubbed in `require.cache`, self-cleaning fixtures. Run it with `DATABASE_URL=... node scripts/test-interactions.js`.
- **2026-09-12: Drug interaction Phase 2 — audit wiring.** `createMedicalRecord` now accepts optional `check_id` and `override_reason` (`backend/controllers/record.controller.js`).
  - With a `check_id`, the conflicts are re-read from the stored `interaction_checks` row, never from the request body. If that row recorded conflicts, a non-empty `override_reason` is required or the save is refused with 400.
  - After the record is written, the check row is linked back: `record_id`, `overridden`, `override_reason`.
  - `overridden` is true **only when conflicts were actually found** — a clean check saves with no reason and stores `overridden = false`, so the audit trail never claims a warning was dismissed when none was shown.
  - A check row is **single-use**: reusing one that already has a `record_id` is a 400. Not in the plan; added so the audit trail can say which save the doctor was warned about.
  - Omitting `check_id` leaves the endpoint behaving exactly as before, so the current app build and the Postman collection keep working until Phase 3 lands.
  - Verified with 25 assertions driving the controller directly, then re-verified over **real HTTP** (65 assertions total across Phases 1+2, all passing, fixtures cleaned up).
  - **How to test the API without Firebase or a device:** stub `config/firebase.js` in `require.cache` before requiring `server.js`, with an `auth.verifyIdToken` that base64-decodes a fake token into `{ uid }`. The real `authenticate` → `requireRole` → controller → `errorHandler` stack then runs untouched, and role gates behave correctly (PATIENT gets 403 on the doctor-only routes). No repo changes, no credentials.
  - Local DB for testing when Docker is unavailable: PostgreSQL 16 is installed in the image; `initdb` + `pg_ctl` as the `postgres` user under `/var/lib/postgresql/` works (it refuses to run as root, and a scratchpad path fails on directory traversal permissions). Point at it with a `DATABASE_URL` env var — `dotenv` does not override an already-set variable, so `.env` stays untouched.
  - Confirmed still true: the **same-visit gap** is real — warfarin and ibuprofen prescribed *together in one visit* are not flagged; only new-vs-already-active pairs fire.
  - Next: Phase 3 (Flutter banner + override UI), then Phase 4 (the AI layer).
- **2026-09-11: APK build pipeline.** `.github/workflows/build-apk.yml` builds an installable Android APK on every push to `main` that touches `mobile_app/**` (plus manual `workflow_dispatch`).
  - Two jobs: `test` (`flutter analyze` + `flutter test`) and `build`. They run in parallel, so a failing test is visible but never blocks the APK.
  - The build mode is chosen from the API URL, because `AppConstants.validateNetworkSecurity()` makes a release build throw at launch on a non-HTTPS endpoint:
    - no `API_BASE_URL` repository variable (today's state) → **debug** APK against `http://localhost:3000/api`, usable with `adb reverse tcp:3000 tcp:3000`;
    - `API_BASE_URL` set to an `https://…` URL (after the AWS move) → **release** APK against it, automatically.
    - `workflow_dispatch` can override the URL and force `debug`/`release`; forcing release without HTTPS fails with an explicit message.
  - Output: artifact `apk-<mode>-<run number>`, file `migrant-health-<mode>-v<version>-<run>-<sha>.apk`, kept 30 days. `versionCode` is the run number, so each build is distinct.
  - No secrets needed: the Android build has no `google-services` Gradle plugin, so Firebase comes from `lib/firebase_options.dart` and `google-services.json` is not read by the build (it is tracked in git, not gitignored; checked 2026-09-15, so a re-downloaded copy from the console need not replace it). Release still signs with the debug keystore (`android/app/build.gradle.kts`) — fine for sideloading, not for Play.
  - **Gotcha found:** the existing backend workflow is `.github/workflows/deploy-container` with **no `.yml` extension**, so GitHub Actions has never run it. Left as is — rename it to `deploy-container.yml` to turn it on.
- **2026-09-11: Walk-in (on-the-spot) appointments.**
  - `POST /api/appointments` is now open to DOCTOR/ADMIN as well. For staff callers it takes `patient_id` from the body. The doctor defaults to the caller (`getAuthenticatedDoctorId`, now exported from `record.controller.js`), the clinic to that doctor's clinic, and the time to now. Status is `confirmed`, where patient bookings stay `pending`.
  - An ADMIN without a doctor record must pass `doctor_id`.
  - App: a "Walk-in" button next to "New visit" on `/doctor/patients`. It calls `AppointmentService.createWalkIn`, refreshes the queue, and shows a snackbar with a "Start visit" action that opens the visit form linked to the appointment.
  - The patient sees the walk-in in My Appointments via the 10 s polling.
  - Checked with a scratch script against the local DB (3/3, rows cleaned up).
- **2026-09-11: Live doctor↔patient updates.** Three providers now poll every 10 s, only while their screen is open: `doctorTodayAppointmentsProvider`, `myAppointmentsProvider` and `patientRecordsProvider` (`Timer` + `ref.invalidateSelf`). Verified by the user end to end:
  - the patient books, and the booking appears in the doctor's queue;
  - the doctor saves a visit linked to the appointment, which marks it completed (existing `createMedicalRecord` behaviour);
  - the patient's appointments and records update.
  - Not done: push (move to FCM or websockets if load matters), and a doctor "confirm" action (appointments go straight from pending to completed).
- **2026-09-11 — Clinic (doctor/admin) side made reachable + PC/web layout.** Doctors onboarded by an admin (`POST /api/doctors`) had no `users` row, so on login `/patients/me` 404'd and they were pushed into patient registration. `getMyProfile` now links an unlinked Doctor by phone (exact or last 10 digits) on first sign-in and creates the user as DOCTOR. All signed-in routes sit under a go_router `ShellRoute` (`clinic_shell.dart`): waits for session restore, redirects signed-out users to /login, gates `/doctor/*` (DOCTOR/ADMIN) and `/admin/*` (ADMIN) — the per-screen guards were removed. Staff get a NavigationRail at ≥800 px wide. New `/doctor/patients` patient lookup (search + cross-clinic history). Queue/doctors/clinics use a responsive grid; admin forms open as dialogs on PC; visit form capped at 880 px, one-line prescription rows, Ctrl+Enter saves.
- **2026-09-11 — App polish + bug fixes.** New theme and redesigned login/dashboard. Fixed: token expiry after 1h, offline start logging users out (profile now cached in Hive), duplicate OTP screen on resend and doubled error snackbars, report links not opening, booking wizard resuming stale state, non-Latin names rejected at registration, stale smoke test. Removed the fake notifications button and the dashboard's 2-tab bottom bar.
- **2026-09-11 — Guest registration fixed (backend).** `phone` is required + unique on `users`/`patients`, but anonymous Firebase users have none, so `POST /api/patients` always 400'd for guests. Guests now get the placeholder phone `guest-<firebase uid>` (`backend/controllers/patient.controller.js`).

## Local dev setup (as of 2026-09-11)
- DB: Docker container `migrant-clinic-db` (postgres:16, port 5432, volume `migrant_clinic_pgdata`), matching `backend/.env`. Migrations applied; seeded with `scripts/seed-nearby-clinics.js`. The older `postgres-dev` container belongs to another project — don't use it.
  - (2026-09-13) `backend/docker-compose.yml` now defines it: same container name, port and volume, `restart: unless-stopped`. Run `cd backend && docker compose up -d`. It reads `POSTGRES_PASSWORD` from `backend/.env`, which must match `DATABASE_URL`. The original container was a `docker run` one with no restart policy, and it conflicts by name, so `docker rm` it once; the data lives in the volume. `/api/health` never touches the DB, so a stopped DB shows up only at login, as an `Invalid prisma.user.findUnique()` error with a blank message (ECONNREFUSED).
- Phone testing over wireless adb: run `adb reverse tcp:3000 tcp:3000` so the app's default `http://localhost:3000/api` reaches the backend. No LAN IP or cleartext config change needed. Re-run after each adb reconnect.
- Prisma 7: the datasource URL lives in `backend/prisma.config.ts`, not in `schema.prisma`.
- Test accounts (2026-09-11):
  - **Dr. Default Doctor**: phone `+919999900001`, Firebase test OTP `123456`, clinic "Central Migrant Health Hub". It is a pre-created Doctor row, linked to a user on the first phone login. It needs the number under Firebase console → Auth → Phone → "Phone numbers for testing", and the SMS region policy must allow India. Otherwise login shows "SMS unable to be sent until this region enabled".
  - Older guest doctors: `guest-tjEBbgzUuleqMiAFIuzj0i73rGX2` ("Dr. Test Doctor"), and `guest-15YBX55yHjYATVvWeBkIBARxkIB2` ("Dr. Portal Test"). The second was promoted from a patient, so it can no longer book.
- Web test servers (`.claude/launch.json`):
  - `web` is the debug `flutter run -d web-server` on :5000 (patient side).
  - `web-doctor` serves the profile build `mobile_app/build/web` on :5001 (doctor side). Rebuild it with `flutter build web --profile` after app changes.
  - Use a separate browser profile per role, because Firebase keeps one login per browser/origin.
- All clinics are seeded in Singapore and sorted nearest-first, so "Central Migrant Health Hub" (where the test doctors sit) isn't first in the list from India.
- The doctor queue's `?date=` filter uses UTC day bounds, so bookings before 05:30 IST show under the previous day.
- Prefer `test/clinic_flow_test.dart` over browser clicking (2026-09-11). It runs the real router and screens with fake services (the services are built with `Dio()` so no Firebase) and an in-memory cache (`LocalCacheService.init(inMemory: true)`). The save button spins behind the success dialog, so use `pump()` rather than `pumpAndSettle()` after a save.
- Browser testing Flutter web: it renders to a canvas, so clicks go by coordinates. Viewport emulation breaks click mapping, and focus changes scroll the page, so re-screenshot after every click.
- Secrets exist locally: `backend/.env` and `backend/config/firebase-adminsdk.json`. Never commit, print or publish them.

## User preferences
- When asked for a plan, save it as a `.md` file in the repo and stop. Only implement when explicitly asked.
- The user does web UI clicks (register, log in, book) themselves to save tokens. Give short numbered steps instead of driving the Flutter canvas (2026-09-11). The in-app browser drops Flutter clicks while its pane is hidden, and the `[::1]` origin hangs in debug.
