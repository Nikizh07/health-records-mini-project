# Plan: AI Cross-Clinic Medication Conflict Detector

**Status: plan only — no code written.** Approved 2026-09-12.

## Context

Patient medical history in this system is already cross-clinic by design — `getPatientMedicalHistory`
(`backend/controllers/record.controller.js:396-402`) deliberately does not filter by `clinic_id` or
`doctor_id`, so a doctor at Clinic B can already *see* what Clinic A prescribed. But nothing *uses*
that data: a doctor saving a new prescription gets no signal that it interacts dangerously with a drug
another clinic started. That is the gap this feature closes — turning the multi-tenant record store from
passive storage into an active safety check.

**Outcome:** when a doctor saves a visit record, the backend checks the new prescriptions against the
patient's still-active prescriptions from *every* clinic, and returns any dangerous interactions with
the culprit drug, the clinic that prescribed it, and the date. The doctor sees a red banner and must
give an override reason to proceed. Every check and override is stored for audit.

### Decisions taken (2026-09-12)

| Decision | Choice |
|---|---|
| Knowledge source | Curated local `drug_interactions` table **+** an LLM layer |
| Model | Open-source Llama on **AWS Bedrock** (not Claude), region `ap-south-1` |
| Trigger | Pre-flight on save |
| Enforcement | Warn, allow override, capture a reason |
| Bedrock unavailable | **Fail open** — save proceeds, flagged as AI-unchecked; the curated table still fires |
| Persistence | Store every check + its outcome |

The two-source design is what makes fail-open safe: the deterministic table lookup needs no network and
always runs, so an outage degrades the feature instead of disabling it.

---

## Architecture

One Bedrock call per save, on top of a deterministic core:

```
POST /api/records/interaction-check
  │
  ├─ 1. Load patient's cross-clinic prescription history  (existing unfiltered query pattern)
  ├─ 2. Filter to still-active meds                       (parse `duration` vs `visit_date`)
  │
  ├─ 3a. DETERMINISTIC: naive-normalise names → look up `drug_interactions`   ← always runs
  ├─ 3b. AI: one Bedrock/Llama call with {active meds, new drugs, curated table}
  │        → catches brand names, misspellings, and off-table pairs; writes the prose
  │        → on any failure: skip, set ai_available=false                      ← fail open
  │
  ├─ 4. Merge + dedupe by drug pair (table severity wins where both hit)
  └─ 5. Persist an `interaction_checks` row → return { check_id, conflicts[], ai_available }
```

The app then re-submits to `POST /api/records` with `check_id` (+ `override_reason` when conflicts were
shown). The create handler reads the stored conflicts from `interaction_checks` and links the row to the
new record — so the audit trail is server-derived, never trusted from the client.

---

# Implementation phases

Four phases, each a coherent commit that leaves the system working.

**The build order is deliberate: the AI leg is last.** It is the only part that depends on an external
account, region-specific model ids, and console-enabled model access. Because the design fails open, the
deterministic table is the *load-bearing* safety component and the AI is an enhancement — so Phases 1-3
deliver a complete, demoable, offline-capable feature, and Phase 4 can slip or fail without stranding
half-built work.

| Phase | Scope | Depends on | External deps |
|---|---|---|---|
| 1 | Schema + deterministic checker + check endpoint | — | none |
| 2 | Audit wiring into record creation | 1 | none |
| 3 | Flutter banner + override UI + tests | 2 | none |
| 4 | Bedrock/Llama leg | 1 | AWS account, Bedrock model access |

---

## Phase 1 — Deterministic core (backend, no AI, no AWS)

Goal: `POST /api/records/interaction-check` returns real cross-clinic conflicts from the curated table.

### 1.1 Schema — `prisma/schema.prisma` + migration #3

Two new models and one enum. Note `Prescription` today is free text only (`medicine_name` bundles the
strength, `dosage` conflates dose and frequency, there is no end date and no drug code) — the design
works around that rather than restructuring it.

```prisma
enum InteractionSeverity {
  MINOR
  MODERATE
  MAJOR
  CRITICAL
}

// Curated reference data. Seeded, not user-written.
model DrugInteraction {
  id                    String              @id @default(uuid()) @db.Uuid
  drug_a                String              // normalised generic, lowercase
  drug_b                String              // normalised generic, lowercase; store with drug_a < drug_b
  severity              InteractionSeverity
  mechanism             String              @db.Text
  suggested_alternative String?
  created_at            DateTime            @default(now())

  @@unique([drug_a, drug_b])
  @@index([drug_a])
  @@index([drug_b])
  @@map("drug_interactions")
}

// One row per check run. Audit trail + the server-side source of truth for what was shown.
model InteractionCheck {
  id              String    @id @default(uuid()) @db.Uuid
  patient_id      String    @db.Uuid
  doctor_id       String    @db.Uuid
  record_id       String?   @db.Uuid          // set when the record is actually saved
  checked_drugs   Json                        // the new prescriptions submitted
  conflicts       Json                        // merged conflict objects returned to the client
  ai_available    Boolean   @default(false)
  overridden      Boolean   @default(false)
  override_reason String?   @db.Text
  created_at      DateTime  @default(now())

  patient Patient        @relation(fields: [patient_id], references: [id], onDelete: Cascade)
  doctor  Doctor         @relation(fields: [doctor_id], references: [id], onDelete: Cascade)
  record  MedicalRecord? @relation(fields: [record_id], references: [id], onDelete: SetNull)

  @@index([patient_id])
  @@map("interaction_checks")
}
```

