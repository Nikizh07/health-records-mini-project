-- AlterTable
ALTER TABLE "patients" ADD COLUMN     "claim_failures" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "claim_locked_until" TIMESTAMP(3),
ADD COLUMN     "registered_by_user_id" UUID;
