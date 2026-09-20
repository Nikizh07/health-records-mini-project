# Plan: Move backend, DB and storage from GCP → AWS (Firebase unchanged)

## Status (2026-09-19)
- ✅ **§2 Backend code** — done and verified locally.
- ✅ **§3 CI/CD** — done. The workflow also gained the `.yml` extension it was missing, so it will actually run now.
- ✅ **§5 Mobile** — nothing to change; confirmed the app already passes absolute URLs through.
- ✅ **§6 Docs** — `README.md`, `ARCHITECTURE.md`, `SNAPSHOT.md`, `MEMORY.md` updated.
- ⬜ **§1 AWS infrastructure** — needs an AWS account; none of it is code. Do this next.
- ⬜ **§4 Data migration** — nothing to migrate. The local DB is seed/test data and the single test PDF was deleted with the `uploads/` folder.
- ⬜ **Verification steps 2-6 below** — they all need live AWS resources. Steps done locally instead: `/api/health` returns 200, `/uploads/...` is now 404, both regression suites pass (302 + 112), `scripts/test-s3-signing.js` passes, and an intercepted end-to-end upload proved the key/bucket/signing wiring. The Docker image build was **not** confirmed — the `node:22-slim` pull kept timing out on this network. The CA-bundle URL the Dockerfile fetches was checked separately and returns 108 certificates. Run `docker build -t mcb backend/` once the network allows.

After §1, set these repository settings for the deploy workflow: secret `AWS_ROLE_ARN`; variables `AWS_REGION`, `ECS_CLUSTER`, `ECS_SERVICE`.

## Context
The project is branded as GCP (Cloud Run + Cloud SQL + GCS), but the code is barely tied to GCP:
- **DB**: plain Postgres via `DATABASE_URL` (Prisma 7 + `@prisma/adapter-pg`) — no Cloud SQL connector.
- **Storage**: GCS was never implemented. Uploads go to local disk (`backend/middleware/upload.js`) and are served from `/uploads` in `server.js`. That breaks on any container host (the files disappear on restart) and the app can't open the relative `/uploads/...` URL anyway (`record_detail_screen.dart:27` calls `launchUrl` on it directly).
- **Backend hosting**: CI only pushes an image to GHCR. There's no Cloud Run deploy step.
- **Firebase Admin** in `config/firebase.js` falls back to Google ADC when the JSON key is missing. The key is excluded by `.dockerignore`, so on AWS the fallback **will fail** unless the key is injected as a secret.

Goal: Postgres on **RDS**, reports in a **private S3 bucket** (served by presigned URLs), backend container on **ECS Fargate**, and Firebase Auth/Admin exactly as it is now.

Suggested region: `ap-south-1` (Mumbai), since the users are in India (hi/ta locales), which keeps the health data in-country.

---

## 1. AWS infrastructure (console or CLI, one-time)
1. **VPC**: use the default VPC. Create 2 security groups:
   - `sg-app`: inbound 80/443 from the internet (via the load balancer).
   - `sg-db`: inbound 5432 **only from `sg-app`**.
2. **RDS PostgreSQL 16**: `db.t4g.micro`, 20 GB gp3, not publicly accessible, `sg-db`, encryption at rest on, automated backups on. DB name `migrant_clinic_db`.
3. **S3 bucket** `migrant-clinic-reports-<suffix>`: Block Public Access ON, SSE-S3 encryption, versioning optional.
4. **ECR repo** `migrant-clinic-backend`.
5. **Secrets Manager**:
   - `DATABASE_URL` = `postgresql://USER:PASS@<rds-endpoint>:5432/migrant_clinic_db?sslmode=verify-full&sslrootcert=/app/certs/rds-global-bundle.pem`
   - `FIREBASE_SERVICE_ACCOUNT_JSON` = full contents of `firebase-adminsdk.json`
6. **IAM**:
   - ECS **task role**: `s3:PutObject`, `s3:GetObject` on `arn:aws:s3:::<bucket>/reports/*`. This means no access keys in env.
   - If the drug-interaction AI leg runs on Bedrock or SageMaker (`AI_PROVIDER`, see `thinking-archive/AI_DRUG_INTERACTION_PLAN.md` Phase 4), the same task role also needs `bedrock:InvokeModel` on the model ARN, or `sagemaker:InvokeEndpoint` on the endpoint ARN.
   - ECS **execution role**: `AmazonECSTaskExecutionRolePolicy` + `secretsmanager:GetSecretValue` on the 2 secrets.
   - **GitHub OIDC role** for CI: ECR push + `ecs:UpdateService`.
7. **ECS Fargate service** (use *ECS Express Mode* if your console offers it; it creates the ALB, HTTPS URL and autoscaling for you. Otherwise use a plain Fargate service behind an ALB with an ACM cert):
   - 0.25 vCPU / 0.5 GB, container port 3000, env `PORT=3000`, `NODE_ENV=production`, `AWS_REGION`, `S3_BUCKET_NAME`, secrets from step 5.
   - Health check path: `/api/health`.

## 2. Backend code changes (`backend/`)

