// backend/scripts/test-ai-provider.js
// ============================================================
// Is the configured AI provider usable? One command, no DB, no app.
// ============================================================
// Renders the real drug-interaction prompt for a canned case (a patient on
// warfarin being handed the brand name "Brufen"), sends it through whatever
// AI_PROVIDER backend/.env selects, and prints the raw reply, the parsed
// conflicts and how long it took.
//
// Usage:
//   node scripts/test-ai-provider.js
//   AI_PROVIDER=bedrock AWS_REGION=ap-south-1 AI_MODEL=... node scripts/test-ai-provider.js
//
// Exits 1 if the provider is unconfigured, fails, or returns nothing usable.
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });

const { isAiEnabled, complete } = require('../services/ai');
const { renderInteractionPrompt, parseConflicts } = require('../services/interactionChecker');

const newDrugs = [{ raw: 'Brufen 400mg', name: 'brufen' }];
const activeMeds = [
  {
    name: 'warfarin',
    medicine_name: 'Warfarin 5mg',
    dosage: '5mg once daily',
    duration: '90 days',
  },
];
// A slice of the curated table, as the checker would pass it.
const tableRows = [
  {
    drug_a: 'ibuprofen',
    drug_b: 'warfarin',
    severity: 'CRITICAL',
    mechanism: 'NSAIDs inhibit platelet function and irritate the gastric mucosa, raising the bleeding risk of warfarin.',
  },
];

async function main() {
  const provider = process.env.AI_PROVIDER || 'openai-compatible';
  console.log(`Provider: ${provider}   model: ${process.env.AI_MODEL || process.env.AI_SAGEMAKER_ENDPOINT || '(unset)'}`);

  if (!isAiEnabled()) {
    console.error('❌ AI is disabled or the provider is missing its env vars (see backend/.env.example).');
    process.exit(1);
  }

  const { system, user } = renderInteractionPrompt(newDrugs, activeMeds, tableRows);
  const started = Date.now();

  try {
    const { text } = await complete({ system, user, temperature: 0 });
    const elapsed = Date.now() - started;

    console.log('\n── Raw reply ──\n' + text);
    const conflicts = parseConflicts(text);
    console.log('\n── Parsed conflicts ──\n' + JSON.stringify(conflicts, null, 2));
    console.log(`\n── ${elapsed} ms ──`);

    const caught = conflicts.some((c) => /brufen/i.test(c.new_drug + c.existing_drug) && /warfarin/i.test(c.new_drug + c.existing_drug));
    console.log(caught ? '✅ Brufen + warfarin caught' : '⚠️  Reply parsed, but Brufen + warfarin was not flagged');
    process.exit(conflicts.length ? 0 : 1);
  } catch (err) {
    console.error(`\n❌ ${err.message} (after ${Date.now() - started} ms)`);
    process.exit(1);
  }
}

main();
