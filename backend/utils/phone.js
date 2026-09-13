// backend/utils/phone.js
// ============================================================
// Phone number normalisation (E.164)
// ============================================================
// Every phone the backend stores or matches goes through toE164(), so
// "+91 99999-00001", "0091 9999900001" and "9999900001" are the same
// number. A bare 10-digit number gets +91, matching the app's default.
// Anything else must carry its country code; there is no guessing.
// ============================================================

'use strict';

const DEFAULT_COUNTRY_CODE = '91';

/**
 * @param {string} raw
 * @returns {string|null} "+<8-15 digits>", or null when it can't be normalised
 */
function toE164(raw) {
  if (typeof raw !== 'string') return null;
  const trimmed = raw.trim();
  const digits = trimmed.replace(/\D/g, '');

  let e164 = null;
  if (trimmed.startsWith('+')) e164 = `+${digits}`;
  else if (digits.startsWith('00')) e164 = `+${digits.slice(2)}`;
  else if (digits.length === 10) e164 = `+${DEFAULT_COUNTRY_CODE}${digits}`;

  return e164 && /^\+[1-9]\d{7,14}$/.test(e164) ? e164 : null;
}

module.exports = { toE164 };