Add the back-relations (`interaction_checks InteractionCheck[]`) to `Patient`, `Doctor`, `MedicalRecord`.

**Also add in the same migration** — the check runs a patient-history query on the save hot path, and
these columns have no index today:

```sql
CREATE INDEX ON medical_records (patient_id);
CREATE INDEX ON prescriptions (record_id);
```

Generate with `npx prisma migrate dev --name add_drug_interactions`. Remember the datasource URL lives in
`prisma.config.ts`, not `schema.prisma`.

### 1.2 `scripts/seed-drug-interactions.js` (new)

Follows the existing `seed-*.js` convention. Seed ~50 well-known pairs with normalised lowercase generic
names, `drug_a < drug_b` ordering, and a real `mechanism` sentence. Must include the demo pair:
**warfarin + ibuprofen → CRITICAL**, alternative *acetaminophen*. Idempotent via `upsert` on the
`@@unique([drug_a, drug_b])`.

### 1.3 `utils/prescriptionWindow.js` (new, ~30 lines)

`isLikelyActive(prescription, visitDate, now)` — parses the free-text `duration` (`"5 days"`,
`"2 weeks"`, `"1 month"`, `"30 days"`) and compares `visit_date + duration` against now.

Safety rule: **when `duration` is unparseable, treat the med as active if `visit_date` is within the last
90 days.** Err toward showing a warning rather than missing one. Mark those results
`confidence: "ASSUMED"` so the banner can say "duration unclear".

### 1.4 `services/interactionChecker.js` (new, ~90 lines at this phase)

Exports `checkInteractions({ patientId, newPrescriptions })`:

1. `prisma.medicalRecord.findMany({ where: { patient_id }, include: { prescriptions: true, doctor: { include: { clinic: true } } } })` — same unfiltered cross-clinic shape as `getPatientMedicalHistory`. Clinic is the 3-hop `Prescription → MedicalRecord → Doctor → Clinic`.
2. Filter through `isLikelyActive`. Keep `{ medicine_name, dosage, duration, clinic_name, visit_date }`.
3. `normaliseDrugName()` — lowercase, strip strength tokens (`500mg`, `5ml`), strip form words
   (`tablet|capsule|syrup|injection`), collapse whitespace. Then one `prisma.drugInteraction.findMany`
   over the candidate pairs. Source `TABLE`.
4. Sort `CRITICAL → MINOR`, return `{ conflicts, ai_available: false }`.

Leave a clearly marked seam where the AI leg plugs in at Phase 4.

Conflict object returned to the client:

```json
{
  "new_drug": "Ibuprofen 400mg",
  "existing_drug": "Warfarin 5mg",
  "severity": "CRITICAL",
  "clinic_name": "Clinic A",
  "prescribed_on": "2026-01-15",
  "explanation": "Ibuprofen increases bleeding risk when combined with Warfarin.",
  "suggested_alternative": "Acetaminophen",
  "source": "TABLE",
  "confidence": "CERTAIN"
}
```

At this phase `explanation` comes from the table's `mechanism` column.

### 1.5 Controller + route

**New handler `checkDrugInteractions(req, res, next)`** in `controllers/record.controller.js` — body
`{ patient_id, prescriptions[] }`. Reuse the existing UUID/patient validation and
`getAuthenticatedDoctorId(req)`. Calls the service, writes the `interaction_checks` row, responds in the
house envelope:

```js
return res.status(200).json({
  success: true,
  data: { check_id, conflicts, ai_available },
});
```

In `routes/record.routes.js`:

```js
router.post('/interaction-check', requireRole('DOCTOR', 'ADMIN'), checkDrugInteractions);
```

**Must be registered above `router.get('/:id', ...)`** or the wildcard swallows it — the same pitfall is
already commented in `patient.routes.js` and `appointment.routes.js`.

Follow the file's conventions: validation errors returned inline (never thrown), unexpected errors to
`next(error)`, `'use strict'`, numbered `// ── n. ──` step comments.

