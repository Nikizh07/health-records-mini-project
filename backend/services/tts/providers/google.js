// backend/services/tts/providers/google.js
// ============================================================
// Google Cloud Text-to-Speech via REST API (no SDK required).
// ============================================================
// Uses bare fetch against the REST endpoint with an API key, following the
// pattern in services/ai/providers/openaiCompatible.js. No SDK dependency.
//
// Voice selection: the plan requires verifying Tamil voice availability before
// committing to this provider. Google offers multiple voices per language.
// Configuration uses TTS_VOICE_* env vars to specify exact voices per language.
//
// Env vars:
//   TTS_PROVIDER=google
//   GOOGLE_TTS_API_KEY=...
//   TTS_VOICE_EN=en-IN-Standard-A   (optional, defaults shown)
//   TTS_VOICE_HI=hi-IN-Standard-A
//   TTS_VOICE_TA=ta-IN-Standard-A
//
// Verify available voices:
//   curl "https://texttospeech.googleapis.com/v1/voices?key=YOUR_KEY" | jq '.voices[] | select(.languageCodes[] | contains("ta-IN"))'
// ============================================================

'use strict';

const GOOGLE_TTS_ENDPOINT = 'https://texttospeech.googleapis.com/v1/text:synthesize';

// Default voice names per language (can be overridden via env)
const DEFAULT_VOICES = {
  en: 'en-IN-Standard-A',
  hi: 'hi-IN-Standard-A',
  ta: 'ta-IN-Standard-A',
};

module.exports = {
  name: 'google',

  isConfigured() {
    return Boolean(process.env.GOOGLE_TTS_API_KEY);
  },

  async synthesize({ text, languageCode, signal }) {
    if (!text || !text.trim()) {
      throw new Error('text is required');
    }

    // Map language code to Google Cloud voice name
    const voiceKey = `TTS_VOICE_${languageCode.toUpperCase()}`;
    const voiceName = process.env[voiceKey] || DEFAULT_VOICES[languageCode];
    
    if (!voiceName) {
      throw new Error(`no voice configured for language "${languageCode}"`);
    }

    // Extract language code from voice name (e.g., "hi-IN-Standard-A" → "hi-IN")
    const languageCodeFull = voiceName.split('-').slice(0, 2).join('-');

    const requestBody = {
      input: { text },
      voice: {
        languageCode: languageCodeFull,
        name: voiceName,
      },
      audioConfig: {
        audioEncoding: 'MP3',
        // Slightly slower than default for clarity with medical instructions
        speakingRate: 0.9,
      },
    };

    const res = await fetch(`${GOOGLE_TTS_ENDPOINT}?key=${process.env.GOOGLE_TTS_API_KEY}`, {
      method: 'POST',
      signal,
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(requestBody),
    });

    if (!res.ok) {
      const errorText = await res.text();
      throw new Error(`HTTP ${res.status}: ${errorText.slice(0, 200)}`);
    }

    const data = await res.json();
    
    if (!data.audioContent) {
      throw new Error('response missing audioContent field');
    }

    // Google returns base64-encoded audio in the audioContent field
    return Buffer.from(data.audioContent, 'base64');
  },
};
