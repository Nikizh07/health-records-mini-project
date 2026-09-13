# Project Memory

Running context for this project: what it is, what's decided, and what's in progress.
**Keep this file current:** add decisions, status changes and gotchas as they happen, and date them.

## What this is
Cloud-based digital health record and appointment system for migrant worker clinics.
- **Backend** (`backend/`): Node.js 22, Express 4, Prisma 7 with the `@prisma/adapter-pg` driver adapter, PostgreSQL, Multer for uploads.
- **Mobile** (`mobile_app/`): Flutter, locales en / hi / ta. It talks only to the backend API (`API_BASE_URL` via `--dart-define`) and never touches the DB or storage directly.
- **Auth**: Firebase Auth on the client. The backend verifies Firebase ID tokens with `firebase-admin` (`middleware/authenticate.js`). Roles are PATIENT / DOCTOR / ADMIN (`middleware/requireRole.js`).
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
- **Decision (2026-09-12):** warn a doctor at save time when a new prescription conflicts with a drug another clinic already started. Full plan: `AI_DRUG_INTERACTION_PLAN.md`.
- Two knowledge sources: a seeded `drug_interactions` reference table (deterministic, always runs) **plus** an LLM leg.
- **The AI provider is pluggable, configured by env vars only** (2026-09-12). One adapter contract (`isConfigured()` + `complete({system,user})`) with three implementations: `openai-compatible` (plain `fetch`, no deps — covers OpenAI, Gemini's compat endpoint, Groq, OpenRouter, Ollama, vLLM, any custom URL), `bedrock`, and `sagemaker`. Adding a provider = one file + one registry line. AWS SDKs are `optionalDependencies`, lazily required.
- **The prompt lives in `backend/prompts/drug-interaction.md`, not in code** — `{{placeholders}}`, split into system/user by a `---USER---` line, cached only in production so prompt edits need no restart.
- Bedrock model ids are region-specific: get the exact id from `aws bedrock list-foundation-models --region ap-south-1 --by-provider meta`, never guess. SageMaker has no standard payload shape — the adapter targets HuggingFace TGI and the mapping is meant to be edited.
- **Fails open by design**: if Bedrock is unreachable the save still proceeds, flagged `ai_available: false`, and the curated table still fires. Never block a clinic on an LLM outage.
- Conflicts warn but don't block; the doctor must give an override reason, and every check is stored in `interaction_checks` for audit.
- **Status (2026-09-12): Phase 1 done** — schema (`drug_interactions`, `interaction_checks`, `InteractionSeverity`) + 2 migrations, `utils/drugName.js`, `utils/prescriptionWindow.js`, `services/interactionChecker.js`, `scripts/seed-drug-interactions.js` (56 curated pairs), and `POST /api/records/interaction-check`. Verified end to end against the local DB and over HTTP with a real doctor token; test rows cleaned up. Phases 2-4 (audit wiring, Flutter UI, AI layer) pending.
- Gotcha: `utils/drugName.js` `normaliseDrugName()` is the contract between the seeder and the checker. If one side changes how names are normalised and the other doesn't, lookups silently return nothing — there is no error.
- Gotcha: an unparseable `duration` makes a prescription count as active for 90 days (`ASSUMED_ACTIVE_DAYS`) and marks the conflict `confidence: "ASSUMED"`. Deliberate: a false warning is cheaper than a missed one.
- Known gap: the checker compares new drugs only against *existing* active ones, so two conflicting drugs prescribed in the **same visit** do not fire. Left open deliberately (outside the approved Phase 1 scope); closing it means including the new drugs on both sides of the pair loop in `findTableConflicts`.

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
  - Still yours to do: the browser walkthrough. Widget tests cover the logic and wording, not the look.
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
  - No secrets needed: the Android build has no `google-services` Gradle plugin, so Firebase comes from `lib/firebase_options.dart` and the gitignored `google-services.json` is not required. Release still signs with the debug keystore (`android/app/build.gradle.kts`) — fine for sideloading, not for Play.
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
