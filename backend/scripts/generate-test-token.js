// backend/scripts/generate-test-token.js
// ============================================================
// Helper Script: Generate a Test Firebase ID Token for Postman
// ============================================================
// Usage:
//   node scripts/generate-test-token.js [FIREBASE_WEB_API_KEY] [UID] [PHONE]
// ============================================================

'use strict';

require('dotenv').config();
const { auth } = require('../config/firebase');

async function main() {
  const webApiKey = process.argv[2] || process.env.FIREBASE_WEB_API_KEY;
  const testUid = process.argv[3] || 'test-patient-uid-1001';
  const testPhone = process.argv[4] || '+919876543210';

  console.log('----------------------------------------------------');
  console.log('🔑 Generating Firebase Test Token...');
  console.log(`   UID  : ${testUid}`);
  console.log(`   Phone: ${testPhone}`);
  console.log('----------------------------------------------------');

  try {
    // 1. Create or ensure test user exists in Firebase Auth
    try {
      await auth.getUser(testUid);
    } catch (err) {
      if (err.code === 'auth/user-not-found') {
        await auth.createUser({
          uid: testUid,
          phoneNumber: testPhone,
        });
        console.log('✅ Created new test user in Firebase Auth.');
      }
    }

    // 2. Generate a custom token using Admin SDK
    const customToken = await auth.createCustomToken(testUid, {
      phone_number: testPhone,
    });

    console.log('\n[Option A] Generated Firebase Custom Token:');
    console.log(customToken);

    if (!webApiKey) {
      console.log('\n💡 To exchange this into an ID Token for Postman:');
      console.log('   Pass your Firebase Web API Key (found in Firebase Console -> Project Settings -> General -> Web API Key):');
      console.log('   node scripts/generate-test-token.js <YOUR_FIREBASE_WEB_API_KEY>');
      return;
    }

    // 3. Exchange custom token for a real ID Token via Google Identity Toolkit REST API
    const response = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webApiKey}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          token: customToken,
          returnSecureToken: true,
        }),
      }
    );

    const data = await response.json();

    if (data.idToken) {
      console.log('\n🎉 SUCCESS! Copy this Firebase ID Token into Postman:\n');
      console.log(data.idToken);
      console.log('\n(Expires in 1 hour)');
    } else {
      console.error('❌ Failed to exchange custom token:', data);
    }
  } catch (err) {
    console.error('❌ Error generating token:', err.message);
  }
}

main();
