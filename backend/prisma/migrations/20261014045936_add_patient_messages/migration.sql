-- CreateEnum
CREATE TYPE "MessageStatus" AS ENUM ('QUEUED', 'SENT', 'DELIVERED', 'FAILED');

-- AlterTable
ALTER TABLE "patients" ADD COLUMN     "whatsapp_opt_in" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "whatsapp_opt_in_at" TIMESTAMP(3);

-- CreateTable
CREATE TABLE "patient_messages" (
    "id" UUID NOT NULL,
    "record_id" UUID NOT NULL,
    "patient_id" UUID NOT NULL,
    "doctor_id" UUID NOT NULL,
    "language" TEXT NOT NULL,
    "status" "MessageStatus" NOT NULL DEFAULT 'QUEUED',
    "provider" TEXT,
    "provider_message_id" TEXT,
    "error" TEXT,
    "payload" JSONB NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "sent_at" TIMESTAMP(3),

    CONSTRAINT "patient_messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "patient_messages_record_id_idx" ON "patient_messages"("record_id");

-- CreateIndex
CREATE INDEX "patient_messages_patient_id_idx" ON "patient_messages"("patient_id");

-- CreateIndex
CREATE INDEX "patient_messages_status_idx" ON "patient_messages"("status");

-- AddForeignKey
ALTER TABLE "patient_messages" ADD CONSTRAINT "patient_messages_record_id_fkey" FOREIGN KEY ("record_id") REFERENCES "medical_records"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patient_messages" ADD CONSTRAINT "patient_messages_patient_id_fkey" FOREIGN KEY ("patient_id") REFERENCES "patients"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patient_messages" ADD CONSTRAINT "patient_messages_doctor_id_fkey" FOREIGN KEY ("doctor_id") REFERENCES "doctors"("id") ON DELETE CASCADE ON UPDATE CASCADE;
