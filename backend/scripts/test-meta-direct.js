#!/usr/bin/env node
// Test Meta API with minimal code to isolate the issue

require('dotenv').config();

async function test() {
  const token = process.env.META_ACCESS_TOKEN;
  const phoneNumberId = process.env.META_PHONE_NUMBER_ID;
  const apiUrl = `https://graph.facebook.com/v19.0/${phoneNumberId}/messages`;

  console.log('Testing Meta WhatsApp API...');
  console.log('Phone Number ID:', phoneNumberId);
  console.log('Token (first 20):', token?.substring(0, 20));
  console.log('API URL:', apiUrl);
  console.log();

  const payload = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to: '+919342060715',
    type: 'text',
    text: {
      preview_url: false,
      body: 'Test message ' + Date.now()
    }
  };

  console.log('Payload:');
  console.log(JSON.stringify(payload, null, 2));
  console.log();

  try {
    const response = await fetch(apiUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    console.log('Response Status:', response.status);
    const data = await response.json();
    console.log('Response Body:');
    console.log(JSON.stringify(data, null, 2));

    if (data.messages) {
      console.log('\n✅ SUCCESS! Message ID:', data.messages[0].id);
      console.log('Check your phone: +919342060715');
    } else if (data.error) {
      console.log('\n❌ ERROR:', data.error.message);
      console.log('Code:', data.error.code);
      console.log('Type:', data.error.type);
    }
  } catch (err) {
    console.error('❌ Request failed:', err.message);
  }
}

test();
