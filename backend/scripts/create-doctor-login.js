require('dotenv').config({ path: '../.env' });
const { auth } = require('../config/firebase');
const prisma = require('../config/prisma');

async function main() {
  const email = 'ananya@clinic.com';
  const password = 'password123';
  const phone = '+60123451004';
  
  let fbUser;
  try {
    fbUser = await auth.getUserByEmail(email);
    console.log('Firebase user exists.');
  } catch (e) {
    fbUser = await auth.createUser({
      email,
      password,
      emailVerified: true
    });
    console.log('Firebase user created.');
  }

  const doctor = await prisma.doctor.findFirst({ where: { phone } });
  if (!doctor) {
    console.log('Doctor not found!');
    return;
  }

  let user = await prisma.user.findFirst({ where: { email } });
  if (!user) {
    user = await prisma.user.create({
      data: {
        firebase_uid: fbUser.uid,
        email: email,
        role: 'DOCTOR',
        clinic_id: doctor.clinic_id
      }
    });
  } else {
    await prisma.user.update({
      where: { id: user.id },
      data: { role: 'DOCTOR', clinic_id: doctor.clinic_id }
    });
  }

  await prisma.doctor.update({
    where: { id: doctor.id },
    data: { user_id: user.id, email: email }
  });

  console.log('Done! You can now login with email: ananya@clinic.com, password: password123');
  process.exit(0);
}
main().catch(console.error);
