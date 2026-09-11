// backend/scripts/seed-sample-records.js
// ============================================================
// Seeds sample clinics, doctors, and medical records with
// prescriptions for all registered patients in the database.
//
// Usage:
//   node scripts/seed-sample-records.js
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const prisma = require('../config/prisma');

async function seedRecords() {
  console.log('\n🏥  Seeding sample clinic, doctor, and health records...\n');

  try {
    // 1. Ensure at least one Clinic exists
    let clinic = await prisma.clinic.findFirst();
    if (!clinic) {
      clinic = await prisma.clinic.create({
        data: {
          name: 'Migrant Community Health Center',
          location: 'Building 4, Industrial Zone Hub',
          contact_number: '+919876540001',
        },
      });
      console.log(`   ✔  Created Clinic: ${clinic.name}`);
    } else {
      console.log(`   ✔  Using existing Clinic: ${clinic.name}`);
    }

    // 2. Ensure at least one Doctor exists
    let doctor = await prisma.doctor.findFirst();
    if (!doctor) {
      doctor = await prisma.doctor.create({
        data: {
          clinic_id: clinic.id,
          name: 'Dr. Sarah Tan',
          specialization: 'General Medicine & Occupational Health',
          phone: '+919876540002',
        },
      });
      console.log(`   ✔  Created Doctor: ${doctor.name}`);
    } else {
      console.log(`   ✔  Using existing Doctor: ${doctor.name}`);
    }

    // 3. Find all registered patients
    const patients = await prisma.patient.findMany();
    if (patients.length === 0) {
      console.log('   ⚠️  No patients found in DB to attach records to.');
      return;
    }

    console.log(`\n📋  Found ${patients.length} patient(s). Creating sample records...`);

    for (const patient of patients) {
      // Check if patient already has records
      const existingCount = await prisma.medicalRecord.count({
        where: { patient_id: patient.id },
      });

      if (existingCount > 0) {
        console.log(`   ℹ️  Patient "${patient.name}" already has ${existingCount} record(s). Skipping duplicate seed.`);
        continue;
      }

      // Record 1: Upper Respiratory Infection
      await prisma.medicalRecord.create({
        data: {
          patient_id: patient.id,
          doctor_id: doctor.id,
          visit_date: new Date(Date.now() - 3 * 24 * 60 * 60 * 1000), // 3 days ago
          diagnosis: 'Acute Upper Respiratory Tract Infection (URTI) with mild fever',
          notes: 'Patient presented with sore throat, runny nose, and fatigue. Advised 3 days medical leave, high fluid intake, and steam inhalation.',
          report_file_url: 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
          prescriptions: {
            create: [
              {
                medicine_name: 'Amoxicillin 500mg',
                dosage: '1 capsule three times daily after meals',
                duration: '5 days',
              },
              {
                medicine_name: 'Paracetamol 650mg',
                dosage: '1 tablet every 6 hours as needed for fever/pain',
                duration: '3 days',
              },
              {
                medicine_name: 'Cetirizine 10mg',
                dosage: '1 tablet once daily at bedtime',
                duration: '5 days',
              },
            ],
          },
        },
      });

      // Record 2: Routine Health Check & Occupational Screening
      await prisma.medicalRecord.create({
        data: {
          patient_id: patient.id,
          doctor_id: doctor.id,
          visit_date: new Date(Date.now() - 21 * 24 * 60 * 60 * 1000), // 3 weeks ago
          diagnosis: 'Routine Occupational Health Screening & Mild Contact Dermatitis',
          notes: 'Vitals normal (BP: 120/80 mmHg, SpO2: 98%). Minor skin irritation observed on hands due to chemical exposure at workplace. Prescribed topical ointment and protective gloves.',
          prescriptions: {
            create: [
              {
                medicine_name: 'Hydrocortisone Cream 1%',
                dosage: 'Apply thin layer to affected skin twice daily',
                duration: '7 days',
              },
              {
                medicine_name: 'Vitamin B-Complex + Zinc',
                dosage: '1 tablet daily with breakfast',
                duration: '30 days',
              },
            ],
          },
        },
      });

      console.log(`   ✔  Created 2 clinical records + prescriptions for "${patient.name}" (${patient.health_id})`);
    }

    console.log('\n✅  Successfully seeded sample health records!\n');
  } catch (error) {
    console.error('❌  Error seeding records:', error);
  } finally {
    await prisma.$disconnect();
  }
}

seedRecords();
