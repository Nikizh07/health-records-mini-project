# Cloud-Based Digital Health Record & Appointment Management System
### For Migrant Worker Clinics

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat&logo=node.js&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat&logo=postgresql&logoColor=white)
![Google Cloud](https://img.shields.io/badge/Google_Cloud-4285F4?style=flat&logo=google-cloud&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

A cloud-native mobile platform that gives migrant workers a **portable digital health record** — one that follows them across clinics and cities — combined with an appointment booking system that participating clinics can manage in real time.

---

---

## Problem statement

Migrant workers frequently relocate for work across cities and states, which fractures their access to continuous healthcare. Medical history, prescriptions, and vaccination records stay siloed at the clinic where they were created — so a worker who visits a new clinic starts from zero, leading to repeated diagnostics, medication errors, and gaps in care.

This project addresses that gap with a **multi-tenant, cloud-hosted health record system**: every participating clinic connects to the same backend, so a patient's record and appointment history are accessible from anywhere in the network.

---

## Key features

- **Portable digital health ID** — a unique identifier that follows the patient across every registered clinic
- **OTP-based authentication** — phone number login via Firebase Auth, no passwords to manage
- **Cross-clinic appointment booking** — book, reschedule, or cancel appointments at any participating clinic
- **Digital medical records** — diagnosis, prescriptions, and visit notes stored centrally and accessible instantly
- **Live updates** — the doctor's queue and the patient's appointments and records refresh every 10 s while open, so a booking or a saved visit shows up on the other side without a manual refresh
- **File uploads** — scanned lab reports and prescriptions stored securely in the cloud
- **Push notifications** — automated appointment reminders via Firebase Cloud Messaging
- **Role-based access** — separate views for patients, doctors, and clinic admins
- **Multilingual UI** — accessible to workers across different regional languages

---

## Tech stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart), Riverpod, go_router |
| Backend API | Node.js, Express |
| Database | PostgreSQL (Google Cloud SQL) |
| Authentication | Firebase Authentication (Phone OTP) |
| File storage | Google Cloud Storage |
| Push notifications | Firebase Cloud Messaging (FCM) |
| Containerization | Docker |
| Deployment | Google Cloud Run |
| CI/CD | GitHub Actions |
| Monitoring | Google Cloud Monitoring & Logging |

---

## System architecture

```
Flutter Mobile App
        │
        ▼  HTTPS / REST
   Cloud Run (Node.js API)
        │
   ┌────┼────────┬─────────────┐
   ▼    ▼        ▼             ▼
Cloud  Cloud   Firebase       FCM
 SQL  Storage    Auth      (reminders)
```

The mobile app never talks to the database, storage, or auth services directly — every request goes through the Cloud Run API, which is the single point of control for authorization, validation, and business logic.

---

## Database schema

Core entities: `Patient`, `Doctor`, `Clinic`, `Appointment`, `MedicalRecord`, `Prescription`.

- One **Patient** → many **Appointments** and **MedicalRecords**
- One **Clinic** → many **Doctors** and **Appointments**
- One **MedicalRecord** → many **Prescriptions**

Full schema with field types and constraints is documented in [`docs/database-schema.md`](docs/database-schema.md).

---

## Project structure

```
project-root/
├── mobile_app/             # Flutter app (Android + web for the clinic side)
│   └── lib/
│       ├── core/            # constants, theme, utils
│       ├── data/             # models, repositories, services
│       ├── providers/        # Riverpod state providers
│       ├── presentation/     # screens and widgets
│       └── routes/           # go_router config
├── backend/                # Node.js + Express API
│   ├── routes/
│   ├── controllers/
│   ├── models/
│   └── middleware/
├── docs/                    # diagrams, schema, reports
├── .github/workflows/       # CI/CD pipeline definitions
├── Dockerfile
└── README.md
```

---

## Getting started

### Prerequisites
- Flutter SDK
- Node.js (v18+)
- Docker
- Google Cloud SDK (`gcloud` CLI)
- A Firebase project (for Auth and FCM)

### Backend setup
```bash
cd backend
npm install
cp .env.example .env      # fill in your credentials
npm run dev
```

### Mobile app setup
```bash
cd mobile_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<host>:3000/api
```
`API_BASE_URL` defaults to `http://localhost:3000/api`. Release builds only accept an `https://` URL, so run debug or `--profile` builds locally.

### Running the doctor portal locally (web)
The clinic side (doctor/admin) is built for a PC browser. Keep the window at least 800 px wide to get the side navigation.

1. **Backend:** `cd backend && npm run dev`
2. **Patient app** at http://localhost:5000: run `cd mobile_app && flutter run -d web-server --web-port 5000`, click *Continue as guest* and register.
3. **Doctor portal** at http://localhost:5001: build with `cd mobile_app && flutter build web --profile`, then serve it with `python3 -m http.server 5001 --directory build/web`. Open it in a **separate browser profile or a private window**, because Firebase keeps one login per browser.
4. **Test doctor login:** phone `9999900001`, OTP `123456`. This needs three things:
   - In the Firebase console, go to Authentication → Sign-in method → Phone → *Phone numbers for testing* and add `+91 9999900001` with code `123456`.
   - Authentication → Settings → *SMS region policy* must allow India.
   - A doctor with that phone must exist. An admin can add one in the admin portal, or an API client can call `POST /api/doctors`. The first login with that number links the account as DOCTOR. To turn an existing account into a doctor instead, run `node backend/scripts/set-user-role.js <phone> DOCTOR "<name>" "<specialization>"`.
5. **The flow:**
   - The patient books *Central Migrant Health Hub* → the doctor, for today.
   - The appointment appears in the doctor's queue within about 10 s.
   - The doctor opens it and saves the visit (Ctrl+Enter), which marks the appointment completed.
   - The patient's *My Appointments* and *Health Records* show the update within about 10 s.
   - **Walk-ins:** a doctor can also open *Patient Lookup*, find the patient and click **Walk-in**. This creates a confirmed appointment for right now, puts it in the doctor's queue, and shows it in the patient's *My Appointments*. The snackbar's *Start visit* opens the visit form for that appointment.

---

## Environment variables

Create a `.env` file in `/backend` with:

```
DATABASE_URL=your_cloud_sql_connection_string
FIREBASE_PROJECT_ID=your_firebase_project_id
GCS_BUCKET_NAME=your_storage_bucket_name
PORT=8080
```

Never commit `.env` files — `.gitignore` is already configured to exclude them.

---

## CI/CD pipeline

On every push to `main`:
1. GitHub Actions installs dependencies and runs backend tests
2. Builds a Docker image of the backend
3. Pushes the image to Google Artifact Registry
4. Deploys automatically to Google Cloud Run

Pipeline definition: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)

---

## Cloud computing concepts demonstrated

This project was built as a **Cloud Computing domain mini project**, and intentionally demonstrates:

- **PaaS** — Cloud Run for backend hosting, no server management
- **DBaaS** — Cloud SQL as a managed relational database
- **SaaS-consumption** — Firebase Auth, FCM, and Cloud Storage as fully managed services
- **Elasticity** — Cloud Run auto-scales backend instances based on load
- **Multi-tenancy** — a single cloud backend serves multiple independent clinics
- **CI/CD automation** — GitHub Actions handles build, test, and deploy with zero manual steps
- **Cloud monitoring & observability** — centralized logs and metrics via Cloud Monitoring

---

## Roadmap

- [ ] Offline-first sync for low-connectivity areas
- [ ] Terraform scripts for infrastructure-as-code
- [ ] Admin analytics dashboard (patient footfall, disease trends)
- [ ] Multi-language voice input for low-literacy users

---

## Author

Developed as a Semester 5 mini project — Cloud Computing domain.

*Feel free to open an issue or reach out with questions about the architecture or setup.*
