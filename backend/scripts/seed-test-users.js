// scripts/seed-test-users.js
// ============================================================
// Seeds the `users` table with ADMIN and PATIENT test accounts
// using the pg driver directly (no psql / Docker needed).
//
// Usage:
//   node scripts/seed-test-users.js
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

const ADMIN_UID   = process.env.TEST_ADMIN_UID;
const PATIENT_UID = process.env.TEST_PATIENT_UID;

async function seed() {
  const client = await pool.connect();
  try {
    console.log('\n🌱  Seeding test users into the database...\n');

    // ── Remove existing rows (safe to re-run) ─────────────────
    await client.query(`
      DELETE FROM users
      WHERE firebase_uid = ANY($1::text[])
    `, [[ADMIN_UID, PATIENT_UID]]);
    console.log('   ✔  Removed any existing test rows.');

    // ── Insert ADMIN ──────────────────────────────────────────
    await client.query(`
      INSERT INTO users (id, firebase_uid, phone, role, created_at)
      VALUES (gen_random_uuid(), $1, $2, 'ADMIN', NOW())
    `, [ADMIN_UID, '+60100000001']);
    console.log(`   ✔  Inserted ADMIN  → UID: ${ADMIN_UID}`);

    // ── Insert PATIENT ────────────────────────────────────────
    await client.query(`
      INSERT INTO users (id, firebase_uid, phone, role, created_at)
      VALUES (gen_random_uuid(), $1, $2, 'PATIENT', NOW())
    `, [PATIENT_UID, '+60100000002']);
    console.log(`   ✔  Inserted PATIENT → UID: ${PATIENT_UID}`);

    // ── Verify ────────────────────────────────────────────────
    const { rows } = await client.query(`
      SELECT firebase_uid, phone, role
      FROM users
      WHERE firebase_uid = ANY($1::text[])
      ORDER BY role
    `, [[ADMIN_UID, PATIENT_UID]]);

    console.log('\n📋  Verification — rows in DB:\n');
    console.table(rows);
    console.log('\n✅  Seeding complete!\n');
  } catch (err) {
    console.error('\n❌  Seed failed:', err.message);
    if (err.message.includes('relation "users" does not exist')) {
      console.error('   → Run your Prisma migrations first:');
      console.error('     npx prisma migrate deploy\n');
    }
  } finally {
    client.release();
    await pool.end();
  }
}

seed();
