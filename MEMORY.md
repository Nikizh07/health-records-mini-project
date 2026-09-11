# Project Memory

Running context for this project: what it is, what's decided, and what's in progress.
**Keep this file current:** add decisions, status changes and gotchas as they happen, and date them.

## What this is
Cloud-based digital health record and appointment system for migrant worker clinics.
- **Backend** (`backend/`): Node.js 22, Express 4, Prisma 7 with the `@prisma/adapter-pg` driver adapter, PostgreSQL, Multer for uploads.
- **Mobile** (`mobile_app/`): Flutter, locales en / hi / ta. It talks only to the backend API (`API_BASE_URL` via `--dart-define`) and never touches the DB or storage directly.
- **Auth**: Firebase Auth on the client. The backend verifies Firebase ID tokens with `firebase-admin` (`middleware/authenticate.js`). Roles are PATIENT / DOCTOR / ADMIN (`middleware/requireRole.js`).
- **Patients** get a health ID in the form `MWH-XXXXXX` (`utils/healthId.js`). Medical history is visible across clinics by design.

## Current infrastructure (as of 2026-09-11)
- Branded as GCP (Cloud Run / Cloud SQL / GCS), but the code is barely tied to GCP:
  - DB is plain Postgres via `DATABASE_URL`, with no Cloud SQL connector.
  - GCS was **never implemented**. Reports are saved to local disk (`backend/uploads/reports/`) and served from `/uploads`.
  - CI (`.github/workflows/deploy-container.yml`) only pushes the image to GHCR. Nothing auto-deploys.

## In progress: AWS migration
- **Decision (2026-09-11):** move the DB → RDS Postgres, storage → private S3 with presigned URLs, and the backend → ECS Fargate. **Keep Firebase exactly as is.**
- Full plan: `AWS_MIGRATION_PLAN.md`.
- **Status: plan only. No code changes made yet.**

## Known gotchas
- `backend/config/firebase.js` falls back to Google ADC when the key file is missing. That will fail on AWS, and the key is dockerignored, so it must be injected as the `FIREBASE_SERVICE_ACCOUNT_JSON` secret.
- `backend/config/db.js` is unused. `config/prisma.js` is the real DB client.
- `report_file_url` is a relative path (`/uploads/reports/...`). Since 2026-09-11 the app resolves it against `API_BASE_URL`. The backend serves `/uploads` **without auth** — medical files are public to anyone with the URL until the S3 move.
- All API services must build their client with `createApiClient()` (`mobile_app/lib/core/network/api_client.dart`). It swaps in a fresh Firebase ID token per request; tokens expire after 1 hour.
- The clinic side targets **Flutter web** for PC use. Linux/Windows desktop builds can't do Firebase phone auth. Release builds refuse a non-HTTPS `API_BASE_URL` (`AppConstants.validateNetworkSecurity`), so test locally with `flutter build web --profile` or `flutter run -d chrome`.
- The first ADMIN still has to be created with `backend/scripts/set-user-role.js <phone> ADMIN`. The account must have signed in once. Guest accounts are stored with the phone `guest-<uid>`.
- Screens should rely on `AppTheme` (buttons, inputs, cards, app bars) rather than per-widget `styleFrom` overrides.

## Changelog
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
