#!/usr/bin/env node
// backend/scripts/debug-meta-whatsapp.js
// ============================================================
// Debug script to test Meta WhatsApp Cloud API directly
// and compare with what Meta's test button sends.
//
// Usage:
//   node scripts/debug-meta-whatsapp.js
//
// This sends a test message to the hardcoded phone number and
// shows the exact HTTP request/response for debugging.
// ============================================================

'use strict';

require('dotenv').config();

const TO_PHONE = '+919342060715';

async function testMetaAPI() {
  const token = process.env.META_ACCESS_TOKEN;
  const phoneNumberId = process.env.META_PHONE_NUMBER_ID;
  const apiVersion = process.env.META_API_VERSION || 'v19.0';

  console.log('='.repeat(70));
  console.log('Meta WhatsApp Cloud API Debug Test');
  console.log('='.repeat(70));
  console.log();
  console.log('Configuration:');
  console.log(`  API Version:       ${apiVersion}`);
  console.log(`  Phone Number ID:   ${phoneNumberId}`);
  console.log(`  Access Token:      ${token.substring(0, 20)}...`);
  console.log(`  To:                ${TO_PHONE}`);
  console.log();

  if (!token || !phoneNumberId) {
    console.error('❌ Missing META_ACCESS_TOKEN or META_PHONE_NUMBER_ID in .env');
    process.exit(1);
  }

  const apiUrl = `https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`;

  // Test 1: Simple text message (matches Meta's test button)
  console.log('Test 1: Simple Text Message');
  console.log('-'.repeat(70));

  const textPayload = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to: TO_PHONE,
    type: 'text',
    text: {
      preview_url: false,
      body: 'Test message from Migrant Clinic API - ' + new Date().toISOString()
    }
  };

  console.log('Request URL:');
  console.log(`  POST ${apiUrl}`);
  console.log();
  console.log('Request Headers:');
  console.log(`  Authorization: Bearer ${token.substring(0, 20)}...`);
  console.log('  Content-Type: application/json');
  console.log();
  console.log('Request Body:');
  console.log(JSON.stringify(textPayload, null, 2));
  console.log();

  try {
    // Add timeout to prevent hanging
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000); // 15 second timeout
    
    const response = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(textPayload),
      signal: controller.signal,
    });
    
    clearTimeout(timeoutId);

    console.log(`Response Status: ${response.status} ${response.statusText}`);
    console.log();

    const responseText = await response.text();
    console.log('Response Body:');
    
    try {
      const responseJson = JSON.parse(responseText);
      console.log(JSON.stringify(responseJson, null, 2));
      
      if (response.ok) {
        const wamid = responseJson.messages?.[0]?.id;
        console.log();
        console.log('✅ Message accepted by Meta API');
        console.log(`   WAMID: ${wamid}`);
        console.log();
        console.log('Next steps:');
        console.log('  1. Check your WhatsApp on +919342060715');
        console.log('  2. If message doesn\'t arrive, check:');
        console.log('     - Phone number is verified in Meta Business Manager');
        console.log('     - Phone number has WhatsApp installed');
        console.log('     - No rate limits or restrictions on your Meta app');
        console.log('     - Business account status in Meta Business Suite');
      } else {
        console.log();
        console.log('❌ Message rejected by Meta API');
        console.log();
        
        if (responseJson.error) {
          console.log('Error details:');
          console.log(`  Code: ${responseJson.error.code}`);
          console.log(`  Message: ${responseJson.error.message}`);
          console.log(`  Type: ${responseJson.error.type}`);
          
          if (responseJson.error.error_data) {
            console.log('  Details:', responseJson.error.error_data);
          }
        }
      }
    } catch (e) {
      console.log(responseText);
    }

  } catch (error) {
    console.log();
    console.log('❌ Request failed:');
    
    if (error.name === 'AbortError') {
      console.log('Request timed out after 15 seconds');
      console.log('This might indicate:');
      console.log('  - Network connectivity issues');
      console.log('  - DNS resolution problems');
      console.log('  - Firewall blocking Meta API');
      console.log('  - Meta API is down (check status.fb.com)');
    } else {
      console.log(error.message);
      console.log();
      console.log('Stack trace:');
      console.log(error.stack);
    }
  }

  console.log();
  console.log('='.repeat(70));
  console.log('Debug Information');
  console.log('='.repeat(70));
  console.log();
  console.log('Common issues:');
  console.log('  1. Token expired - Generate new token in Meta App Dashboard');
  console.log('  2. Phone number not registered - Add in Business Settings');
  console.log('  3. Account restrictions - Check Meta Business Suite notifications');
  console.log('  4. App not approved - Some features need Meta review');
  console.log('  5. Rate limits - Free tier has message limits');
  console.log();
  console.log('How to compare with Meta test button:');
  console.log('  1. Go to: developers.facebook.com > Your App > WhatsApp > API Setup');
  console.log('  2. Click "Send test message" button');
  console.log('  3. Compare the response with above output');
  console.log('  4. If test button works but this fails, token/config may be wrong');
  console.log('  5. If both get wamid but no delivery, issue is downstream');
  console.log();
  console.log('Useful Meta API endpoints to check:');
  console.log(`  Phone number info: GET https://graph.facebook.com/${apiVersion}/${phoneNumberId}`);
  console.log(`  Message status: GET https://graph.facebook.com/${apiVersion}/{wamid}`);
  console.log();
}

// Run the test
testMetaAPI().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
