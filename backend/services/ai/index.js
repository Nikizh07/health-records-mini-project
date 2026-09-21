// backend/services/ai/index.js
// ============================================================
// Pluggable AI layer: provider registry, prompt rendering, JSON parsing.
// ============================================================
// Every provider exports { name, isConfigured(), complete({...}) -> string }.
// Adding one is a new file in providers/ plus one line in PROVIDERS.
//
// Every failure (unconfigured, network, timeout, unusable output) surfaces
// as one AiUnavailableError, so a caller has a single thing to catch and
// fall back from.
// ============================================================

'use strict';

const fs = require('fs');
const path = require('path');

const PROVIDERS = {
  'openai-compatible': require('./providers/openaiCompatible'),
  bedrock: require('./providers/bedrock'),
  sagemaker: require('./providers/sagemaker'),
};

const PROMPTS_DIR = path.resolve(__dirname, '../../prompts');
const USER_DELIMITER = /^---USER---$/m;
const SEVERITIES = new Set(['CRITICAL', 'MAJOR', 'MODERATE', 'MINOR']);

class AiUnavailableError extends Error {
  constructor(message, cause) {
    super(message);
    this.name = 'AiUnavailableError';
    this.cause = cause;
  }
}

let warnedUnknownProvider = null;

function getProvider() {
  const key = process.env.AI_PROVIDER || 'openai-compatible';
  const provider = PROVIDERS[key];
  if (!provider && warnedUnknownProvider !== key) {
    warnedUnknownProvider = key;
    console.warn(`⚠️  Unknown AI_PROVIDER "${key}". AI checks are disabled.`);
  }
  return provider || null;
}

/** True when AI is not switched off and the chosen provider has its env set. */
function isAiEnabled() {
  if (process.env.AI_ENABLED === 'false') return false;
  const provider = getProvider();
  return Boolean(provider && provider.isConfigured());
}

/**
 * One completion through the configured provider, bounded by AI_TIMEOUT_MS.
 *
 * @returns {Promise<{text: string, provider: string}>}
 * @throws {AiUnavailableError}
 */
async function complete({ system, user, maxTokens, temperature = 0 }) {
  const provider = getProvider();
  if (!provider || !provider.isConfigured()) {
    throw new AiUnavailableError('No AI provider is configured');
  }

  const signal = AbortSignal.timeout(Number(process.env.AI_TIMEOUT_MS) || 8000);
  // Enforce the timeout here too, so a provider that ignores `signal` still
  // cannot hold a doctor's save open.
  const timedOut = new Promise((_, reject) => {
    signal.addEventListener('abort', () => reject(new Error('timed out')), { once: true });
  });

  try {
    const text = await Promise.race([
      provider.complete({
        system,
        user,
        maxTokens: maxTokens || Number(process.env.AI_MAX_TOKENS) || 1500,
        temperature,
        signal,
      }),
      timedOut,
    ]);
    if (typeof text !== 'string' || !text.trim()) throw new Error('empty response');
    return { text, provider: provider.name };
  } catch (err) {
    throw new AiUnavailableError(`${provider.name}: ${err.message}`, err);
  }
}

const promptCache = new Map();

/**
 * Reads prompts/<name>.md, splits it on the ---USER--- line and fills
 * {{placeholders}}. Re-read on every call outside production, so the prompt
 * can be edited without a restart.
 *
 * @returns {{system: string, user: string}}
 */
function renderPrompt(name, vars) {
  let source = promptCache.get(name);
  if (!source) {
    source = fs.readFileSync(path.join(PROMPTS_DIR, `${name}.md`), 'utf8');
    if (process.env.NODE_ENV === 'production') promptCache.set(name, source);
  }

  const parts = source.split(USER_DELIMITER);
  if (parts.length !== 2) throw new Error(`prompts/${name}.md needs exactly one ---USER--- line`);

  const fill = (text) =>
    text.replace(/\{\{(\w+)\}\}/g, (_, key) => {
      if (!(key in vars)) throw new Error(`prompts/${name}.md uses {{${key}}}, which was not supplied`);
      return String(vars[key]);
    });

  return { system: fill(parts[0]).trim(), user: fill(parts[1]).trim() };
}

// First balanced {...} in the text, skipping braces inside JSON strings.
function extractJsonObject(text) {
  const start = text.indexOf('{');
  if (start === -1) return null;

  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === '\\') escaped = true;
      else if (ch === '"') inString = false;
    } else if (ch === '"') {
      inString = true;
    } else if (ch === '{') {
      depth += 1;
    } else if (ch === '}') {
      depth -= 1;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}

/**
 * Pulls `{ "conflicts": [...] }` out of model text: tolerates code fences,
 * surrounding prose and <think> blocks; drops malformed entries.
 *
 * Unusable output throws AiUnavailableError, so it is handled exactly like
 * an outage.
 *
 * @returns {Array<{new_drug, existing_drug, severity, explanation, suggested_alternative}>}
 */
function parseConflicts(text) {
  const json = extractJsonObject(String(text).replace(/<think>[\s\S]*?<\/think>/g, ''));

  let parsed;
  try {
    parsed = JSON.parse(json);
  } catch (err) {
    throw new AiUnavailableError('AI response contained no usable JSON', err);
  }
  if (!parsed || !Array.isArray(parsed.conflicts)) {
    throw new AiUnavailableError('AI response has no "conflicts" array');
  }

  const isText = (v) => typeof v === 'string' && v.trim() !== '';

  return parsed.conflicts
    .filter((c) => c && isText(c.new_drug) && isText(c.existing_drug) && isText(c.explanation))
    .map((c) => ({
      new_drug: c.new_drug.trim(),
      existing_drug: c.existing_drug.trim(),
      severity: String(c.severity || '').trim().toUpperCase(),
      explanation: c.explanation.trim(),
      suggested_alternative: isText(c.suggested_alternative) ? c.suggested_alternative.trim() : null,
    }))
    .filter((c) => SEVERITIES.has(c.severity));
}

module.exports = {
  AiUnavailableError,
  isAiEnabled,
  complete,
  renderPrompt,
  parseConflicts,
  // Exported for other AI callers (services/doseScheduleParser.js) so the
  // balanced-brace scanner is written once rather than copied per feature.
  extractJsonObject,
};
