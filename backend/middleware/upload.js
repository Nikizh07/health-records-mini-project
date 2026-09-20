// backend/middleware/upload.js
// ============================================================
// File Upload Middleware using Multer (in-memory)
// ============================================================
// Notes:
// - Buffers the uploaded report in memory; the controller streams it to the
//   private S3 bucket (see config/s3.js). Nothing is written to container disk.
// - Validates file format (PDF, PNG, JPG, JPEG, WEBP)
// - Enforces 5 MB file size limit — the same cap keeps the buffer small
// ============================================================

'use strict';

const multer = require('multer');

// ── File Filter & MIME Validation ─────────────────────────────
const fileFilter = (req, file, cb) => {
  const allowedMimeTypes = [
    'application/pdf',
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/webp',
  ];

  if (allowedMimeTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    const error = new Error('Invalid file type. Only PDF, PNG, JPG, JPEG, and WEBP documents are permitted.');
    error.statusCode = 400;
    cb(error, false);
  }
};

// ── Multer Instance ───────────────────────────────────────────
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 5 * 1024 * 1024, // 5 MB maximum file size
  },
  fileFilter: fileFilter,
});

module.exports = upload;
