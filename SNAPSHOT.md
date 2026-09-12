# Folder Snapshot

Snapshot of the project layout as of 2026-09-11. It leaves out generated/build output (`node_modules/`, `.dart_tool/`, `build/`, `.gradle/`, lockfiles, `ephemeral/`).
Platform boilerplate (Flutter android/ios/linux/macos/windows/web) is collapsed to one line each.

**Keep this file current:** when files or folders are added, moved or deleted, update the tree below.

```
.
├── AWS_MIGRATION_PLAN.md          # GCP → AWS plan (RDS, S3, ECS) — not implemented yet
├── AI_DRUG_INTERACTION_PLAN.md    # cross-clinic medication conflict detector — Phase 1 done, 2-4 pending
├── CLAUDE.md                      # instructions for Claude (points here + MEMORY.md)
├── MEMORY.md                      # project context, decisions, status
├── SNAPSHOT.md                    # this file
├── .claude/launch.json            # local preview servers: web (:5000 debug), web-doctor (:5001 profile build)
├── DEVLOG.md                      # temporary log of the 2026-09-11 clinic-side/PC work
├── README.md                      # project overview (still describes GCP stack)
├── START_HERE.md, QUICK_START.md, SUMMARY.txt
├── FIREBASE_CREDENTIALS_SETUP.md, REPLACE_FIREBASE_CREDENTIALS.md, QUICK_FIREBASE_SETUP.txt
├── ENABLE_ANONYMOUS_AUTH.md, GUEST_LOGIN_SETUP.md
├── check-firebase-config.sh
├── .github/workflows/
│   ├── build-apk.yml              # CI: builds an installable Android APK on every push to main
│   └── deploy-container           # CI: backend image → GHCR. NOTE: no .yml extension, so GitHub never runs it
├── scripts/
│   └── push-docker-ghcr.ps1       # manual GHCR push
│
├── backend/                       # Node.js + Express REST API
│   ├── server.js                  # entry point; mounts /api, serves /uploads statically
│   ├── package.json               # express, prisma 7, @prisma/adapter-pg, firebase-admin, multer
│   ├── prisma.config.ts           # Prisma 7 config (DATABASE_URL lives here, not in schema)
│   ├── Dockerfile, .dockerignore  # node:22-slim image; secrets/uploads excluded
│   ├── .env (local secrets — never commit/print), .env.example, .gitignore
│   ├── config/
│   │   ├── prisma.js              # PrismaClient singleton (pg Pool adapter) — the real DB client
│   │   ├── firebase.js            # Firebase Admin init (key file → ADC fallback)
│   │   ├── firebase-adminsdk.json # service account key (gitignored, SECRET)
│   │   └── db.js                  # UNUSED raw pg Pool (safe to delete)
│   ├── routes/
│   │   ├── index.js               # mounts all routers under /api
│   │   ├── health.routes.js, protected.routes.js
│   │   ├── patient.routes.js, doctor.routes.js, clinic.routes.js
│   │   ├── appointment.routes.js
│   │   └── record.routes.js       # records, POST /interaction-check, POST /:id/upload (multer)
│   ├── controllers/
│   │   ├── health.controller.js, patient.controller.js, doctor.controller.js
│   │   ├── clinic.controller.js, appointment.controller.js
│   │   └── record.controller.js   # medical records, prescriptions, report upload,
│   │                              # + POST /interaction-check (drug conflict pre-flight)
│   ├── middleware/
│   │   ├── authenticate.js        # verifies Firebase ID token → req.user
│   │   ├── requireRole.js         # role gate (PATIENT / DOCTOR / ADMIN)
│   │   ├── authorizePatientAccess.js
│   │   ├── upload.js              # multer local-disk storage, 5 MB, PDF/PNG/JPG/WEBP
│   │   ├── errorHandler.js, notFound.js
│   ├── services/
│   │   └── interactionChecker.js  # cross-clinic drug conflict detector (curated table; AI leg = Phase 4)
│   ├── prisma/
│   │   ├── schema.prisma          # + DrugInteraction, InteractionCheck, InteractionSeverity
│   │   └── migrations/            # 20260810170839_init_schema, 20260910082706,
│   │                              # 20260912122022_add_drug_interactions, 20260912122039_add_history_indexes
│   ├── utils/
│   │   ├── healthId.js            # MWH-XXXXXX health ID generator
│   │   ├── drugName.js            # normalises free-text medicine names for table lookup
│   │   └── prescriptionWindow.js  # infers whether a prescription is still active
│   ├── scripts/                   # seed-*.js, seed-test-users.sql, set-user-role.js,
│   │                              # generate-test-token.js, get-test-tokens.js, list-ids.js,
│   │                              # seed-drug-interactions.js (56 curated pairs)
│   ├── postman/                   # API collection + environment
│   ├── models/README.md
│   └── uploads/reports/           # local uploaded reports (1 test PDF)
│
└── mobile_app/                    # Flutter app
    ├── pubspec.yaml, l10n.yaml, analysis_options.yaml
    ├── flutter_launcher_icons.yaml, flutter_native_splash.yaml
    ├── assets/icons/              # app_icon.png, splash_logo.png
    ├── test/widget_test.dart, clinic_shell_test.dart (role gate),
    │   clinic_flow_test.dart (doctor/admin screens via real router + fake services)
    ├── lib/
    │   ├── main.dart
    │   ├── firebase_options.dart  # Firebase client config (unchanged by AWS move)
    │   ├── routes/app_router.dart
    │   ├── core/
    │   │   ├── constants/app_constants.dart   # API_BASE_URL via --dart-define
    │   │   ├── errors/api_exception.dart
    │   │   ├── network/api_client.dart        # shared Dio; refreshes Firebase token per request
    │   │   ├── models/cached_result.dart
    │   │   ├── theme/app_colors.dart, app_theme.dart
    │   │   └── utils/app_logger.dart
    │   ├── data/services/
    │   │   ├── auth_service.dart, secure_storage_service.dart, local_cache_service.dart
    │   │   ├── patient_service.dart, appointment_service.dart
    │   │   ├── record_service.dart, admin_service.dart
    │   ├── providers/
    │   │   ├── app_providers.dart, auth_provider.dart, locale_provider.dart
    │   │   ├── appointment_provider.dart, records_provider.dart
    │   │   ├── doctor_provider.dart, admin_provider.dart
    │   ├── presentation/
    │   │   ├── screens/
    │   │   │   ├── auth/          # login, otp_verification, patient_registration
    │   │   │   ├── dashboard/     # dashboard_screen + widgets/dashboard_header_card
    │   │   │   ├── appointments/  # appointments_screen, book_appointment_screen
    │   │   │   ├── records/       # records_screen, record_detail_screen (opens report URL)
    │   │   │   ├── clinic/clinic_shell.dart   # wraps signed-in routes: auth wait, role gate, staff side nav on wide screens
    │   │   │   ├── doctor/doctor_screens.dart # queue, add visit record, patient lookup
    │   │   │   ├── admin/admin_screens.dart   # manage doctors, manage clinics
    │   │   │   └── profile/profile_screen.dart
    │   │   └── widgets/           # app_error_view, custom_card, offline_banner, responsive_card_list
    │   └── l10n/                  # app_en/hi/ta.arb + generated/
    ├── android/                   # app/build.gradle.kts, app/google-services.json, res/ icons+splash
    ├── ios/                       # Runner/ (AppDelegate, Info.plist, assets), Flutter/ xcconfigs
    ├── web/                       # index.html, manifest.json, icons/, splash/
    └── linux/, macos/, windows/   # stock Flutter desktop runners
```
