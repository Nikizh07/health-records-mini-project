// backend/utils/healthId.js
// ============================================================
// System-wide Unique Health ID Generator
// ============================================================
// Format: MWH-XXXXXX (e.g. MWH-7A9K32 or MWH-849201)
// - Human-readable identifier for migrant worker medical records
// - Performs database collision checks before returning guaranteed unique ID
// ============================================================

'use strict';

const crypto = require('crypto');

/**
 * Generates a candidate 6-character random uppercase alphanumeric string.
 * Uses cryptographically secure random bytes.
 * @returns {string} e.g. "MWH-7A9K32"
 */
function generateCandidateId() {
  const characters = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // Excludes confusing characters (0, O, 1, I)
  let result = '';
  const bytes = crypto.randomBytes(6);
  for (let i = 0; i < 6; i++) {
    result += characters[bytes[i] % characters.length];
  }
  return `MWH-${result}`;
}

/**
 * Generates a guaranteed unique health_id by checking against PostgreSQL database via Prisma.
 * Retries up to maxRetries times in case of collision.
 *
 * @param {object} prisma - Prisma Client instance
 * @param {number} maxRetries - Maximum retry attempts (default: 10)
 * @returns {Promise<string>} Unique health_id (e.g. "MWH-849201")
 */
async function generateUniqueHealthId(prisma, maxRetries = 10) {
  for (let attempt = 0; attempt < maxRetries; attempt++) {
    const candidate = generateCandidateId();
    
    // Check uniqueness in database
    const existingPatient = await prisma.patient.findUnique({
      where: { health_id: candidate },
      select: { id: true },
    });

    if (!existingPatient) {
      return candidate; // Unique ID found!
    }
    console.warn(`⚠️ Health ID collision detected for candidate "${candidate}". Retrying (attempt ${attempt + 1})...`);
  }

  throw new Error('Failed to generate a unique health_id after multiple attempts. Please try again.');
}

module.exports = {
  generateCandidateId,
  generateUniqueHealthId,
};
