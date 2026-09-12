// backend/utils/prescriptionWindow.js
// ============================================================
// "Is this prescription probably still being taken?"
// ============================================================
// Prescriptions carry only a free-text `duration` ("5 days", "2 weeks")
// and the parent record's `visit_date`. There is no end date column, so
// the end of a course has to be inferred.
//
// Safety stance: when the duration cannot be parsed we ASSUME the drug is
// still active if the visit was recent. A false warning costs the doctor a
// glance; a missed warning is the failure this feature exists to prevent.
// ============================================================

'use strict';

// How long an unparseable prescription is assumed to remain active.
const ASSUMED_ACTIVE_DAYS = 90;

const UNIT_DAYS = {
  day: 1,
  week: 7,
  month: 30,
  year: 365,
};

/**
 * Parses a free-text duration into a number of days.
 * Handles "5 days", "2 weeks", "1 month", "10d", "3/52" (weeks, UK shorthand).
 *
 * @param {string} raw
 * @returns {number|null} days, or null when unparseable
 */
function parseDurationDays(raw) {
  if (typeof raw !== 'string') return null;
  const text = raw.toLowerCase().trim();
  if (!text) return null;

  // UK shorthand: 3/7 = 3 days, 3/52 = 3 weeks, 3/12 = 3 months
  const shorthand = text.match(/^(\d+)\s*\/\s*(7|52|12)$/);
  if (shorthand) {
    const n = Number(shorthand[1]);
    const per = shorthand[2];
    if (per === '7') return n;
    if (per === '52') return n * 7;
    return n * 30;
  }

  const match = text.match(/(\d+(?:\.\d+)?)\s*(day|days|d|week|weeks|wk|wks|w|month|months|mon|mth|mths|m|year|years|yr|yrs|y)\b/);
  if (!match) return null;

  const value = Number(match[1]);
  if (!Number.isFinite(value) || value <= 0) return null;

  const unit = match[2];
  let key;
  if (/^(d|day|days)$/.test(unit)) key = 'day';
  else if (/^(w|wk|wks|week|weeks)$/.test(unit)) key = 'week';
  else if (/^(m|mon|mth|mths|month|months)$/.test(unit)) key = 'month';
  else key = 'year';

  return Math.ceil(value * UNIT_DAYS[key]);
}

/**
 * Decides whether a prescription is probably still being taken.
 *
 * @param {{ duration?: string }} prescription
 * @param {Date|string} visitDate - visit_date of the parent medical record
 * @param {Date} [now]
 * @returns {{ active: boolean, confidence: 'CERTAIN'|'ASSUMED', endsOn: Date|null }}
 *   confidence is ASSUMED when the duration could not be parsed, so the UI
 *   can say "duration unclear" instead of stating an end date it invented.
 */
function isLikelyActive(prescription, visitDate, now = new Date()) {
  const start = visitDate instanceof Date ? visitDate : new Date(visitDate);

  if (Number.isNaN(start.getTime())) {
    // No usable start date — treat as active rather than dropping it silently.
    return { active: true, confidence: 'ASSUMED', endsOn: null };
  }

  const days = parseDurationDays(prescription?.duration);

  if (days === null) {
    const assumedEnd = addDays(start, ASSUMED_ACTIVE_DAYS);
    return { active: now <= assumedEnd, confidence: 'ASSUMED', endsOn: null };
  }

  const endsOn = addDays(start, days);
  return { active: now <= endsOn, confidence: 'CERTAIN', endsOn };
}

function addDays(date, days) {
  const out = new Date(date.getTime());
  out.setDate(out.getDate() + days);
  return out;
}

module.exports = {
  ASSUMED_ACTIVE_DAYS,
  parseDurationDays,
  isLikelyActive,
};
