// backend/scripts/test-tts-provider.js
// ============================================================
// Is the configured TTS provider usable? One command, no DB, no app.
// ============================================================
// Synthesizes a short medical instruction in each supported language (en, hi, ta)
// through whatever TTS_PROVIDER backend/.env selects, and reports the audio
// size and how long it took.
//
// Usage:
//   node scripts/test-tts-provider.js
//   TTS_PROVIDER=google GOOGLE_TTS_API_KEY=... node scripts/test-tts-provider.js
//   TTS_PROVIDER=polly AWS_REGION=ap-south-1 node scripts/test-tts-provider.js
//
// Exits 1 if the provider is unconfigured, fails, or returns empty audio.
// Writes test audio files to /tmp for manual verification.
// ============================================================

'use strict';

const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const { isTtsEnabled, synthesize } = require('../services/tts');

// Short medical instructions in each supported language
const TEST_CASES = [
  {
    languageCode: 'en',
    text: 'Medicine number one, the blue one. Morning and night, after food. For five days.',
  },
  {
    languageCode: 'hi',
    text: 'दवाई नंबर एक, नीली वाली। सुबह और रात को, खाना खाने के बाद। पांच दिन तक।',
  },
  {
    languageCode: 'ta',
    text: 'மருந்து எண் ஒன்று, நீல நிறம். காலை மற்றும் இரவு, உணவுக்குப் பிறகு. ஐந்து நாட்களுக்கு.',
  },
];

const OUTPUT_DIR = '/tmp/tts-test';

async function main() {
  const provider = process.env.TTS_PROVIDER || 'mock';
  console.log(`\nTTS Provider: ${provider}`);
  console.log(`Output directory: ${OUTPUT_DIR}\n`);

  if (!isTtsEnabled()) {
    console.error('❌ TTS is disabled or the provider is missing its env vars (see backend/.env.example).');
    process.exit(1);
  }

  // Create output directory
  try {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  } catch (err) {
    console.error(`❌ Could not create output directory: ${err.message}`);
    process.exit(1);
  }

  let allPassed = true;
  const results = [];

  for (const testCase of TEST_CASES) {
    const { languageCode, text } = testCase;
    const started = Date.now();

    try {
      console.log(`Testing ${languageCode.toUpperCase()}...`);
      const { buffer, provider: usedProvider } = await synthesize({
        text,
        languageCode,
      });
      const elapsed = Date.now() - started;

      if (!buffer || buffer.length === 0) {
        throw new Error('provider returned empty buffer');
      }

      // Write to file for manual verification
      const filename = `${languageCode}-test.mp3`;
      const filepath = path.join(OUTPUT_DIR, filename);
      fs.writeFileSync(filepath, buffer);

      const sizeKb = (buffer.length / 1024).toFixed(2);
      console.log(`  ✅ ${sizeKb} KB in ${elapsed} ms (${usedProvider})`);
      console.log(`     → ${filepath}\n`);

      results.push({
        languageCode,
        success: true,
        sizeKb,
        elapsed,
        provider: usedProvider,
      });
    } catch (err) {
      const elapsed = Date.now() - started;
      console.error(`  ❌ ${languageCode.toUpperCase()} failed: ${err.message} (${elapsed} ms)\n`);
      allPassed = false;
      results.push({
        languageCode,
        success: false,
        error: err.message,
        elapsed,
      });
    }
  }

  // Summary
  console.log('─'.repeat(60));
  console.log('Summary:');
  const passed = results.filter((r) => r.success).length;
  const failed = results.filter((r) => !r.success).length;
  console.log(`  ${passed} passed, ${failed} failed`);

  if (allPassed) {
    console.log('\n✅ All TTS tests passed. Check audio files in:', OUTPUT_DIR);
    console.log('\nExample playback:');
    console.log(`  mpg123 ${OUTPUT_DIR}/en-test.mp3`);
    console.log(`  ffplay ${OUTPUT_DIR}/hi-test.mp3`);
    process.exit(0);
  } else {
    console.log('\n❌ Some TTS tests failed. See errors above.');
    
    // Provide hints for common issues
    const failedLangs = results.filter((r) => !r.success).map((r) => r.languageCode);
    if (failedLangs.includes('ta')) {
      console.log('\n💡 Tamil (ta) failed: This language may not be available on your provider.');
      console.log('   Verify available voices:');
      if (provider === 'polly') {
        console.log('     aws polly describe-voices --region ap-south-1 --language-code ta-IN');
      } else if (provider === 'google') {
        console.log('     curl "https://texttospeech.googleapis.com/v1/voices?key=YOUR_KEY" | jq \'.voices[] | select(.languageCodes[] | contains("ta-IN"))\'');
      }
      console.log('   If Tamil is unavailable, the system will degrade to English for ta-speaking patients.');
    }
    
    process.exit(1);
  }
}

main();
