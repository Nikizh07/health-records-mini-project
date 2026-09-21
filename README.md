# Cloud-Based Digital Health Record & Appointment Management System
### For Migrant Worker Clinics

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat&logo=node.js&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![Prisma](https://img.shields.io/badge/Prisma-2D3748?style=flat&logo=prisma&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase_Auth-FFCA28?style=flat&logo=firebase&logoColor=black)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)

A platform that gives migrant workers a **portable digital health record** that follows them across clinics and cities. It also includes an appointment system that participating clinics manage in real time.

---

## Problem statement

Migrant workers often move between cities and states for work, which breaks up their access to continuous healthcare. Medical history, prescriptions and vaccination records stay at the clinic that created them. A worker who visits a new clinic starts from zero, which leads to repeated tests, medication errors and gaps in care.

This project closes that gap with a **shared, multi-clinic health record system**. Every participating clinic connects to the same backend, so a patient's records and appointments can be seen from any clinic in the network.

---

## Project status

| Area | Status |
|---|---|
| Patient app (Android + web) | Working |
| Doctor / admin portal (web, for PC) | Working |
| Backend API + PostgreSQL | Working, runs locally |
| Consent and access log | Working: records need a care link, the patient's consent or an audited emergency override |
| Drug interaction warnings | Working, using a list of 56 known drug pairs |
| AI-assisted interaction check | Built, off until `AI_*` env vars are set (see `backend/.env.example`); not yet tried with a real model |
| Cloud deployment | Code is AWS-ready (RDS, S3, ECS Fargate, CI to ECR), see [`AWS_MIGRATION_PLAN.md`](AWS_MIGRATION_PLAN.md). The AWS account and its resources are not provisioned yet, so nothing is running in the cloud. |
| Push notifications | Not built. Screens poll every 10 s instead. |

---

## Key features

**For patients**
- **Portable health ID**: every patient gets an ID like `MWH-XXXXXX` that works at every registered clinic
- **Sign in** with phone OTP, Google or email. Google and email accounts add a verified mobile number. Guest login only in test builds.
- **Registered at the clinic first?** Staff can register a patient who has no phone app. When that patient later signs in on the same number, they confirm their date of birth and get their existing health ID and history.
- **Appointments at any clinic**: book, reschedule or cancel. Clinics are listed nearest first.
- **Health records**: diagnoses, prescriptions, visit notes and attached reports from every clinic in one place
- **You decide who sees your history**: a doctor outside your care team has to ask. Your phone shows "Dr X, Clinic Y wants to see your medical history for 24 hours" — Allow or Deny. No app to hand? Make a 6-digit share code that works once, for 10 minutes.
- **Privacy screen**: who can see your history right now, a Revoke button, and a log of every time someone opened your records
- **Multilingual UI** in English, Hindi and Tamil

**For doctors and clinic staff**
- **Today's queue**: the doctor's appointments, refreshed every 10 s
- **Patient lookup**: search your clinic's patients by name, or anyone by exact health ID or phone. The history opens when you have a care link (you wrote a record, or they have an appointment at your clinic within 30 days); otherwise ask for consent, enter their share code, or use emergency access with a written reason (4 hours, flagged to the patient and the clinic).
- **Front desk (receptionist)**: the clinic queue for every doctor, confirm or cancel bookings, register a new patient and book them a walk-in. Receptionists never see records.
- **Walk-ins**: create a confirmed appointment for right now and start the visit straight away
- **Visit form** with diagnosis, notes and prescriptions. Ctrl+Enter saves. Reports can be attached through the API (`POST /api/records/:id/upload`), but the app has no upload screen yet.
- **Drug interaction warnings**: before a visit is saved, each new prescription is checked against:
  - drugs the patient is still taking from **any clinic**
  - the other drugs in the **same prescription**

  If there's a conflict, a banner names the drugs, how serious it is and which clinic prescribed the existing drug. The doctor can still save, but has to give a reason, and every check is kept for audit.
- **Staff sign-in** with email + password or Google (phone OTP still works). Staff join by an admin's invite, or doctors apply with their registration number and wait for approval.
- **Admin portal**: manage clinics, invite staff, approve or reject doctor applications, disable accounts
- **Role-based access** for PATIENT, RECEPTIONIST, DOCTOR, CLINIC_ADMIN and ADMIN, enforced by the backend
- **Access log**: every staff read or write of a patient's records is recorded, and clinic admins can review it, with emergency access highlighted

---

## Tech stack

| Layer | Technology |
|---|---|
| Mobile / web app | Flutter (Dart), Riverpod, go_router, Dio, Hive (local cache) |
| Backend API | Node.js 22, Express 4 |
| Database | PostgreSQL 16, Prisma 7 (`@prisma/adapter-pg`) |
| Authentication | Firebase Authentication (phone OTP for patients; email/password and Google for staff; anonymous guest in test builds), verified server-side with `firebase-admin` |
| File storage | Private Amazon S3 bucket via Multer (in memory) + the AWS SDK. Reports are handed out as 15-minute presigned URLs. |
| Containers | Docker (backend image, local Postgres via Docker Compose) |
| Cloud | AWS: RDS for PostgreSQL, S3 for reports, ECS Fargate for the API, ECR for images |
| CI | GitHub Actions: `flutter analyze` + `flutter test`, an installable Android APK, and the backend image to ECR → ECS on every push to `main` |

---

## System architecture

```
Flutter app (Android / web)
        │
        ▼  REST + Firebase ID token
   Node.js / Express API ──────► Firebase Auth (token verification)
        │
   ┌────┴─────────────┐
   ▼                  ▼
PostgreSQL      Private S3 bucket
(RDS, Prisma)   (reports, presigned URLs)
```

The app never talks to the database or storage directly. Every request goes through the API, which handles authorization, validation and business logic.

---

## Database schema

Core entities: `User`, `Patient`, `Doctor`, `Clinic`, `Appointment`, `MedicalRecord`, `Prescription`, plus `DrugInteraction` and `InteractionCheck` for the drug interaction checker.

- One **Clinic** has many **Doctors** and **Appointments**
- One **Patient** has many **Appointments** and **MedicalRecords**
- One **MedicalRecord** has many **Prescriptions**
- **InteractionCheck** stores every pre-save check, the conflicts it found and the doctor's override reason

The full schema is in [`backend/prisma/schema.prisma`](backend/prisma/schema.prisma).

---

## Project structure

```
.
├── mobile_app/                 # Flutter app: patient side + doctor/admin portal
│   ├── lib/
│   │   ├── core/               # constants, network client, theme, utils
│   │   ├── data/services/      # API services (auth, appointments, records, admin)
│   │   ├── providers/          # Riverpod providers
│   │   ├── presentation/       # screens and widgets
│   │   ├── l10n/               # en / hi / ta translations
│   │   └── routes/             # go_router config
│   └── test/                   # widget and flow tests
├── backend/                    # Node.js + Express API
│   ├── server.js
│   ├── docker-compose.yml      # local PostgreSQL
│   ├── Dockerfile
│   ├── routes/  controllers/  middleware/
│   ├── services/               # drug interaction checker
│   ├── utils/                  # health ID, drug name normalisation, prescription window
│   ├── prisma/                 # schema + migrations
│   └── scripts/                # seeders, role tools, test suite
├── .github/workflows/          # CI (APK build)
├── AWS_MIGRATION_PLAN.md
├── AUTH_RBAC_CONSENT_PLAN.md
└── thinking-archive/           # finished plans and old setup notes
```

---

## Getting started

### Prerequisites
- Flutter SDK (Dart 3.12+)
- Node.js 22
- Docker
- A Firebase project with Phone and Anonymous sign-in enabled, and a service account key

### 1. Database
```bash
cd backend
cp .env.example .env        # set DATABASE_URL and a matching POSTGRES_PASSWORD
docker compose up -d
```

### 2. Backend
```bash
cd backend
npm install
npx prisma migrate deploy
node scripts/seed-nearby-clinics.js
node scripts/seed-drug-interactions.js
npm run dev                 # http://localhost:3000/api/health
```
Put the Firebase service account key at `backend/config/firebase-adminsdk.json`, or point `FIREBASE_SERVICE_ACCOUNT_PATH` at it.

### 3. Mobile app
```bash
cd mobile_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<host>:3000/api
```
- `API_BASE_URL` defaults to `http://localhost:3000/api`.
- Release builds only accept an `https://` URL, so run debug or `--profile` builds locally.
- To test on an Android phone over adb, run `adb reverse tcp:3000 tcp:3000` and keep the default URL.

### Running the doctor portal locally (web)
The clinic side (doctor/admin) is built for a PC browser. Keep the window at least 800 px wide to get the side navigation.

1. **Backend:** start the database and the backend as above.
2. **Patient app** at http://localhost:5000: run `cd mobile_app && flutter run -d web-server --web-port 5000`, click *Continue as guest* and register.
3. **Doctor portal** at http://localhost:5001:
   - Build it with `cd mobile_app && flutter build web --profile`.
   - Serve it with `python3 -m http.server 5001 --directory build/web`.
   - Open it in a **separate browser profile or a private window**, because Firebase keeps one login per browser.
   - **After every rebuild, hard-reload the tab (Ctrl+Shift+R).** An already-open tab keeps running the old build.
4. **Test doctor login:** phone `9999900001`, OTP `123456`. This needs three things:
   - In the Firebase console, go to Authentication → Sign-in method → Phone → *Phone numbers for testing* and add `+91 9999900001` with code `123456`.
   - Authentication → Settings → *SMS region policy* must allow India.
   - A doctor with that phone must exist. An admin can add one in the admin portal, or an API client can call `POST /api/doctors`. The first login with that number links the account as DOCTOR. To turn an existing account into a doctor instead, run `node backend/scripts/set-user-role.js <phone> DOCTOR "<name>" "<specialization>"`.
   - **Email or Google staff sign-in** (the *Clinic staff* tab, default on web) needs Email/Password and Google enabled under Authentication → Sign-in method. `localhost` is an authorized domain by default; add any other web origin under Authentication → Settings → Authorized domains. Google on Android also needs the app's SHA-1 in the Firebase project settings.
   - An admin invites staff from **Staff → Invite** (role, name, email or phone). No email is sent: the person signs in with that email (verified) or phone and lands on their portal. Without an invite, a verified email gets the doctor application form and waits on a pending screen until a clinic admin approves it under **Staff → Applications**.
5. **The first admin** has to be created from the command line after that account has signed in once: `node backend/scripts/set-user-role.js <phone> ADMIN`.
6. **The flow:**
   - The patient books *Central Migrant Health Hub* → the doctor, for today.
   - The appointment appears in the doctor's queue within about 10 s.
   - The doctor opens it and saves the visit (Ctrl+Enter), which marks the appointment completed.
   - The patient's *My Appointments* and *Health Records* show the update within about 10 s.
   - **Walk-ins:** a doctor can also open *Patient Lookup*, find the patient and click **Walk-in**. This creates a confirmed appointment for right now, puts it in the doctor's queue, and shows it in the patient's *My Appointments*. The snackbar's *Start visit* opens the visit form for that appointment.
   - **Drug interactions:** prescribe *warfarin* and *ibuprofen* in one visit. A red banner appears, and the save button changes to **Save Anyway**, which asks for a reason. After a patient has a saved warfarin prescription, prescribing *naproxen* in a later visit shows the warning with the clinic and date of the earlier prescription.

---

## Environment variables

Set these in `backend/.env` (template: `backend/.env.example`):

| Variable | Purpose |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string, e.g. `postgresql://postgres:<password>@localhost:5432/migrant_clinic_db` |
| `POSTGRES_PASSWORD` | Password for the Docker Compose database. It must match `DATABASE_URL`. |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | Path to the Firebase service account key (default `./config/firebase-adminsdk.json`) |
| `FIREBASE_SERVICE_ACCOUNT_JSON` | The key itself, raw JSON or base64. Takes priority over the path. Use it on any host, where the key file is `.dockerignore`d and so absent from the image. |
| `AWS_REGION` | Region for S3 (and Bedrock/SageMaker, if the AI leg uses them) |
| `S3_BUCKET_NAME` | Private bucket for uploaded reports. Unset locally, uploads fail and existing records are returned unsigned. |
| `PORT` | API port (default `3000`) |
| `NODE_ENV` | `development` or `production` |

`FIREBASE_PROJECT_ID` and `ALLOWED_ORIGINS` are in the template, but the code doesn't read them yet.
AWS credentials are never set as variables: locally they come from `AWS_PROFILE`, in production from the ECS task role.

**Keep secrets out of git.** That means `backend/.env` and the Firebase service account key.

---

## Testing a build on a phone (temporary hosted backend)

To install an APK on a phone and use it with no PC, cable or `adb reverse`, the
app needs a public HTTPS backend. `render.yaml` in the repo root is a Render
Blueprint that stands one up on the free tier.

1. **Deploy.** Render dashboard → **New** → **Blueprint** → pick this repo. It
   creates the API and a Postgres database from `render.yaml`, then asks for
   `FIREBASE_SERVICE_ACCOUNT_JSON` (paste `backend/config/firebase-adminsdk.json`,
   or its base64) and `FIREBASE_PROJECT_ID`. Migrations run on every boot.
2. **Seed it.** The new database is empty. From your PC, using the database's
   *External* connection string (Render → the database → Connections):
   ```bash
   cd backend
   DATABASE_URL='<external-url>' node scripts/seed-nearby-clinics.js
   DATABASE_URL='<external-url>' node scripts/seed-drug-interactions.js
   ```
3. **Build the APK against it.** GitHub → Actions → *Build Android APK* → **Run
   workflow**, with `api_base_url` = `https://<service>.onrender.com/api`. An
   HTTPS URL makes it a **release** APK automatically. Download it from the run's
   artifacts and install it. (Setting the `API_BASE_URL` repository variable does
   the same for every future push to `main`.)

Free-tier caveats, all of which you will notice while testing:

- The service **sleeps after ~15 minutes idle**. The next request cold-starts it
  and can take up to a minute, while the app's Dio timeout is 10 s — so the first
  action after a pause usually fails once and works on retry. Wake it by opening
  `https://<service>.onrender.com/api/health` in a browser first.
- The free database **expires 30 days** after creation.
- There is **no persistent disk**: uploaded reports under `uploads/reports/` are
  wiped on every deploy and restart. Records and prescriptions are in Postgres
  and survive; the files do not.
- `NODE_ENV=production` **refuses anonymous (guest) sign-in**, and a release APK
  hides the guest button anyway. Sign in with a phone or email account.

---

## Testing

```bash
cd mobile_app && flutter analyze && flutter test
```
```bash
cd backend && node scripts/test-interactions.js && node scripts/test-auth-rbac.js
```
- `flutter test` covers the role gate, the doctor/admin screens, staff email sign-in to the pending screen, the Staff screen, the front desk, and the consent gate, popup and privacy screen. It uses the real router with fake services.
- `test-interactions.js` runs 112 drug interaction checks against the real API and database. Firebase and the AI provider are faked, so it needs no device or credentials, and it removes its own test data.
- `test-auth-rbac.js` covers sign-in, role and consent rules the same way: role from the database only, phone only from the verified token, a permission × endpoint matrix generated from the permission table, staff invites and applications, desk registration and claim, the front desk, and consent (care link, request, share code, emergency, revoke, access log).
- `node scripts/test-ai-provider.js` sends one canned case to whichever AI provider `backend/.env` configures and prints the reply.
- `node scripts/test-s3-signing.js` checks report URL signing (key → presigned URL, absolute URLs and empty reports left alone). Signing is local, so it needs no bucket and no credentials.

---

## CI

[`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml) runs on every push to `main` that touches `mobile_app/`:
1. `flutter analyze` and `flutter test`
2. Builds an Android APK and uploads it as a workflow artifact, kept for 30 days:
   - with no `API_BASE_URL` repository variable, a debug APK
   - with an `https://` URL set, a release APK

[`.github/workflows/deploy-container.yml`](.github/workflows/deploy-container.yml) runs on every push to `main` that touches `backend/`:
1. Assumes an AWS role over OIDC — no long-lived keys in the repository
2. Builds the backend image and pushes it to ECR, tagged with the commit SHA and `latest`
3. Forces a new ECS deployment; the container applies pending Prisma migrations before starting

It needs `AWS_ROLE_ARN` as a repository secret, and `AWS_REGION`, `ECS_CLUSTER` and `ECS_SERVICE` as repository variables.

---

## Known limitations

- Report URLs are presigned for 15 minutes. A record screen left open longer needs a refresh before the report opens.
- Screens poll every 10 s rather than receiving push updates, so a consent popup can take that long to appear.
- The consent and front-desk screens are English-only; the patient app is translated.
- Emergency access is not reviewed by anyone: it is recorded and shown to the patient and the clinic admin.
- The doctor queue's date filter uses UTC day boundaries, so bookings before 05:30 IST appear under the previous day.

---

## Cloud computing concepts

This project was built as a **Cloud Computing domain mini project**. The AWS deployment demonstrates:

- **Managed database (DBaaS)**: Amazon RDS for PostgreSQL
- **Object storage**: private S3 buckets with presigned URLs for medical reports
- **Containers**: the backend as a Docker image on ECS Fargate, which scales without managing servers
- **Managed services**: Firebase Authentication for identity
- **Multi-tenancy**: one backend serves many independent clinics
- **CI/CD automation**: GitHub Actions builds and tests on every push

---

## Roadmap

- [ ] Provision the AWS resources and run the first deployment (the code and CI are ready)
- [ ] AI-assisted drug interaction check alongside the known-pair list
- [ ] Push notifications for appointment reminders
- [ ] Offline-first sync for low-connectivity areas
- [ ] Terraform scripts for infrastructure-as-code
- [ ] Admin analytics dashboard (patient footfall, disease trends)
- [ ] Multi-language voice input for low-literacy users

---

## Author

Developed as a Semester 5 mini project in the Cloud Computing domain.

*Feel free to open an issue or reach out with questions about the architecture or setup.*
