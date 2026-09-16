# Folder Snapshot

Snapshot of the project layout as of 2026-09-13. It leaves out generated/build output (`node_modules/`, `.dart_tool/`, `build/`, `.gradle/`, lockfiles, `ephemeral/`).
Platform boilerplate (Flutter android/ios/linux/macos/windows/web) is collapsed to one line each.

**Keep this file current:** when files or folders are added, moved or deleted, update the tree below.

```
.
├── AWS_MIGRATION_PLAN.md          # GCP → AWS plan (RDS, S3, ECS) — not implemented yet
├── AUTH_RBAC_CONSENT_PLAN.md      # registration (OTP/email/Google), RBAC roles, patient consent — 8 phases, Phases 1-7 built
├── CLAUDE.md                      # instructions for Claude (points here + MEMORY.md)
├── MEMORY.md                      # project context, decisions, status
├── SNAPSHOT.md                    # this file
├── README.md                      # project overview, status, setup, testing (rewritten 2026-09-13)
├── .claude/launch.json            # local preview servers: web (:5000 debug), web-doctor (:5001 profile build)
├── thinking-archive/              # no longer needed day to day; kept for history (moved 2026-09-13)
│   ├── AI_DRUG_INTERACTION_PLAN.md    # drug conflict detector plan — Phases 1-4 built
│   ├── DEVLOG.md                  # temporary log of the 2026-09-11 clinic-side/PC work (folded into MEMORY.md)
│   ├── START_HERE.md, QUICK_START.md, SUMMARY.txt   # stale 2026-09-10 Firebase/guest setup notes
│   ├── FIREBASE_CREDENTIALS_SETUP.md, REPLACE_FIREBASE_CREDENTIALS.md, QUICK_FIREBASE_SETUP.txt
│   ├── ENABLE_ANONYMOUS_AUTH.md, GUEST_LOGIN_SETUP.md
│   ├── check-firebase-config.sh   # uses root-relative paths; run from the repo root if ever needed
│   └── doctor-creds.txt           # Firebase test phone + OTP (also in README/MEMORY)
├── .github/workflows/
│   ├── build-apk.yml              # CI: builds an installable Android APK on every push to main
│   └── deploy-container           # CI: backend image → GHCR. NOTE: no .yml extension, so GitHub never runs it
├── scripts/
│   └── push-docker-ghcr.ps1       # manual GHCR push
│
├── backend/                       # Node.js + Express REST API
│   ├── server.js                  # entry point; mounts /api, serves /uploads statically
│   ├── package.json               # express, prisma 7, @prisma/adapter-pg, firebase-admin, multer;
│   │                              # optional @aws-sdk/client-bedrock-runtime + client-sagemaker-runtime
│   ├── prisma.config.ts           # Prisma 7 config (DATABASE_URL lives here, not in schema)
│   ├── Dockerfile, .dockerignore  # node:22-slim image; secrets/uploads excluded
│   ├── docker-compose.yml         # local Postgres 16 (migrant-clinic-db, :5432, volume migrant_clinic_pgdata)
│   ├── .env (local secrets — never commit/print), .env.example, .gitignore
│   ├── config/
│   │   ├── prisma.js              # PrismaClient singleton (pg Pool adapter) — the real DB client
│   │   ├── permissions.js         # the one role → permission table + permissionsFor() + outsideOwnClinic()
│   │   ├── firebase.js            # Firebase Admin init (key file → ADC fallback)
│   │   ├── firebase-adminsdk.json # service account key (gitignored, SECRET)
│   │   └── db.js                  # UNUSED raw pg Pool (safe to delete)
│   ├── routes/
│   │   ├── index.js               # mounts all routers under /api
│   │   ├── health.routes.js, protected.routes.js
│   │   ├── patient.routes.js, doctor.routes.js, clinic.routes.js
│   │   ├── appointment.routes.js
│   │   ├── staff.routes.js        # /staff: invites, doctor applications, list, approve/reject/disable
│   │   ├── consent.routes.js      # /consents (request, respond, share code, redeem, emergency, mine, revoke) + /audit/access
│   │   └── record.routes.js       # records, POST /interaction-check, POST /:id/upload (multer)
│   ├── controllers/
│   │   ├── health.controller.js, patient.controller.js (+ desk registration, claim by DOB, lookup), doctor.controller.js
│   │   ├── clinic.controller.js, appointment.controller.js (+ confirm)
│   │   ├── staff.controller.js    # buildInvite (shared with POST /doctors), acceptInvite (used by /patients/me),
│   │   │                          # applications, staff list, approve/reject/disable
│   │   ├── consent.controller.js  # consent flows (§D of AUTH_RBAC_CONSENT_PLAN.md) and the access audit list
│   │   └── record.controller.js   # medical records, prescriptions, report upload,
│   │                              # POST /interaction-check (drug conflict pre-flight), and
│   │                              # createMedicalRecord's check_id / override_reason audit wiring
│   ├── middleware/
│   │   ├── authenticate.js        # verifies Firebase ID token → req.user
│   │   ├── requirePermission.js   # permission gate (any of the listed permissions)
│   │   ├── authorizePatientAccess.js  # /patients/:id: self, or patient:lookup for demographics
│   │   ├── requirePatientAccess.js    # /records gate: care link / consent / emergency, writes patient_access_logs
│   │   ├── upload.js              # multer local-disk storage, 5 MB, PDF/PNG/JPG/WEBP
│   │   ├── errorHandler.js, notFound.js
│   ├── prompts/
│   │   └── drug-interaction.md    # LLM prompt for the AI leg (system / ---USER--- / {{placeholders}})
│   ├── services/
│   │   ├── patientAccess.js       # resolveAccess(user, patientId) → SELF | CARE | CONSENT | EMERGENCY
│   │   ├── interactionChecker.js  # drug conflict detector: new-vs-active (cross-clinic) AND
│   │   │                          # new-vs-new in the same visit; curated table + optional AI leg (fails open)
│   │   └── ai/
│   │       ├── index.js           # provider registry (AI_PROVIDER), timeout, prompt render, JSON parse
│   │       └── providers/         # openaiCompatible.js (fetch), bedrock.js, sagemaker.js (lazy AWS SDKs)
│   ├── prisma/
│   │   ├── schema.prisma          # + DrugInteraction, InteractionCheck, InteractionSeverity
│   │   └── migrations/            # 20260810170839_init_schema, 20260910082706,
│   │                              # 20260912122022_add_drug_interactions, 20260912122039_add_history_indexes,
│   │                              # 20260915000000_add_roles_status, 20260915120000_add_staff_onboarding,
│   │                              # 20260915180000_add_patient_registered_by, 20260915200000_add_consent
│   ├── utils/
│   │   ├── healthId.js            # MWH-XXXXXX health ID generator
│   │   ├── phone.js               # toE164(): every stored/matched phone goes through it (+91 default)
│   │   ├── drugName.js            # normalises free-text medicine names for table lookup
│   │   └── prescriptionWindow.js  # infers whether a prescription is still active
│   ├── scripts/                   # seed-*.js, seed-test-users.sql, set-user-role.js,
│   │   │                          # generate-test-token.js, get-test-tokens.js, list-ids.js
│   │   ├── seed-drug-interactions.js  # 56 curated interaction pairs (idempotent upsert)
│   │   ├── test-interactions.js   # drug-interaction regression suite: 112 assertions over real
│   │   │                          # HTTP, Firebase stubbed, fake AI provider in-process
│   │   ├── test-auth-rbac.js      # auth/RBAC regression suite (AUTH_RBAC_CONSENT_PLAN.md), one section per phase;
│   │   │                          # same stubbed-Firebase harness as test-interactions.js
│   │   └── test-ai-provider.js    # smoke-tests whichever AI provider .env configures (no DB)
│   ├── postman/                   # API collection + environment (06. Staff Onboarding, 07. Consent & Access)
│   ├── models/README.md
│   └── uploads/reports/           # local uploaded reports (1 test PDF)
│
└── mobile_app/                    # Flutter app
    ├── pubspec.yaml, l10n.yaml, analysis_options.yaml
    ├── flutter_launcher_icons.yaml, flutter_native_splash.yaml
    ├── assets/icons/              # app_icon.png, splash_logo.png
    ├── test/widget_test.dart, clinic_shell_test.dart (permission gate),
    │   clinic_flow_test.dart (doctor/admin screens via real router + fake services),
    │   interaction_contract_test.dart (client↔API field names; skips without a live backend)
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
    │   │   ├── auth_service.dart      # phone OTP (sign-in or link to a Google/email user), guest, email/password, Google
    │   │   ├── secure_storage_service.dart, local_cache_service.dart
    │   │   ├── patient_service.dart, appointment_service.dart
    │   │   ├── record_service.dart   # records + checkDrugInteractions (pre-flight)
    │   │   ├── admin_service.dart     # clinics
    │   │   ├── staff_service.dart     # /staff: invites, applications, approve/reject/disable
    │   ├── providers/
    │   │   ├── app_providers.dart, auth_provider.dart, locale_provider.dart
    │   │   ├── appointment_provider.dart, records_provider.dart
    │   │   ├── doctor_provider.dart, admin_provider.dart (clinics, staff list, invites)
    │   ├── presentation/
    │   │   ├── screens/
    │   │   │   ├── auth/          # login (Patient / Clinic staff tabs), otp_verification, patient_registration,
    │   │   │   │                  # email_verification, staff_application (apply form + awaiting approval),
    │   │   │   │                  # claim_profile (DOB for a clinic-registered phone); /link-phone reuses login
    │   │   │   ├── dashboard/     # dashboard_screen (+ chatbot placeholder) + widgets/dashboard_header_card
    │   │   │   ├── appointments/  # appointments_screen, book_appointment_screen
    │   │   │   ├── records/       # records_screen, record_detail_screen (opens report URL)
    │   │   │   ├── clinic/clinic_shell.dart   # wraps signed-in routes: auth wait, permission gate, permission-filtered staff side nav on wide screens
    │   │   │   ├── doctor/doctor_screens.dart # queue, add visit record, patient lookup;
    │   │   │   │                              # _InteractionBanner = drug conflict warning + override reason
    │   │   │   ├── reception/reception_screens.dart # front desk pieces used by the queue + lookup screens:
    │   │   │   │                              # register-patient dialog, demographics + walk-in doctor picker, confirm/cancel
    │   │   │   ├── admin/admin_screens.dart   # Staff (applications / staff / invites tabs + invite dialog), manage clinics
    │   │   │   └── profile/profile_screen.dart
    │   │   └── widgets/           # app_error_view, custom_card, offline_banner, responsive_card_list
    │   └── l10n/                  # app_en/hi/ta.arb + generated/
    ├── android/                   # app/build.gradle.kts, app/google-services.json, res/ icons+splash
    ├── ios/                       # Runner/ (AppDelegate, Info.plist, assets), Flutter/ xcconfigs
    ├── web/                       # index.html, manifest.json, icons/, splash/
    └── linux/, macos/, windows/   # stock Flutter desktop runners
```
