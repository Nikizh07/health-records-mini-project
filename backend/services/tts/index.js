// backend/services/tts/index.js
// ============================================================
// Pluggable TTS layer: provider registry for text-to-speech synthesis.
// ============================================================
// Every provider exports { name, isConfigured(), synthesize({...}) -> Buffer }.
// Adding one is a new file in providers/ plus one line in PROVIDERS.
//
// Every failure (unconfigured, network, timeout, unsupported language) surfaces
// as one TtsUnavailableError, so a caller has a single thing to catch and
// fall back from.
//
// The contract deliberately resembles services/ai/index.js: same PROVIDERS
// registry, same isConfigured()/isEnabled() pair, same error class pattern.
// ============================================================

'use strict';

const PROVIDERS = {
  mock: require('./providers/mock'),
  google: require('./providers/google'),
  polly: require('./providers/polly'),
};

class TtsUnavailableError extends Error {
  constructor(message, cause) {
    super(message);
    this.name = 'TtsUnavailableError';
    this.cause = cause;
  }
}

let warnedUnknownProvider = null;

function getProvider() {
  const key = process.env.TTS_PROVIDER || 'mock';
  const provider = PROVIDERS[key];
  if (!provider && warnedUnknownProvider !== key) {
    warnedUnknownProvider = key;
    console.warn(`⚠️  Unknown TTS_PROVIDER "${key}". TTS is disabled.`);
  }
  return provider || null;
}

/** True when TTS is not switched off and the chosen provider has its env set. */
function isTtsEnabled() {
  if (process.env.TTS_ENABLED === 'false') return false;
  const provider = getProvider();
  return Boolean(provider && provider.isConfigured());
}

/**
 * Synthesize speech from text using the configured provider.
 *
 * @param {Object} params
 * @param {string} params.text - The text to synthesize
 * @param {string} params.languageCode - Language code (en, hi, ta)
 * @param {AbortSignal} [params.signal] - Optional timeout signal
 * @returns {Promise<{buffer: Buffer, provider: string}>}
 * @throws {TtsUnavailableError}
 */
async function synthesize({ text, languageCode, signal }) {
  const provider = getProvider();
  if (!provider || !provider.isConfigured()) {
    throw new TtsUnavailableError('No TTS provider is configured');
  }

  // Default 30-second timeout if no signal provided
  const timeoutMs = Number(process.env.TTS_TIMEOUT_MS) || 30000;
  const actualSignal = signal || AbortSignal.timeout(timeoutMs);
  
  // Enforce the timeout here too, so a provider that ignores `signal` still
  // cannot hold a doctor's save open indefinitely.
  const timedOut = new Promise((_, reject) => {
    actualSignal.addEventListener('abort', () => reject(new Error('timed out')), { once: true });
  });

  try {
    const buffer = await Promise.race([
      provider.synthesize({ text, languageCode, signal: actualSignal }),
      timedOut,
    ]);
    
    if (!Buffer.isBuffer(buffer) || buffer.length === 0) {
      throw new Error('provider returned empty or invalid audio');
    }
    
    return { buffer, provider: provider.name };
  } catch (err) {
    throw new TtsUnavailableError(`${provider.name}: ${err.message}`, err);
  }
}

module.exports = {
  TtsUnavailableError,
  isTtsEnabled,
  synthesize,
};
