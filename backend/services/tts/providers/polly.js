// backend/services/tts/providers/polly.js
// ============================================================
// AWS Polly text-to-speech via AWS SDK.
// ============================================================
// Credentials come from the default AWS chain: AWS_PROFILE locally, the
// ECS task role in production. No access keys in env. This matches the
// pattern in services/ai/providers/bedrock.js and config/s3.js.
//
// The SDK is lazily required as an optionalDependency, so users who don't
// need Polly never have to install it.
//
// Voice selection: the plan requires verifying Tamil voice availability before
// committing to this provider. Polly has multiple voices per language.
// Configuration uses TTS_VOICE_* env vars to specify exact voices per language.
//
// Env vars:
//   TTS_PROVIDER=polly
//   AWS_REGION=ap-south-1
//   TTS_VOICE_EN=Kajal    (optional, defaults shown - Indian English voice)
//   TTS_VOICE_HI=Aditi    (Hindi voice)
//   TTS_VOICE_TA=<check>  (Tamil - needs verification)
//
// Verify available voices:
//   aws polly describe-voices --region ap-south-1 --language-code hi-IN
//   aws polly describe-voices --region ap-south-1 --language-code ta-IN
// ============================================================

'use strict';

let client = null;

// Default voice IDs per language (can be overridden via env)
const DEFAULT_VOICES = {
  en: 'Kajal',    // Indian English female voice
  hi: 'Aditi',    // Hindi female voice
  ta: null,       // Must be verified and configured explicitly
};

// Language codes for Polly API
const LANGUAGE_CODES = {
  en: 'en-IN',
  hi: 'hi-IN',
  ta: 'ta-IN',
};

module.exports = {
  name: 'polly',

  isConfigured() {
    return Boolean(process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION);
  },

  async synthesize({ text, languageCode, signal }) {
    if (!text || !text.trim()) {
      throw new Error('text is required');
    }

    // Required lazily so users without Polly never need the AWS SDK.
    try {
      var { PollyClient, SynthesizeSpeechCommand } = require('@aws-sdk/client-polly');
    } catch (err) {
      throw new Error(
        'AWS Polly SDK not installed. Install it with: npm install @aws-sdk/client-polly'
      );
    }

    client ??= new PollyClient({});

    // Map language code to Polly voice ID
    const voiceKey = `TTS_VOICE_${languageCode.toUpperCase()}`;
    const voiceId = process.env[voiceKey] || DEFAULT_VOICES[languageCode];
    
    if (!voiceId) {
      throw new Error(
        `no Polly voice configured for language "${languageCode}". ` +
        `Set ${voiceKey} or verify Tamil voice availability with: ` +
        `aws polly describe-voices --language-code ta-IN`
      );
    }

    const languageCodeFull = LANGUAGE_CODES[languageCode];
    if (!languageCodeFull) {
      throw new Error(`unsupported language code: ${languageCode}`);
    }

    const command = new SynthesizeSpeechCommand({
      Text: text,
      VoiceId: voiceId,
      LanguageCode: languageCodeFull,
      OutputFormat: 'mp3',
      Engine: 'standard', // 'neural' is higher quality but not available for all voices
    });

    const response = await client.send(command, { abortSignal: signal });

    if (!response.AudioStream) {
      throw new Error('Polly response missing AudioStream');
    }

    // Convert the readable stream to a buffer
    const chunks = [];
    for await (const chunk of response.AudioStream) {
      chunks.push(chunk);
    }

    return Buffer.concat(chunks);
  },
};
