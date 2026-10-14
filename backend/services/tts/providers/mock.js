// backend/services/tts/providers/mock.js
// ============================================================
// Mock TTS provider: returns a tiny fixed WAV file.
// ============================================================
// Lets the whole pipeline run locally with no credentials. The audio is a
// valid 1-second silent WAV that any player will accept. Phase 7's offline
// suite uses this provider to verify the orchestrator works end-to-end.
// ============================================================

'use strict';

module.exports = {
  name: 'mock',

  isConfigured() {
    // Always available — no env vars required.
    return true;
  },

  /**
   * @returns {Promise<Buffer>} A tiny valid WAV file (silent, 1 second, 8kHz mono)
   */
  async synthesize({ text, languageCode, signal }) {
    // Minimal WAV file: RIFF header + fmt chunk + data chunk
    // 8000 Hz, 8-bit mono, 1 second = 8000 samples of 0x80 (silence in unsigned 8-bit)
    const sampleRate = 8000;
    const numSamples = sampleRate; // 1 second
    const dataSize = numSamples;
    const fileSize = 36 + dataSize;

    const buffer = Buffer.alloc(44 + dataSize);
    let offset = 0;

    // RIFF header
    buffer.write('RIFF', offset); offset += 4;
    buffer.writeUInt32LE(fileSize, offset); offset += 4;
    buffer.write('WAVE', offset); offset += 4;

    // fmt chunk
    buffer.write('fmt ', offset); offset += 4;
    buffer.writeUInt32LE(16, offset); offset += 4; // fmt chunk size
    buffer.writeUInt16LE(1, offset); offset += 2;  // audio format (PCM)
    buffer.writeUInt16LE(1, offset); offset += 2;  // num channels (mono)
    buffer.writeUInt32LE(sampleRate, offset); offset += 4;
    buffer.writeUInt32LE(sampleRate, offset); offset += 4; // byte rate
    buffer.writeUInt16LE(1, offset); offset += 2;  // block align
    buffer.writeUInt16LE(8, offset); offset += 2;  // bits per sample

    // data chunk
    buffer.write('data', offset); offset += 4;
    buffer.writeUInt32LE(dataSize, offset); offset += 4;

    // Audio samples: 0x80 is digital silence for unsigned 8-bit PCM
    buffer.fill(0x80, offset);

    return buffer;
  },
};
