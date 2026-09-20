// backend/scripts/test-s3-signing.js
// Self-check for config/s3.js signReport(). Pure signing — no network, no DB.
//   node scripts/test-s3-signing.js
'use strict';

const assert = require('assert');

process.env.AWS_REGION = 'ap-south-1';
process.env.AWS_ACCESS_KEY_ID = 'AKIAFAKEFAKEFAKEFAKE';
process.env.AWS_SECRET_ACCESS_KEY = 'fake-secret-for-signing-only';
process.env.S3_BUCKET_NAME = 'test-bucket';

const { signReport, URL_TTL_SECONDS } = require('../config/s3');

(async () => {
  // 1. An S3 key becomes a presigned HTTPS URL for that bucket+key.
  const signed = await signReport({ id: 'r1', report_file_url: 'reports/r1/123-456.pdf' });
  assert.match(signed.report_file_url, /^https:\/\/test-bucket\.s3\..*\/reports\/r1\/123-456\.pdf\?/);
  assert.match(signed.report_file_url, new RegExp(`X-Amz-Expires=${URL_TTL_SECONDS}`));
  assert.strictEqual(signed.id, 'r1', 'other fields survive');

  // 2. Seed rows already holding an absolute URL are left alone.
  const http = { report_file_url: 'https://example.com/dummy.pdf' };
  assert.strictEqual((await signReport(http)).report_file_url, http.report_file_url);

  // 3. Records with no report pass through untouched.
  assert.strictEqual((await signReport({ report_file_url: null })).report_file_url, null);

  // 4. No bucket configured (local dev) → no signing, no crash.
  delete require.cache[require.resolve('../config/s3')];
  delete process.env.S3_BUCKET_NAME;
  const noBucket = require('../config/s3');
  assert.strictEqual((await noBucket.signReport({ report_file_url: 'reports/a/b.pdf' })).report_file_url, 'reports/a/b.pdf');

  console.log('✅ s3 signing: 4/4 passed');
})();
