-- CreateEnum
CREATE TYPE "ConsentMethod" AS ENUM ('APP', 'CODE', 'EMERGENCY');

-- CreateEnum
CREATE TYPE "ConsentStatus" AS ENUM ('PENDING', 'APPROVED', 'DENIED', 'EXPIRED', 'REVOKED');

-- CreateEnum
CREATE TYPE "AccessVia" AS ENUM ('SELF', 'CARE', 'CONSENT', 'EMERGENCY');

-- CreateTable
CREATE TABLE "consent_requests" (
    "id" UUID NOT NULL,
    "patient_id" UUID NOT NULL,
    "doctor_id" UUID,
    "clinic_id" UUID,
    "method" "ConsentMethod" NOT NULL,
    "status" "ConsentStatus" NOT NULL,
    "reason" TEXT,
    "code_hash" TEXT,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "granted_until" TIMESTAMP(3),
    "responded_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "consent_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "patient_access_logs" (
    "id" UUID NOT NULL,
    "patient_id" UUID NOT NULL,
    "user_id" UUID,
    "clinic_id" UUID,
    "via" "AccessVia" NOT NULL,
    "consent_id" UUID,
    "appointment_id" UUID,
    "action" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "patient_access_logs_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "consent_requests_patient_id_doctor_id_status_idx" ON "consent_requests"("patient_id", "doctor_id", "status");

-- CreateIndex
CREATE INDEX "patient_access_logs_patient_id_idx" ON "patient_access_logs"("patient_id");

-- CreateIndex
CREATE INDEX "patient_access_logs_clinic_id_idx" ON "patient_access_logs"("clinic_id");

-- AddForeignKey
ALTER TABLE "consent_requests" ADD CONSTRAINT "consent_requests_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "patients"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "consent_requests" ADD CONSTRAINT "consent_requests_doctor_id_fkey" FOREIGN KEY ("doctor_id") REFERENCES "doctors"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "consent_requests" ADD CONSTRAINT "consent_requests_clinic_id_fkey" FOREIGN KEY ("clinic_id") REFERENCES "clinics"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patient_access_logs" ADD CONSTRAINT "patient_access_logs_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "patients"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patient_access_logs" ADD CONSTRAINT "patient_access_logs_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patient_access_logs" ADD CONSTRAINT "patient_access_logs_consent_id_fkey" FOREIGN KEY ("consent_id") REFERENCES "consent_requests"("id") ON DELETE SET NULL ON UPDATE CASCADE;

