// backend/routes/media.routes.js
// ============================================================
// Public media serving for Twilio Sandbox
// ============================================================
// Serves patient message assets (audio files, pictograms) via JWT-signed
// time-limited URLs. The token itself is the authorization — no Firebase
// auth middleware needed. This lets Twilio fetch media without credentials.
//
// Route: GET /api/media/:token/:filename
//
// The token contains { recordId, messageId, filename, exp } and is verified
// using backend/utils/mediaToken.js. Assets are stored as base64 in the
// PatientMessage.payload.assets JSON field.
//
// Security: 15-minute expiry, signature verified, no patient data in URL.
// ============================================================

'use strict';

const express = require('express');
const router = express.Router();
const { verifyMediaToken } = require('../utils/mediaToken');
const prisma = require('../config/prisma');

/**
 * GET /api/media/:token/:filename
 * Serve a patient message asset with token-based authorization.
 */
router.get('/:token/:filename', async (req, res, next) => {
  try {
    const { token, filename } = req.params;

    // 1. Verify the token
    const decoded = verifyMediaToken(token);
    if (!decoded) {
      return res.status(401).json({
        error: 'Unauthorized',
        message: 'Invalid or expired media token',
      });
    }

    // 2. Validate filename matches token
    if (decoded.filename !== decodeURIComponent(filename)) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Token does not authorize this filename',
      });
    }

    // 3. Fetch the PatientMessage record
    const message = await prisma.patientMessage.findUnique({
      where: { id: decoded.messageId },
      select: {
        id: true,
        record_id: true,
        payload: true,
      },
    });

    if (!message) {
      return res.status(404).json({
        error: 'Not Found',
        message: 'Message not found',
      });
    }

    // 4. Verify recordId matches
    if (message.record_id !== decoded.recordId) {
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Token does not match message record',
      });
    }

    // 5. Find the asset in the payload
    const assets = message.payload?.assets || [];
    const asset = assets.find((a) => a.filename === decoded.filename);

    if (!asset || !asset.base64Data) {
      return res.status(404).json({
        error: 'Not Found',
        message: 'Asset not found in message payload',
      });
    }

    // 6. Decode base64 and stream the media
    const buffer = Buffer.from(asset.base64Data, 'base64');
    const mimetype = asset.mimetype || 'application/octet-stream';

    res.set({
      'Content-Type': mimetype,
      'Content-Length': buffer.length,
      'Cache-Control': 'private, max-age=600', // 10 minutes
      'Content-Disposition': `inline; filename="${filename}"`,
    });

    res.send(buffer);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
