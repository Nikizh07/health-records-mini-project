-- AlterTable
ALTER TABLE "prescriptions" ADD COLUMN     "food_relation" TEXT,
ADD COLUMN     "pills_per_dose" DOUBLE PRECISION,
ADD COLUMN     "prn" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "prn_condition" TEXT,
ADD COLUMN     "schedule_source" TEXT,
ADD COLUMN     "slots" TEXT[] DEFAULT ARRAY[]::TEXT[];
