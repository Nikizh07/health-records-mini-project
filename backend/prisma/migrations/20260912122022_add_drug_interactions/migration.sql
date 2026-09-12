-- CreateEnum
CREATE TYPE "InteractionSeverity" AS ENUM ('MINOR', 'MODERATE', 'MAJOR', 'CRITICAL');

-- CreateTable
CREATE TABLE "drug_interactions" (
    "id" UUID NOT NULL,
    "drug_a" TEXT NOT NULL,
    "drug_b" TEXT NOT NULL,
    "severity" "InteractionSeverity" NOT NULL,
    "mechanism" TEXT NOT NULL,
    "suggested_alternative" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "drug_interactions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "interaction_checks" (
    "id" UUID NOT NULL,
    "patient_id" UUID NOT NULL,
    "doctor_id" UUID NOT NULL,
    "record_id" UUID,
    "checked_drugs" JSONB NOT NULL,
    "conflicts" JSONB NOT NULL,
    "ai_available" BOOLEAN NOT NULL DEFAULT false,
    "ai_provider" TEXT,
    "overridden" BOOLEAN NOT NULL DEFAULT false,
    "override_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "interaction_checks_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "drug_interactions_drug_a_idx" ON "drug_interactions"("drug_a");

-- CreateIndex
CREATE INDEX "drug_interactions_drug_b_idx" ON "drug_interactions"("drug_b");

-- CreateIndex
CREATE UNIQUE INDEX "drug_interactions_drug_a_drug_b_key" ON "drug_interactions"("drug_a", "drug_b");

-- CreateIndex
CREATE INDEX "interaction_checks_patient_id_idx" ON "interaction_checks"("patient_id");

-- AddForeignKey
ALTER TABLE "interaction_checks" ADD CONSTRAINT "interaction_checks_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "patients"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "interaction_checks" ADD CONSTRAINT "interaction_checks_doctor_id_fkey" FOREIGN KEY ("doctor_id") REFERENCES "doctors"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "interaction_checks" ADD CONSTRAINT "interaction_checks_record_id_fkey" FOREIGN KEY ("record_id") REFERENCES "medical_records"("id") ON DELETE SET NULL ON UPDATE CASCADE;
