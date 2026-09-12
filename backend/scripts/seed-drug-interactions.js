// backend/scripts/seed-drug-interactions.js
// ============================================================
// Seeds the curated drug-drug interaction reference table.
//
// This is the deterministic half of the medication conflict detector:
// it needs no network and no AI provider, so it keeps working when the
// AI leg is disabled or unreachable. See AI_DRUG_INTERACTION_PLAN.md.
//
// Conventions for every row:
//   - drug_a / drug_b are NORMALISED: lowercase generic name only,
//     no strength, no dose form. Must match utils/drugName.js output.
//   - drug_a < drug_b (alphabetical), so each pair has exactly one row.
//
// Usage:
//   node scripts/seed-drug-interactions.js
// ============================================================

'use strict';

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });

const prisma = require('../config/prisma');
const { normaliseDrugName } = require('../utils/drugName');

// ── Curated pairs ────────────────────────────────────────────
// Severity guide:
//   CRITICAL — avoid the combination; real risk of death or major harm
//   MAJOR    — avoid unless clearly justified; needs monitoring
//   MODERATE — usually manageable, but dose/monitoring should change
//   MINOR    — worth knowing, rarely changes the plan
const INTERACTIONS = [
  // ── Anticoagulants / antiplatelets — bleeding risk ──
  ['warfarin', 'ibuprofen', 'CRITICAL', 'NSAIDs inhibit platelet function and irritate gastric mucosa, sharply increasing the risk of major bleeding in a patient already anticoagulated with warfarin.', 'Acetaminophen'],
  ['warfarin', 'naproxen', 'CRITICAL', 'Same NSAID bleeding risk as ibuprofen, with a longer half-life prolonging the exposure.', 'Acetaminophen'],
  ['warfarin', 'diclofenac', 'CRITICAL', 'NSAID antiplatelet effect plus gastric irritation markedly raises bleeding risk on warfarin.', 'Acetaminophen'],
  ['aspirin', 'warfarin', 'CRITICAL', 'Additive anticoagulant and antiplatelet effects substantially increase the risk of gastrointestinal and intracranial bleeding.', 'Acetaminophen for analgesia'],
  ['clopidogrel', 'warfarin', 'CRITICAL', 'Dual antiplatelet plus anticoagulant therapy greatly increases major bleeding risk and should only be used under specialist supervision.', null],
  ['fluconazole', 'warfarin', 'MAJOR', 'Fluconazole inhibits CYP2C9, reducing warfarin metabolism and raising INR into the bleeding range.', 'Topical antifungal, or reduce warfarin dose with INR monitoring'],
  ['metronidazole', 'warfarin', 'MAJOR', 'Metronidazole inhibits warfarin metabolism, causing a marked INR rise within days.', null],
  ['ciprofloxacin', 'warfarin', 'MAJOR', 'Ciprofloxacin potentiates warfarin and raises INR; bleeding events are well documented.', 'An antibiotic without CYP interaction, guided by culture'],
  ['amiodarone', 'warfarin', 'MAJOR', 'Amiodarone inhibits warfarin metabolism; the warfarin dose usually needs roughly halving with close INR monitoring.', null],
  ['aspirin', 'ibuprofen', 'MODERATE', 'Ibuprofen competitively blocks aspirin binding to platelet COX-1, reducing aspirin cardioprotection, and adds gastrointestinal bleeding risk.', 'Acetaminophen, or dose aspirin 2 hours before ibuprofen'],
  ['clopidogrel', 'omeprazole', 'MAJOR', 'Omeprazole inhibits CYP2C19, reducing conversion of clopidogrel to its active metabolite and weakening antiplatelet protection.', 'Pantoprazole'],

  // ── Serotonergic — serotonin syndrome ──
  ['sertraline', 'tramadol', 'MAJOR', 'Both raise synaptic serotonin, risking serotonin syndrome; tramadol also lowers the seizure threshold.', 'A non-serotonergic analgesic'],
  ['fluoxetine', 'tramadol', 'MAJOR', 'Additive serotonergic effect plus CYP2D6 inhibition, risking serotonin syndrome and reduced tramadol efficacy.', 'A non-serotonergic analgesic'],
  ['linezolid', 'sertraline', 'CRITICAL', 'Linezolid is a reversible MAO inhibitor; combined with an SSRI it can precipitate life-threatening serotonin syndrome.', null],
  ['linezolid', 'fluoxetine', 'CRITICAL', 'MAO inhibition plus SSRI carries a high risk of serotonin syndrome; fluoxetine long half-life extends the danger for weeks.', null],
  ['fluoxetine', 'tranylcypromine', 'CRITICAL', 'SSRI combined with an MAO inhibitor can cause fatal serotonin syndrome; a washout period is mandatory.', null],
  ['sertraline', 'sumatriptan', 'MODERATE', 'Both increase serotonergic tone; monitor for serotonin syndrome, though the combination is often tolerated.', null],
  ['dextromethorphan', 'fluoxetine', 'MODERATE', 'Fluoxetine inhibits CYP2D6, raising dextromethorphan levels and adding serotonergic load.', null],

  // ── QT prolongation ──
  ['amiodarone', 'ciprofloxacin', 'MAJOR', 'Additive QT interval prolongation increases the risk of torsades de pointes.', null],
  ['azithromycin', 'amiodarone', 'MAJOR', 'Both prolong the QT interval; the combination raises the risk of fatal arrhythmia.', null],
  ['citalopram', 'azithromycin', 'MODERATE', 'Additive QT prolongation; consider an ECG if other risk factors are present.', null],
  ['domperidone', 'ketoconazole', 'MAJOR', 'Ketoconazole inhibits CYP3A4, raising domperidone levels and prolonging the QT interval.', null],

  // ── Renal / electrolyte ──
  ['lisinopril', 'spironolactone', 'MAJOR', 'ACE inhibitor plus potassium-sparing diuretic can cause dangerous hyperkalaemia.', 'Monitor potassium closely, or use a thiazide'],
  ['losartan', 'spironolactone', 'MAJOR', 'ARB plus potassium-sparing diuretic risks hyperkalaemia, especially with impaired renal function.', null],
  ['ibuprofen', 'lisinopril', 'MODERATE', 'NSAIDs blunt the antihypertensive effect and, with an ACE inhibitor, risk acute kidney injury.', 'Acetaminophen'],
  ['furosemide', 'ibuprofen', 'MODERATE', 'NSAIDs reduce the diuretic and antihypertensive effect of furosemide and add renal risk.', 'Acetaminophen'],
  ['lithium', 'ibuprofen', 'MAJOR', 'NSAIDs reduce renal lithium clearance, pushing lithium into the toxic range.', 'Acetaminophen'],
  ['lithium', 'lisinopril', 'MAJOR', 'ACE inhibitors reduce lithium excretion and can cause lithium toxicity.', null],
  ['gentamicin', 'furosemide', 'MAJOR', 'Additive ototoxicity and nephrotoxicity.', null],

  // ── Statins — rhabdomyolysis ──
  ['clarithromycin', 'simvastatin', 'CRITICAL', 'Clarithromycin strongly inhibits CYP3A4, causing simvastatin accumulation and a high risk of rhabdomyolysis.', 'Azithromycin, or hold the statin during the antibiotic course'],
  ['itraconazole', 'simvastatin', 'CRITICAL', 'Potent CYP3A4 inhibition sharply raises simvastatin exposure and rhabdomyolysis risk.', 'Pravastatin'],
  ['gemfibrozil', 'simvastatin', 'MAJOR', 'Combined fibrate and statin markedly increases the risk of myopathy and rhabdomyolysis.', 'Fenofibrate'],
  ['amlodipine', 'simvastatin', 'MODERATE', 'Amlodipine raises simvastatin levels; the simvastatin dose should be capped at 20 mg daily.', null],

  // ── CNS depression ──
  ['alprazolam', 'morphine', 'CRITICAL', 'Benzodiazepine plus opioid causes additive respiratory depression and is a leading cause of overdose death.', null],
  ['diazepam', 'morphine', 'CRITICAL', 'Additive CNS and respiratory depression; avoid co-prescribing where possible.', null],
  ['codeine', 'diazepam', 'MAJOR', 'Additive sedation and respiratory depression.', null],
  ['alprazolam', 'ketoconazole', 'MODERATE', 'CYP3A4 inhibition raises alprazolam levels, prolonging sedation.', null],

  // ── Metabolic / endocrine ──
  ['metformin', 'prednisolone', 'MODERATE', 'Corticosteroids raise blood glucose and oppose metformin, worsening glycaemic control.', null],
  ['glibenclamide', 'ciprofloxacin', 'MODERATE', 'Fluoroquinolones can potentiate sulfonylureas and cause hypoglycaemia.', null],
  ['levothyroxine', 'omeprazole', 'MODERATE', 'Reduced gastric acid impairs levothyroxine absorption, lowering its effect.', 'Separate the doses by at least 4 hours'],
  ['calcium carbonate', 'levothyroxine', 'MODERATE', 'Calcium binds levothyroxine in the gut and reduces absorption.', 'Separate the doses by at least 4 hours'],

  // ── Antibiotic / absorption ──
  ['ciprofloxacin', 'calcium carbonate', 'MODERATE', 'Divalent cations chelate fluoroquinolones and substantially reduce absorption.', 'Separate the doses by at least 2 hours'],
  ['doxycycline', 'ferrous sulfate', 'MODERATE', 'Iron chelates tetracyclines, markedly reducing antibiotic absorption.', 'Separate the doses by at least 2 hours'],
  ['amoxicillin', 'methotrexate', 'MAJOR', 'Penicillins reduce renal methotrexate clearance, risking methotrexate toxicity.', null],
  ['methotrexate', 'trimethoprim', 'CRITICAL', 'Both are antifolates; the combination risks severe bone marrow suppression.', null],
  ['ibuprofen', 'methotrexate', 'MAJOR', 'NSAIDs reduce methotrexate excretion and increase its toxicity.', 'Acetaminophen'],

  // ── Other well-known pairs ──
  ['allopurinol', 'azathioprine', 'CRITICAL', 'Allopurinol blocks azathioprine metabolism, causing profound and potentially fatal myelosuppression.', null],
  ['digoxin', 'furosemide', 'MAJOR', 'Diuretic-induced hypokalaemia sensitises the myocardium to digoxin toxicity.', 'Monitor potassium and digoxin levels'],
  ['amiodarone', 'digoxin', 'MAJOR', 'Amiodarone roughly doubles digoxin levels, risking toxicity.', 'Halve the digoxin dose and monitor levels'],
  ['carbamazepine', 'warfarin', 'MAJOR', 'Carbamazepine induces CYP enzymes and reduces warfarin effect, risking clot formation.', null],
  ['phenytoin', 'fluconazole', 'MAJOR', 'Fluconazole inhibits phenytoin metabolism and can cause phenytoin toxicity.', null],
  ['rifampicin', 'ethinylestradiol', 'MAJOR', 'Rifampicin induces CYP3A4 and markedly reduces oral contraceptive efficacy.', 'Add a barrier method during and after the course'],
  ['sildenafil', 'isosorbide dinitrate', 'CRITICAL', 'Combined nitrate and PDE5 inhibitor causes profound, potentially fatal hypotension.', null],
  ['spironolactone', 'potassium chloride', 'MAJOR', 'Additive potassium load risks severe hyperkalaemia and arrhythmia.', null],
  ['prednisolone', 'ibuprofen', 'MODERATE', 'Corticosteroid plus NSAID substantially increases the risk of peptic ulcer and gastrointestinal bleeding.', 'Add gastroprotection, or use acetaminophen'],
  ['theophylline', 'ciprofloxacin', 'MAJOR', 'Ciprofloxacin inhibits theophylline metabolism, risking seizures and arrhythmia.', null],
];

