// backend/scripts/set-user-role.js
// ============================================================
// Set a user account's role by phone number or email
//
// Usage:
//   node scripts/set-user-role.js <phone|email> PATIENT|ADMIN
//   node scripts/set-user-role.js <phone|email> DOCTOR [Doctor_Name] [Specialization]
//   node scripts/set-user-role.js <phone|email> CLINIC_ADMIN|RECEPTIONIST <clinic_id>
//
// Examples:
//   node scripts/set-user-role.js +919876543210 DOCTOR "Dr. Ramesh Kumar" "General Medicine"
//   node scripts/set-user-role.js admin@example.com ADMIN
//   node scripts/set-user-role.js desk@example.com RECEPTIONIST 3f1c...-uuid
//
// The account must have signed in once (in Firebase). If it has no users row
// yet, one is created from the Firebase account.
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const prisma = require('../config/prisma');
const { toE164 } = require('../utils/phone');

const ROLES = ['PATIENT', 'RECEPTIONIST', 'DOCTOR', 'CLINIC_ADMIN', 'ADMIN'];
const CLINIC_ROLES = ['RECEPTIONIST', 'CLINIC_ADMIN'];

function usage() {
  console.log('\n❌ Usage: node scripts/set-user-role.js <phone|email> <ROLE> [...]');
  console.log('   PATIENT|ADMIN');
  console.log('   DOCTOR [Doctor_Name] [Specialization]');
  console.log('   CLINIC_ADMIN|RECEPTIONIST <clinic_id>\n');
  process.exit(1);
}

async function setRole() {
  const [identifier, rawRole, arg3, arg4] = process.argv.slice(2);
  const targetRole = rawRole?.toUpperCase();
  if (!identifier || !ROLES.includes(targetRole)) usage();
  if (CLINIC_ROLES.includes(targetRole) && !arg3) usage();

  const email = identifier.includes('@') ? identifier.trim().toLowerCase() : null;
  // guest-<uid> placeholders (debug guest accounts) are matched as they are.
  const phone = email ? null : toE164(identifier) || (identifier.startsWith('guest-') ? identifier : null);
  if (!email && !phone) {
    console.log(`❌ "${identifier}" is neither an email nor a phone number with a country code.`);
    process.exit(1);
  }

  try {
    console.log(`\n🔍 Looking up user ${email || phone}...`);
    let user = await prisma.user.findFirst({
      where: email ? { email } : { phone },
      include: { doctor: true },
    });

    if (!user) {
      const { auth } = require('../config/firebase');
      let fbUser;
      try {
        fbUser = email ? await auth.getUserByEmail(email) : await auth.getUserByPhoneNumber(phone);
      } catch (_) {
        console.log(`❌ No account for ${email || phone} in the database or in Firebase.`);
        console.log('   Sign in once in the app with this phone/email first.');
        process.exit(1);
      }
      user = await prisma.user.create({
        data: { firebase_uid: fbUser.uid, phone: fbUser.phoneNumber || null, email: fbUser.email || null },
        include: { doctor: true },
      });
      console.log(`   ➕ Created users row from Firebase account ${fbUser.uid}`);
    }

    console.log(`✅ Found user: ID = ${user.id}, Current Role = ${user.role}`);

    let clinicId = null;
    if (CLINIC_ROLES.includes(targetRole)) {
      const clinic = await prisma.clinic.findUnique({ where: { id: arg3 } }).catch(() => null);
      if (!clinic) {
        console.log(`❌ Clinic "${arg3}" not found.`);
        process.exit(1);
      }
      clinicId = clinic.id;
    }

    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: { role: targetRole, clinic_id: clinicId },
    });

    // If changing to DOCTOR, ensure a Doctor record exists and is linked
    if (targetRole === 'DOCTOR') {
      const doctorName = arg3 || 'Dr. Medical Practitioner';
      const specialization = arg4 || 'General Medicine & Occupational Health';
      let clinic = await prisma.clinic.findFirst();
      if (!clinic) {
        clinic = await prisma.clinic.create({
          data: {
            name: 'Central Migrant Worker Health Clinic',
            location: 'Sector 4, Industrial Zone',
            contact_number: '+919999999999',
          },
        });
        console.log(`   🏥 Created default clinic: ${clinic.name}`);
      }

      if (user.doctor) {
        await prisma.doctor.update({
          where: { id: user.doctor.id },
          data: { name: doctorName, specialization, clinic_id: clinic.id },
        });
        console.log(`   👨‍⚕️ Updated linked Doctor profile for ${doctorName}`);
      } else {
        await prisma.doctor.create({
          data: {
            user_id: user.id,
            clinic_id: clinic.id,
            name: doctorName,
            specialization,
            phone: user.phone,
            email: user.email,
          },
        });
        console.log(`   👨‍⚕️ Created & linked new Doctor profile for ${doctorName}`);
      }
    }

    console.log(`\n🎉 User ${user.email || user.phone} successfully updated to role: [${updatedUser.role}]!`);
    console.log('   Refresh the app to pick up the new role.\n');
  } catch (error) {
    console.error('❌ Error setting user role:', error.message);
  } finally {
    await prisma.$disconnect();
  }
}

setRole();