> **Done when:** seed the table, give a test patient a warfarin record, then POST ibuprofen to
> `/api/records/interaction-check` via the Postman collection (`backend/postman/`) → a CRITICAL conflict
> comes back naming the other clinic and date, with `ai_available: false`, and an `interaction_checks`
> row exists.

---

## Phase 2 — Audit wiring (backend)

Goal: saving a record can be linked to a check, and a conflicted save demands a reason.

Modify `createMedicalRecord` to accept optional `check_id` and `override_reason`:

- Insert after the existing prescription validation and before the `prisma.medicalRecord.create` call.
- If `check_id` is present: load the row, verify it belongs to this patient. If it recorded conflicts,
  require a non-empty `override_reason` → else `400` with the standard
  `{ success: false, error: 'Bad Request', message: ... }` shape.
- After the record is created, update the check row with `record_id`, `overridden: true`, `override_reason`.
- If `check_id` is absent, behaviour is **unchanged** — this keeps the Postman collection and the
  current app build working while Phase 3 is in flight.

> **Done when:** via Postman, a `POST /api/records` carrying a `check_id` that had conflicts is rejected
> with 400 until an `override_reason` is supplied; once saved, the `interaction_checks` row has
> `record_id` set, `overridden = true`, and the reason stored.

---

## Phase 3 — Doctor UI (Flutter)

Goal: the feature is visible and usable end to end, still with zero AWS dependency.

### 3.1 `lib/data/services/record_service.dart`

Add a 4th method, same shape as the existing three (explicit `Authorization` header so the
`createApiClient()` refresh interceptor fires; check `statusCode` **and** `data['success']`; throw
`ApiException.fromDioException`):

```dart
Future<Map<String, dynamic>> checkDrugInteractions({
  required String idToken,
  required String patientId,
  required List<Map<String, String>> prescriptions,
}) async  // POST /records/interaction-check → { check_id, conflicts, ai_available }
```

Extend `createMedicalRecord` with optional `String? checkId, String? overrideReason`, added to the payload
with the existing conditional-key style.

### 3.2 `lib/presentation/screens/doctor/doctor_screens.dart`

New state on `_DoctorAddRecordScreenState` (alongside `_isSubmitting`):
`_isCheckingInteractions`, `List<Map<String, dynamic>> _conflicts`, `String? _checkId`, `bool _aiUnavailable`,
`_overrideReasonController` (dispose it).

Rework `_submitRecord` — insert between building `formattedPrescriptions` and the create call:

- If `_checkId == null` and there is at least one prescription → run the check, `setState` the results, and
  **return without saving**. The banner renders; the save button relabels to `Save Anyway`.
- If `_checkId != null` → require a non-empty override reason when `_conflicts` is non-empty (red SnackBar
  otherwise), then call `createMedicalRecord` with `checkId` + `overrideReason`.
- Invalidate `_checkId`/`_conflicts` whenever any prescription field changes, so an edited drug list is
  re-checked rather than saved against a stale verdict. Add listeners in `_PrescriptionEntry`, or clear on
  add/remove plus an `onChanged` on the medicine field.

New `_InteractionBanner` widget rendered just above the submit button. Follow the file's own conventions —
hardcoded English (this screen is entirely unlocalised) and the `Colors.red.shade50 / shade200 / shade700`
box pattern from `book_appointment_screen.dart:683-704`, with severity-coloured chips reusing the
`_DoctorAppointmentCard` status-chip style. Per conflict show: new drug, existing drug, **clinic name and
date**, explanation, suggested alternative. When `_aiUnavailable`, show a muted amber note
("AI check unavailable — showing known interactions only") rather than a green all-clear.

### 3.3 Tests — `test/clinic_flow_test.dart`

`_Records` already extends the real service with `super(dio: Dio())` and `recordServiceProvider` is already
overridden, so no harness change is needed. Add a `checkDrugInteractions` override backed by a settable
`List<Map<String, dynamic>> conflicts` field, and assert `created['check_id']` /
`created['override_reason']` on the spy.

Two new cases:
1. **Conflict path** — fake returns one CRITICAL conflict → banner text appears, first save does **not**
   call `createMedicalRecord`, entering a reason and saving again does, and the payload carries `check_id`
   and `override_reason`.
2. **Fail-open path** — fake returns `ai_available: false` with an empty conflict list → save proceeds and
   the muted "AI check unavailable" note is shown.

Use `await tester.pump()` rather than `pumpAndSettle()` after a save — the existing test documents that the
button spinner keeps animating behind the success dialog, and the new check spinner behaves the same way.

> **Done when:** `cd mobile_app && flutter analyze && flutter test` is green, and in the browser (you drive
> it) a doctor adding ibuprofen to a warfarin patient sees the red banner with Clinic A's name and date,
> is refused a save until a reason is entered, and then saves successfully.

---

## Phase 4 — Bedrock / Llama leg

