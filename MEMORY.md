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
- Screens should rely on `AppTheme` (buttons, inputs, cards, app bars) rather than per-widget `styleFrom` overrides.

## Changelog
- **2026-09-11 — App polish + bug fixes.** New theme and redesigned login/dashboard. Fixed: token expiry after 1h, offline start logging users out (profile now cached in Hive), duplicate OTP screen on resend and doubled error snackbars, report links not opening, booking wizard resuming stale state, non-Latin names rejected at registration, stale smoke test. Removed the fake notifications button and the dashboard's 2-tab bottom bar.
- **2026-09-11 — Guest registration fixed (backend).** `phone` is required + unique on `users`/`patients`, but anonymous Firebase users have none, so `POST /api/patients` always 400'd for guests. Guests now get the placeholder phone `guest-<firebase uid>` (`backend/controllers/patient.controller.js`).

## Local dev setup (as of 2026-09-11)
- DB: Docker container `migrant-clinic-db` (postgres:16, port 5432, volume `migrant_clinic_pgdata`), matching `backend/.env`. Migrations applied; seeded with `scripts/seed-nearby-clinics.js`. The older `postgres-dev` container belongs to another project — don't use it.
- Phone testing over wireless adb: run `adb reverse tcp:3000 tcp:3000` so the app's default `http://localhost:3000/api` reaches the backend. No LAN IP or cleartext config change needed. Re-run after each adb reconnect.
- Prisma 7: the datasource URL lives in `backend/prisma.config.ts`, not in `schema.prisma`.
- Secrets exist locally: `backend/.env` and `backend/config/firebase-adminsdk.json`. Never commit, print or publish them.

## User preferences
- When asked for a plan, save it as a `.md` file in the repo and stop. Only implement when explicitly asked.