async function seedDrugInteractions() {
  console.log('\n🌱  Seeding curated drug interaction table...\n');

  try {
    let created = 0;
    let updated = 0;

    for (const [rawA, rawB, severity, mechanism, alternative] of INTERACTIONS) {
      // Normalise and order the pair so lookups are deterministic.
      const a = normaliseDrugName(rawA);
      const b = normaliseDrugName(rawB);
      const [drug_a, drug_b] = a < b ? [a, b] : [b, a];

      const existing = await prisma.drugInteraction.findUnique({
        where: { drug_a_drug_b: { drug_a, drug_b } },
        select: { id: true },
      });

      await prisma.drugInteraction.upsert({
        where: { drug_a_drug_b: { drug_a, drug_b } },
        update: { severity, mechanism, suggested_alternative: alternative },
        create: { drug_a, drug_b, severity, mechanism, suggested_alternative: alternative },
      });

      if (existing) {
        updated += 1;
      } else {
        created += 1;
        console.log(`   ✔  ${drug_a} + ${drug_b}  [${severity}]`);
      }
    }

    const total = await prisma.drugInteraction.count();
    console.log(`\n✅  Done. ${created} created, ${updated} updated, ${total} pairs in table.\n`);
  } catch (err) {
    console.error('❌  Failed to seed drug interactions:', err);
    process.exitCode = 1;
  } finally {
    await prisma.$disconnect();
  }
}

seedDrugInteractions();
