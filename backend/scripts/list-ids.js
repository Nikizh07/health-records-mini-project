// backend/scripts/list-ids.js
// ============================================================
// Quick helper to view and copy Clinic, Doctor, and Patient IDs
// Run: node backend/scripts/list-ids.js (from project root or backend folder)
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const prisma = require('../config/prisma');

async function main() {
  console.log('\n======================================================');
  console.log('📋 CLINICS, DOCTORS & PATIENTS IN DATABASE');
  console.log('======================================================\n');

  try {
    // 1. Clinics
    const clinics = await prisma.clinic.findMany();
    console.log(`🏥 Clinics (${clinics.length}):`);
    if (clinics.length === 0) {
      console.log('   (No clinics found. Create one using POST /api/clinics)');
    } else {
      console.table(clinics.map(c => ({
        clinic_id: c.id,
        name: c.name,
        location: c.location,
      })));
    }

    // 2. Doctors
    const doctors = await prisma.doctor.findMany({
      include: { clinic: true },
    });
    console.log(`\n👨‍⚕️ Doctors (${doctors.length}):`);
    if (doctors.length === 0) {
      console.log('   (No doctors found. Create one using POST /api/doctors)');
    } else {
      console.table(doctors.map(d => ({
        doctor_id: d.id,
        name: d.name,
        specialization: d.specialization,
        clinic_id: d.clinic_id,
        clinic_name: d.clinic?.name || 'N/A',
      })));
    }

    // 3. Patients
    const patients = await prisma.patient.findMany();
    console.log(`\n🧑 Patients (${patients.length}):`);
    if (patients.length === 0) {
      console.log('   (No patients found. Create one using POST /api/patients)');
    } else {
      console.table(patients.map(p => ({
        patient_id: p.id,
        health_id: p.health_id,
        name: p.name,
        phone: p.phone,
      })));
    }

    console.log('\n======================================================\n');
  } catch (error) {
    console.error('❌ Error fetching data:', error.message);
  } finally {
    await prisma.$disconnect();
    process.exit(0);
  }
}

main();
