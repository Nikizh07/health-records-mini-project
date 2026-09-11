-- ============================================================
-- scripts/seed-test-users.sql
-- Seeds the `users` table with ADMIN and PATIENT test accounts
-- that match the Firebase UIDs from your migrant-workers-89bb8 project.
--
-- Run this in pgAdmin Query Tool or psql:
--   psql -U postgres -d migrant_clinic_db -f seed-test-users.sql
-- ============================================================

-- Remove existing test rows first (safe to re-run)
DELETE FROM users WHERE firebase_uid IN (
  'pCn8nXOSuHTE7IIzFCq9qbntPr83',
  'hnn3PouhqbaC0FGKTwvCJVvcAow1'
);

-- Insert ADMIN user
INSERT INTO users (id, firebase_uid, phone, role, created_at)
VALUES (
  gen_random_uuid(),
  'pCn8nXOSuHTE7IIzFCq9qbntPr83',
  '+60100000001',
  'ADMIN',
  NOW()
);

-- Insert PATIENT user
INSERT INTO users (id, firebase_uid, phone, role, created_at)
VALUES (
  gen_random_uuid(),
  'hnn3PouhqbaC0FGKTwvCJVvcAow1',
  '+60100000002',
  'PATIENT',
  NOW()
);

-- Verify
SELECT id, firebase_uid, phone, role, created_at
FROM users
WHERE firebase_uid IN (
  'pCn8nXOSuHTE7IIzFCq9qbntPr83',
  'hnn3PouhqbaC0FGKTwvCJVvcAow1'
)
ORDER BY role;
