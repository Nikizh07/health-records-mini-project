// backend/middleware/upload.js
// ============================================================
// File Upload Middleware using Multer (Local Disk Storage)
// ============================================================
// Notes:
// - Stores uploaded medical test reports / documents in `backend/uploads/reports`
// - Validates file format (PDF, PNG, JPG, JPEG, WEBP)
// - Enforces 5 MB file size limit
// - NOTE: On Day 25, this local storage driver will be swapped
//   for Google Cloud Storage (GCS) signed upload URLs without
//   breaking this API endpoint contract.
// ============================================================

'use strict';

const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Ensure upload directory exists
const uploadDir = path.join(__dirname, '../uploads/reports');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// ── Storage Configuration ─────────────────────────────────────
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    // Generate unique sanitized filename: report-<timestamp>-<random><ext>
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `report-${uniqueSuffix}${ext}`);
  },
});

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
  storage: storage,
  limits: {
    fileSize: 5 * 1024 * 1024, // 5 MB maximum file size
  },
  fileFilter: fileFilter,
});

module.exports = upload;