Goal: catch brand names, misspellings and off-table pairs, and write better prose — without ever becoming
a hard dependency.

### 4.0 Pre-check (do this before writing any Phase 4 code)

Confirm the exact model id **and** that model access is enabled in the Bedrock console for the account:

```
aws bedrock list-foundation-models --region ap-south-1 --by-provider meta \
  --query 'modelSummaries[].modelId'
```

Llama is served in `ap-south-1` and the region supports APAC cross-region inference profiles, so expect
either an on-demand id (`meta.llama3-...`) or an `apac.`-prefixed inference-profile id. Put whichever the
command returns into `BEDROCK_MODEL_ID` — **do not hardcode a guessed id.** If this command returns
nothing usable, stop: Phases 1-3 already ship a working feature.

### 4.1 `config/bedrock.js` (new, ~25 lines)

Mirrors the shape of `config/prisma.js` — a lazily-created singleton client.

- `@aws-sdk/client-bedrock-runtime`, `BedrockRuntimeClient` + **`ConverseCommand`** (the unified API;
  it handles Llama's prompt format so you don't hand-roll `<|begin_of_text|>` templating).
- Region from `BEDROCK_REGION` (default `ap-south-1`), model from `BEDROCK_MODEL_ID`.
- Credentials resolve from the default AWS chain — `AWS_PROFILE` locally, the ECS **task role** in prod.
  No access keys in env, consistent with how `AWS_MIGRATION_PLAN.md` §1.6 handles S3.
- Export `isConfigured()` so the checker can skip the AI leg cleanly when unset.

### 4.2 AI leg in `services/interactionChecker.js`

Plug into the seam left at Phase 1. One `ConverseCommand`. System prompt: *a clinical pharmacology
assistant; you are given a patient's active medications, the drugs about to be prescribed, and a reference
interaction table; return JSON only.* Set `temperature: 0` and a modest `maxTokens` (~1500).

- Inline the full `drug_interactions` table in the prompt (it is small) so the model can match brand names
  and typos against it, and mark each conflict `source: "TABLE"` or `source: "MODEL"`.
- **Parse defensively** — Llama on Bedrock has no strict structured-output mode. Extract the first
  balanced `{...}`, `JSON.parse` inside try/catch, validate each conflict has the required keys and a known
  severity, and silently drop malformed entries. A parse failure is treated exactly like an outage.
- Wrap the whole leg in try/catch with a timeout (~8s). Any failure → `ai_available: false`, log with the
  house `❌` style, continue.

**Merge** by normalised unordered drug pair. Table severity wins where both legs hit; keep the model's
`explanation` and `suggested_alternative`. Sort `CRITICAL → MINOR`.

### 4.3 Config + infra

- `package.json`: add `@aws-sdk/client-bedrock-runtime`.
- `.env.example`: add `BEDROCK_REGION=ap-south-1`, `BEDROCK_MODEL_ID=...`, `AI_INTERACTION_CHECK_ENABLED=true`.
- `AWS_MIGRATION_PLAN.md` §1.6: add `bedrock:InvokeModel` on the target model ARN to the ECS **task role**.

> **Done when:** with `AWS_PROFILE` + `BEDROCK_MODEL_ID` set, submitting the *brand* name "Brufen" instead
> of "Ibuprofen" for a warfarin patient still returns the CRITICAL conflict and `ai_available: true` — the
> table alone cannot do this, so it proves the AI leg adds value. Then point `BEDROCK_MODEL_ID` at a wrong
> id and confirm the endpoint still returns 200 with table-only conflicts and `ai_available: false`.

---

## Cross-phase verification

Run at the end, once all four phases are in:

1. **Fail-open:** unset `BEDROCK_MODEL_ID` → warfarin + ibuprofen still returns CRITICAL, `ai_available: false`.
2. **AI value-add:** with Bedrock configured → "Brufen" is caught, `ai_available: true`.
3. **Resilience:** wrong model id → 200 with table-only conflicts, error logged not thrown.
4. **End to end** (you drive the browser): rebuild the doctor web profile build, log in as Dr. Default
   Doctor, open a patient with a warfarin history, add ibuprofen, hit save → red banner with Clinic A's
   name and date → save refused without a reason → enter one → record saves and the appointment flips to
   completed.
5. **Audit:** query `interaction_checks` — one row, `record_id` set, `overridden = true`, reason stored.
6. `cd mobile_app && flutter analyze && flutter test`.

## Docs to update (per `CLAUDE.md`)

- `SNAPSHOT.md` — after Phase 1 add `services/interactionChecker.js`, `utils/prescriptionWindow.js`,
  `scripts/seed-drug-interactions.js`, migration #3; after Phase 4 add `config/bedrock.js`.
- `MEMORY.md` — a dated note per phase as it lands, replacing the "plan only" status.