| File | Change |
|---|---|
| `package.json` | Add `@aws-sdk/client-s3` and `@aws-sdk/s3-request-presigner`. Remove the `cloud-sql` keyword. |
| `config/s3.js` (new, ~20 lines) | Export the `S3Client`, `putReport(buffer, key, mimetype)`, and `signReport(record)`. `signReport` swaps `report_file_url` (an S3 key) for a 15-minute presigned GET URL, and leaves values starting with `http` untouched (seed data). |
| `middleware/upload.js` | `multer.diskStorage` → `multer.memoryStorage()`. Keep the MIME filter and 5 MB limit. Delete the mkdir block. |
| `controllers/record.controller.js` | `uploadReportFile`: build the key `reports/<recordId>/<timestamp>-<rand><ext>`, call `putReport`, and store the **key** in `report_file_url`. Wrap every returned record in `signReport(...)`: `getPatientMedicalHistory` (map over array), `getMedicalRecordById`, `uploadReportFile`. |
| `server.js` | Remove the `/uploads` static route and the `path` import. |
| `config/firebase.js` | Before the file check: if `FIREBASE_SERVICE_ACCOUNT_JSON` is set → `cert(JSON.parse(...))`. Keep the file path for local dev. Drop the ADC fallback, which can't work on AWS; fail loudly instead. |
| `config/db.js` | **Delete.** It's unused (nothing requires it) and duplicates the pool in `config/prisma.js`. |
| `config/prisma.js` | No change. SSL comes from `sslmode`/`sslrootcert` in `DATABASE_URL`, which `pg` parses natively. |
| `Dockerfile` | Download the RDS CA bundle: `ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /app/certs/rds-global-bundle.pem`. Remove the `mkdir uploads` line. Change CMD to `sh -c "npx prisma migrate deploy && node server.js"` so migrations run on deploy (prisma is already installed in the image). |
| `.env.example` | Replace the Cloud SQL/GCS sections with `DATABASE_URL` (RDS format), `AWS_REGION`, `S3_BUCKET_NAME`, `FIREBASE_SERVICE_ACCOUNT_JSON` (optional alternative to the path). |

The API contract stays the same: `report_file_url` is still a string in responses, but now it's an absolute HTTPS URL the app can actually open.

Presigned URLs expire, so a record screen left open for more than 15 minutes needs a refresh before the report opens. That's acceptable for now.

## 3. CI/CD (`.github/workflows/deploy-container.yml`)
Replace the GHCR login/push with:
1. `aws-actions/configure-aws-credentials@v4` (OIDC, `role-to-assume` = the CI role). Add `permissions: id-token: write`.
2. `aws-actions/amazon-ecr-login@v2`.
3. Build and push to `<acct>.dkr.ecr.<region>.amazonaws.com/migrant-clinic-backend:{sha,latest}` (keep the existing buildx cache).
4. `aws ecs update-service --cluster ... --service ... --force-new-deployment`.

Delete `scripts/push-docker-ghcr.ps1`, or leave it if you still want GHCR as a mirror.

## 4. Data migration (only if Cloud SQL has real data)
```
pg_dump --no-owner --no-acl -Fc "$CLOUD_SQL_URL" > dump.pgdump
pg_restore --no-owner -d "$RDS_URL" dump.pgdump
```
RDS is private, so run the restore from a temporary EC2/CloudShell-in-VPC, or open RDS to your IP briefly. If the DB is only seed/test data, skip this. `prisma migrate deploy` plus the existing `scripts/seed-*.js` rebuild it.

Local `backend/uploads/reports/` only holds 1 test PDF, so there's no file migration.

## 5. Mobile app
No code changes. Firebase config (`firebase_options.dart`, `google-services.json`) stays as is. Only build with the new URL:
```
flutter build apk --dart-define=API_BASE_URL=https://<ecs-express-or-alb-domain>/api
```

## 6. Docs
In `README.md`, change the badges and stack table from Cloud Run/Cloud SQL/GCS to ECS Fargate/RDS/S3, the prerequisites from `gcloud` to `aws` CLI, and the env var list. Update the stale comments in `upload.js` and `.env.example`.

---

## Verification
1. **Local**: `docker build -t mcb backend/` then `docker run` with `.env` pointing at local Postgres, plus `AWS_PROFILE`/creds and `S3_BUCKET_NAME` → `GET /api/health` returns 200.
2. **Upload path**: Postman collection (`backend/postman/`) → `POST /api/records/:id/upload` with a PDF → the object appears under `reports/<id>/` in S3, and the returned `file_url` opens in a browser. Wait 15 min → the URL returns 403 (expiry works).
3. **Bucket is private**: the plain `https://<bucket>.s3.amazonaws.com/reports/...` URL returns AccessDenied.
4. **Deploy**: push to `main` → Actions runs green → ECS task logs show `migrate deploy` applied, `✅ Firebase Admin SDK initialized with Service Account Key`, and the server listening.
5. **Prod**: `curl https://<domain>/api/health`. Log in via the Flutter app built with the new `API_BASE_URL` (Firebase auth unchanged) → book an appointment, have a doctor upload a report, the patient opens it from the record detail screen.
6. **DB TLS**: RDS enforces SSL by default (`rds.force_ssl=1`). A successful connect with `verify-full` proves the cert chain is right.
