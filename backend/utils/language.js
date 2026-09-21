// backend/utils/language.js
// ============================================================
// Backend mirror of mobile_app/lib/providers/locale_provider.dart → parseLocale()
// ============================================================
// The registration form offers eight languages and defaults to Bengali.
// Only three are spoken by the Smart Prescriptions TTS layer.
// resolveLanguage() maps any stored language_pref to a supported code,
// or falls back to English with supported:false so the preview can say so.
// ============================================================

'use strict';

// The three codes the TTS and message-template layers support.
const SUPPORTED_CODES = ['en', 'hi', 'ta'];

/**
 * Maps any language_pref string stored in the patients table to a supported
 * TTS/template code, with a flag indicating whether it was actually supported.
 *
 * Accepts both the code form ('ta', 'hi', 'en') and the display-name form
 * stored by the registration form ('Tamil', 'Hindi', 'English', 'Bengali', …).
 *
 * @param {string|null|undefined} language_pref
 * @returns {{
 *   code: 'en'|'hi'|'ta',
 *   requested: string,   // the human-readable name of what was requested
 *   supported: boolean
 * }}
 */
function resolveLanguage(language_pref) {
  const raw = typeof language_pref === 'string' ? language_pref.trim() : '';
  const lower = raw.toLowerCase();

  // Tamil
  if (lower === 'ta' || lower.includes('tamil') || lower.includes('தமிழ்')) {
    return { code: 'ta', requested: 'Tamil', supported: true };
  }

  // Hindi
  if (lower === 'hi' || lower.includes('hindi') || lower.includes('हिंदी')) {
    return { code: 'hi', requested: 'Hindi', supported: true };
  }

  // English
  if (lower === 'en' || lower.includes('english')) {
    return { code: 'en', requested: 'English', supported: true };
  }

  // Unsupported languages — fall back to English, surface the original name.
  // The registration form stores display names: 'Bengali', 'Malayalam', etc.
  const requested = raw || 'Unknown';
  return { code: 'en', requested, supported: false };
}

module.exports = { resolveLanguage, SUPPORTED_CODES };
