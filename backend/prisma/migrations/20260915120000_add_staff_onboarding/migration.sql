-- AlterTable
ALTER TABLE "doctors" ADD COLUMN     "registration_council" TEXT,
ADD COLUMN     "registration_number" TEXT,
ADD COLUMN     "verified_at" TIMESTAMP(3),
ADD COLUMN     "verified_by_id" UUID;

-- CreateTable
CREATE TABLE "staff_invites" (
    "id" UUID NOT NULL,
    "clinic_id" UUID NOT NULL,
    "role" "Role" NOT NULL,
    "email" TEXT,
    "phone" TEXT,
    "name" TEXT NOT NULL,
    "specialization" TEXT,
    "invited_by_id" UUID,
    "accepted_user_id" UUID,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "staff_invites_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "staff_invites_accepted_user_id_key" ON "staff_invites"("accepted_user_id");

-- CreateIndex
CREATE INDEX "staff_invites_email_idx" ON "staff_invites"("email");

-- CreateIndex
CREATE INDEX "staff_invites_phone_idx" ON "staff_invites"("phone");

-- AddForeignKey
ALTER TABLE "doctors" ADD CONSTRAINT "doctors_verified_by_id_fkey" FOREIGN KEY ("verified_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "staff_invites" ADD CONSTRAINT "staff_invites_clinic_id_fkey" FOREIGN KEY ("clinic_id") REFERENCES "clinics"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "staff_invites" ADD CONSTRAINT "staff_invites_invited_by_id_fkey" FOREIGN KEY ("invited_by_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "staff_invites" ADD CONSTRAINT "staff_invites_accepted_user_id_fkey" FOREIGN KEY ("accepted_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Data: doctors pre-created by an admin but never signed in used to be linked
-- by phone in GET /patients/me. That linking is now invite-only, so give each
-- of them an invite (90 days, longer than the normal 14, so nobody is stranded).
INSERT INTO "staff_invites" ("id", "clinic_id", "role", "email", "phone", "name", "specialization", "expires_at")
SELECT gen_random_uuid(), "clinic_id", 'DOCTOR', "email", "phone", "name", "specialization", NOW() + INTERVAL '90 days'
FROM "doctors"
WHERE "user_id" IS NULL;
