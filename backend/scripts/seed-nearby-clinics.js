// backend/scripts/seed-nearby-clinics.js
// ============================================================
// Seeds or updates sample clinics with realistic GPS coordinates
// and attaches doctors to ensure testing the sorted booking flow works.
//
// Usage:
//   node scripts/seed-nearby-clinics.js
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const prisma = require('../config/prisma');

const SAMPLE_CLINICS = [
  {
    name: 'Central Migrant Health Hub',
    location: 'Sector 4, Central Industrial Estate',
    contact_number: '+60123450001',
    latitude: 1.3329,
    longitude: 103.7436,
    doctor: {
      name: 'Dr. Sarah Tan',
      specialization: 'General Medicine & Occupational Health',
      phone: '+60123451001',
    },
  },
  {
    name: 'West Coast Community Care Clinic',
    location: 'Dormitory Zone 2, West Coast',
    contact_number: '+60123450002',
    latitude: 1.2915,
    longitude: 103.7650,
    doctor: {
      name: 'Dr. Rajiv Menon',
      specialization: 'Pulmonology & Respiratory Care',
      phone: '+60123451002',
    },
  },
  {
    name: 'Puchong Industrial Worker Medical Center',
    location: 'Plot 18, Puchong Tech Park',
    contact_number: '+60123450003',
    latitude: 1.3521,
    longitude: 103.8198,
    doctor: {
      name: 'Dr. Li Wei',
      specialization: 'Dermatology & Wound Care',
      phone: '+60123451003',
    },
  },
  {
    name: 'Tuas South Regional Health Centre',
    location: 'Tuas Mega Marine Yard, Pier 7',
    contact_number: '+60123450004',
    latitude: 1.2420,
    longitude: 103.6350,
    doctor: {
      name: 'Dr. Ananya Sharma',
      specialization: 'General Practice & Trauma Care',
      phone: '+60123451004',
    },
  },
];

async function seedClinics() {
  console.log('\n🏥  Seeding sample clinics with GPS coordinates...\n');

  try {
    for (const data of SAMPLE_CLINICS) {
      // Find existing clinic by name or create new
      let clinic = await prisma.clinic.findFirst({
        where: { name: data.name },
      });

      if (!clinic) {
        clinic = await prisma.clinic.create({
          data: {
            name: data.name,
            location: data.location,
            contact_number: data.contact_number,
            latitude: data.latitude,
            longitude: data.longitude,
          },
        });
        console.log(`   ✔  Created Clinic: "${clinic.name}" at (${clinic.latitude}, ${clinic.longitude})`);
      } else {
        clinic = await prisma.clinic.update({
          where: { id: clinic.id },
          data: {
            location: data.location,
            contact_number: data.contact_number,
            latitude: data.latitude,
            longitude: data.longitude,
          },
        });
        console.log(`   ✔  Updated Clinic: "${clinic.name}" at (${clinic.latitude}, ${clinic.longitude})`);
      }

      // Ensure doctor exists for this clinic
      const existingDoc = await prisma.doctor.findFirst({
        where: {
          OR: [
            { phone: data.doctor.phone },
            { clinic_id: clinic.id, name: data.doctor.name },
          ],
        },
      });

      if (!existingDoc) {
        await prisma.doctor.create({
          data: {
            clinic_id: clinic.id,
            name: data.doctor.name,
            specialization: data.doctor.specialization,
            phone: data.doctor.phone,
          },
        });
        console.log(`      ↳ Attached Doctor: ${data.doctor.name} (${data.doctor.specialization})`);
      } else {
        console.log(`      ↳ Doctor exists: ${existingDoc.name}`);
      }
    }

    console.log('\n✅  Clinics with GPS coordinates seeded successfully!\n');
  } catch (err) {
    console.error('❌  Failed to seed clinics:', err);
  } finally {
    await prisma.$disconnect();
  }
}

seedClinics();
