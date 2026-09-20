// backend/config/s3.js
// ============================================================
// Private S3 bucket for uploaded medical reports
// ============================================================
// The bucket blocks all public access. `report_file_url` stores the S3 *key*;
// the API swaps it for a short-lived presigned HTTPS URL on the way out.
// Credentials come from the AWS chain (ECS task role in prod, AWS_PROFILE locally).
// ============================================================

'use strict';

const { S3Client, PutObjectCommand, GetObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');

const BUCKET = process.env.S3_BUCKET_NAME;
const URL_TTL_SECONDS = 15 * 60;

const s3 = new S3Client({ region: process.env.AWS_REGION });

async function putReport(buffer, key, mimetype) {
  if (!BUCKET) throw new Error('S3_BUCKET_NAME is not set — cannot store the report.');
  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: buffer,
    ContentType: mimetype,
  }));
  return key;
}

// Returns the record with `report_file_url` swapped for a presigned GET URL.
// Left untouched: records with no report, absolute URLs (seed data), and every
// record when no bucket is configured (local dev without AWS).
async function signReport(record) {
  const key = record && record.report_file_url;
  if (!key || key.startsWith('http') || !BUCKET) return record;

  const url = await getSignedUrl(
    s3,
    new GetObjectCommand({ Bucket: BUCKET, Key: key }),
    { expiresIn: URL_TTL_SECONDS }
  );
  return { ...record, report_file_url: url };
}

module.exports = { s3, putReport, signReport, URL_TTL_SECONDS };
