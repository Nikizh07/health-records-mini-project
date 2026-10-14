// backend/services/messaging/index.js
// ============================================================
// Pluggable messaging layer: provider registry for WhatsApp delivery.
// ============================================================
// Every provider exports { name, isConfigured(), send({to, body, media}) -> {providerMessageId} }.
// Adding one is a new file in providers/ plus one line in PROVIDERS.
//
// Every failure (unconfigured, network, timeout) surfaces as one
// MessagingUnavailableError, so a caller has a single thing to catch.
// ============================================================

'use strict';

const PROVIDERS = {
  'twilio-sandbox': require('./providers/twilioSandbox'),
  log: require('./providers/log'),
};

class MessagingUnavailableError extends Error {
  constructor(message, cause) {
    super(message);
    this.name = 'MessagingUnavailableError';
    this.cause = cause;
  }
}

let warnedUnknownProvider = null;

function getProvider() {
  const key = process.env.MSG_PROVIDER || 'log';
  const provider = PROVIDERS[key];
  if (!provider && warnedUnknownProvider !== key) {
    warnedUnknownProvider = key;
    console.warn(`⚠️  Unknown MSG_PROVIDER "${key}". Messaging is disabled.`);
  }
  return provider || null;
}

/** True when messaging is not switched off and the chosen provider has its env set. */
function isMessagingEnabled() {
  if (process.env.MSG_ENABLED === 'false') return false;
  const provider = getProvider();
  return Boolean(provider && provider.isConfigured());
}

/**
 * Send a WhatsApp message through the configured provider.
 *
 * @param {Object} params
 * @param {string} params.to - E.164 phone number (e.g., 'whatsapp:+919876543210')
 * @param {string} params.body - Message text
 * @param {Array<{buffer: Buffer, mimetype: string, filename: string, url: string}>} params.media - Media attachments
 * @returns {Promise<{providerMessageId: string}>}
 * @throws {MessagingUnavailableError}
 */
async function send({ to, body, media = [] }) {
  const provider = getProvider();
  if (!provider || !provider.isConfigured()) {
    throw new MessagingUnavailableError('No messaging provider is configured');
  }

  const timeout = Number(process.env.MSG_TIMEOUT_MS) || 30000;
  const signal = AbortSignal.timeout(timeout);
  const timedOut = new Promise((_, reject) => {
    signal.addEventListener('abort', () => reject(new Error('timed out')), { once: true });
  });

  try {
    const result = await Promise.race([
      provider.send({ to, body, media, signal }),
      timedOut,
    ]);
    
    if (!result || !result.providerMessageId) {
      throw new Error('Provider returned no message ID');
    }
    
    return result;
  } catch (err) {
    throw new MessagingUnavailableError(`${provider.name}: ${err.message}`, err);
  }
}

module.exports = {
  MessagingUnavailableError,
  isMessagingEnabled,
  send,
  getProvider, // exported for testing
};
