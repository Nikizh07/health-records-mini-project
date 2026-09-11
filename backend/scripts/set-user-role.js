// backend/scripts/set-user-role.js
// ============================================================
// Switch a user account's role (PATIENT, DOCTOR, ADMIN) by phone number
//
// Usage:
//   node scripts/set-user-role.js <phone_number> <ROLE> [Doctor_Name] [Specialization]
//
// Examples:
//   node scripts/set-user-role.js +919876543210 DOCTOR "Dr. Ramesh Kumar" "General Medicine"
//   node scripts/set-user-role.js +919876543210 PATIENT
//   node scripts/set-user-role.js +919876543210 ADMIN
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const prisma = require('../config/prisma');

async function setRole() {
  const args = process.argv.slice(2);
  const phone = args[0];
  const targetRole = args[1]?.toUpperCase();
  const doctorName = args[2] || 'Dr. Medical Practitioner';
  const specialization = args[3] || 'General Medicine & Occupational Health';

  if (!phone || !targetRole || !['PATIENT', 'DOCTOR', 'ADMIN'].includes(targetRole)) {
    console.log('\n❌ Usage: node scripts/set-user-role.js <phone> <PATIENT|DOCTOR|ADMIN> [Doctor_Name] [Specialization]');
    console.log('   Example: node scripts/set-user-role.js +919876543210 DOCTOR "Dr. Ramesh Kumar" "Cardiology"\n');
    process.exit(1);
  }

  try {
    console.log(`\n🔍 Looking up user with phone: ${phone}...`);

    // Standardize phone format if needed
    let formattedPhone = phone.trim();
    if (!formattedPhone.startsWith('+')) {
      formattedPhone = `+91${formattedPhone}`;
    }

    let user = await prisma.user.findFirst({
      where: {
        OR: [
          { phone: formattedPhone },
          { phone: phone },
        ],
      },
      include: {
        doctor: true,
        patient: true,
      },
    });

    if (!user) {
      console.log(`❌ User with phone ${phone} not found in database.`);
      console.log('   Make sure you have logged in via the mobile app with this number at least once.');
      process.exit(1);
    }

    console.log(`✅ Found user: ID = ${user.id}, Current Role = ${user.role}`);

    // Update User Role
    const updatedUser = await prisma.user.update({
      where: { id: user.id },
      data: { role: targetRole },
    });

    // If changing to DOCTOR, ensure a Doctor record exists and is linked
    if (targetRole === 'DOCTOR') {
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
          data: {
            name: doctorName,
            specialization: specialization,
            clinic_id: clinic.id,
          },
        });
        console.log(`   👨‍⚕️ Updated linked Doctor profile for ${doctorName}`);
      } else {
        await prisma.doctor.create({
          data: {
            user_id: user.id,
            clinic_id: clinic.id,
            name: doctorName,
            specialization: specialization,
            phone: user.phone,
          },
        });
        console.log(`   👨‍⚕️ Created & linked new Doctor profile for ${doctorName}`);
      }
    }

    console.log(`\n🎉 User ${user.phone} successfully updated to role: [${updatedUser.role}]!`);
    console.log('   When you next open or refresh the mobile app, it will display the Doctor portal.\n');
  } catch (error) {
    console.error('❌ Error setting user role:', error.message);
  } finally {
    await prisma.$disconnect();
  }
}

setRole();
