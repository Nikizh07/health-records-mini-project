// backend/utils/mediaToken.js
// ============================================================
// Media token utilities: JWT-signed URLs for serving patient message assets.
// ============================================================
// Twilio Sandbox requires publicly accessible URLs for media attachments.
// Rather than S3, we serve media directly from the Express server via
// time-limited signed URLs.
//
// Token contains: { recordId, messageId, filename, exp }
// Signed with HMAC-SHA256 using JWT_SECRET (the same secret used by Firebase).
//
// This deliberately uses Node's built-in crypto rather than adding jsonwebtoken
// as a new dependency. The token format is a simplified JWT: base64url header,
// base64url payload, base64url signature, joined by dots.
// ============================================================

'use strict';

const crypto = require('crypto');

const ALGORITHM = 'sha256';

/**
 * Base64url encoding (RFC 4648 §5): no padding, URL-safe characters.
 */
function base64url(buffer) {
  return buffer.toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

/**
 * Base64url decoding.
 */
function base64urlDecode(str) {
  // Add padding back
  const padding = '='.repeat((4 - (str.length % 4)) % 4);
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/') + padding;
  return Buffer.from(base64, 'base64').toString('utf8');
}

/**
 * Get the signing secret from environment.
 * @throws {Error} if JWT_SECRET is not set
 */
function getSecret() {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET environment variable is required for media tokens');
  }
  return secret;
}

/**
 * Sign a media URL with a time-limited token.
 *
 * @param {string} recordId - Medical record ID
 * @param {string} messageId - Patient message ID
 * @param {string} filename - Asset filename (e.g., "audio-0.mp3")
 * @param {number} [ttlSeconds=900] - Time to live in seconds (default 15 minutes)
 * @returns {string} JWT token
 */
function signMediaToken(recordId, messageId, filename, ttlSeconds = 900) {
  if (!recordId || !messageId || !filename) {
    throw new Error('recordId, messageId, and filename are required');
  }

  const now = Math.floor(Date.now() / 1000);
  const exp = now + ttlSeconds;

  const header = {
    alg: 'HS256',
    typ: 'JWT',
  };

  const payload = {
    recordId,
    messageId,
    filename,
    iat: now,
    exp,
  };

  const headerB64 = base64url(Buffer.from(JSON.stringify(header)));
  const payloadB64 = base64url(Buffer.from(JSON.stringify(payload)));
  const message = `${headerB64}.${payloadB64}`;

  const signature = crypto
    .createHmac(ALGORITHM, getSecret())
    .update(message)
    .digest();
  const signatureB64 = base64url(signature);

  return `${message}.${signatureB64}`;
}

/**
 * Verify and decode a media token.
 *
 * @param {string} token - JWT token to verify
 * @returns {{recordId: string, messageId: string, filename: string} | null}
 *   Returns the decoded payload if valid, null otherwise.
 */
function verifyMediaToken(token) {
  if (!token || typeof token !== 'string') {
    return null;
  }

  const parts = token.split('.');
  if (parts.length !== 3) {
    return null;
  }

  const [headerB64, payloadB64, signatureB64] = parts;

  // Verify signature
  try {
    const message = `${headerB64}.${payloadB64}`;
    const expectedSignature = crypto
      .createHmac(ALGORITHM, getSecret())
      .update(message)
      .digest();
    const expectedSignatureB64 = base64url(expectedSignature);

    if (signatureB64 !== expectedSignatureB64) {
      return null;
    }

    // Decode and validate payload
    const payload = JSON.parse(base64urlDecode(payloadB64));

    // Check expiration
    const now = Math.floor(Date.now() / 1000);
    if (!payload.exp || payload.exp < now) {
      return null;
    }

    // Validate required fields
    if (!payload.recordId || !payload.messageId || !payload.filename) {
      return null;
    }

    return {
      recordId: payload.recordId,
      messageId: payload.messageId,
      filename: payload.filename,
    };
  } catch (err) {
    // Invalid token format, malformed JSON, etc.
    return null;
  }
}

/**
 * Generate a complete media URL for a given asset.
 *
 * @param {string} recordId
 * @param {string} messageId
 * @param {string} filename
 * @param {number} [ttlSeconds=900]
 * @returns {string} Full URL like https://example.com/api/media/:token/:filename
 */
function generateMediaUrl(recordId, messageId, filename, ttlSeconds = 900) {
  const baseUrl = process.env.PUBLIC_BASE_URL;
  if (!baseUrl) {
    throw new Error('PUBLIC_BASE_URL environment variable is required for media URLs');
  }

  const token = signMediaToken(recordId, messageId, filename, ttlSeconds);
  const encodedFilename = encodeURIComponent(filename);
  
  // Remove trailing slash from base URL
  const cleanBaseUrl = baseUrl.replace(/\/+$/, '');
  
  return `${cleanBaseUrl}/api/media/${token}/${encodedFilename}`;
}

module.exports = {
  signMediaToken,
  verifyMediaToken,
  generateMediaUrl,
};
