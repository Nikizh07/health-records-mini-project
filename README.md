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
| Drug interaction warnings | Working, using a list of 56 known drug pairs |
| AI-assisted interaction check | Built, off until `AI_*` env vars are set (see `backend/.env.example`); not yet tried with a real model |
| Cloud deployment | Planned on AWS (RDS, S3, ECS Fargate), see [`AWS_MIGRATION_PLAN.md`](AWS_MIGRATION_PLAN.md). Nothing is deployed yet. |
| Push notifications | Not built. Screens poll every 10 s instead. |

---

## Key features

**For patients**
- **Portable health ID**: every patient gets an ID like `MWH-XXXXXX` that works at every registered clinic
- **Sign in** with phone OTP, Google or email. Google and email accounts add a verified mobile number. Guest login only in test builds.
- **Registered at the clinic first?** Staff can register a patient who has no phone app. When that patient later signs in on the same number, they confirm their date of birth and get their existing health ID and history.
- **Appointments at any clinic**: book, reschedule or cancel. Clinics are listed nearest first.
- **Health records**: diagnoses, prescriptions, visit notes and attached reports from every clinic in one place
- **Multilingual UI** in English, Hindi and Tamil

**For doctors and clinic staff**
- **Today's queue**: the doctor's appointments, refreshed every 10 s
- **Patient lookup** with full history across clinics
- **Walk-ins**: create a confirmed appointment for right now and start the visit straight away
- **Visit form** with diagnosis, notes and prescriptions. Ctrl+Enter saves. Reports can be attached through the API (`POST /api/records/:id/upload`), but the app has no upload screen yet.
- **Drug interaction warnings**: before a visit is saved, each new prescription is checked against:
  - drugs the patient is still taking from **any clinic**
  - the other drugs in the **same prescription**

  If there's a conflict, a banner names the drugs, how serious it is and which clinic prescribed the existing drug. The doctor can still save, but has to give a reason, and every check is kept for audit.
- **Staff sign-in** with email + password or Google (phone OTP still works). Staff join by an admin's invite, or doctors apply with their registration number and wait for approval.
- **Admin portal**: manage clinics, invite staff, approve or reject doctor applications, disable accounts
- **Role-based access** for PATIENT, RECEPTIONIST, DOCTOR, CLINIC_ADMIN and ADMIN, enforced by the backend

---

## Tech stack

| Layer | Technology |
|---|---|
| Mobile / web app | Flutter (Dart), Riverpod, go_router, Dio, Hive (local cache) |
| Backend API | Node.js 22, Express 4 |
| Database | PostgreSQL 16, Prisma 7 (`@prisma/adapter-pg`) |
| Authentication | Firebase Authentication (phone OTP for patients; email/password and Google for staff; anonymous guest in test builds), verified server-side with `firebase-admin` |
| File storage | Local disk via Multer (`backend/uploads/`). Moving to S3 is planned. |
| Containers | Docker (backend image, local Postgres via Docker Compose) |
| CI | GitHub Actions: `flutter analyze` + `flutter test`, and an installable Android APK on every push to `main` |

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
PostgreSQL      Local uploads
 (Prisma)       (reports)
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
| `PORT` | API port (default `3000`) |
| `NODE_ENV` | `development` or `production` |

`FIREBASE_PROJECT_ID`, `GCS_BUCKET_NAME` and `ALLOWED_ORIGINS` are in the template, but the code doesn't read them yet.

**Keep secrets out of git.** That means `backend/.env` and the Firebase service account key.

---

## Testing

```bash
cd mobile_app && flutter analyze && flutter test
```
```bash
cd backend && node scripts/test-interactions.js && node scripts/test-auth-rbac.js
```
- `flutter test` covers the role gate, the doctor/admin screens, staff email sign-in to the pending screen, and the Staff screen. It uses the real router with fake services.
- `test-interactions.js` runs 112 drug interaction checks against the real API and database. Firebase and the AI provider are faked, so it needs no device or credentials, and it removes its own test data.
- `test-auth-rbac.js` covers sign-in and role rules the same way: role from the database only, phone only from the verified token, doctors linked by exact phone, visits saved under the right doctor, guests refused in production.
- `node scripts/test-ai-provider.js` sends one canned case to whichever AI provider `backend/.env` configures and prints the reply.

---

## CI

[`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml) runs on every push to `main` that touches `mobile_app/`:
1. `flutter analyze` and `flutter test`
2. Builds an Android APK and uploads it as a workflow artifact, kept for 30 days:
   - with no `API_BASE_URL` repository variable, a debug APK
   - with an `https://` URL set, a release APK

There's also a backend image workflow, `.github/workflows/deploy-container`. It lacks the `.yml` extension, so GitHub never runs it.

---

## Known limitations

- Uploaded reports under `/uploads` are served **without authentication**. Anyone with the URL can open them until the move to S3 with signed URLs.
- Screens poll every 10 s rather than receiving push updates.
- The doctor queue's date filter uses UTC day boundaries, so bookings before 05:30 IST appear under the previous day.

---

## Cloud computing concepts

This project was built as a **Cloud Computing domain mini project**. The planned AWS deployment is designed to demonstrate:

- **Managed database (DBaaS)**: Amazon RDS for PostgreSQL
- **Object storage**: private S3 buckets with presigned URLs for medical reports
- **Containers**: the backend as a Docker image on ECS Fargate, which scales without managing servers
- **Managed services**: Firebase Authentication for identity
- **Multi-tenancy**: one backend serves many independent clinics
- **CI/CD automation**: GitHub Actions builds and tests on every push

---

## Roadmap

- [ ] Deploy to AWS (RDS, S3, ECS Fargate)
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
