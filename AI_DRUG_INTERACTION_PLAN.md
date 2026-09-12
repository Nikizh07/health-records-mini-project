# Plan: AI Cross-Clinic Medication Conflict Detector

**Status: Phases 1-2 complete (2026-09-12). Phases 3-4 pending.**
Approved 2026-09-12; Phase 4 revised the same day to be provider-agnostic.

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

### Decisions taken

| Decision | Choice |
|---|---|
| Knowledge source | Curated local `drug_interactions` table **+** an LLM layer |
| AI provider | **Pluggable** — any OpenAI-compatible endpoint, AWS Bedrock, or AWS SageMaker |
| Provider config | Env vars only |
| Prompt | A markdown file in the repo, not inlined in code |
| Trigger | Pre-flight on save |
| Enforcement | Warn, allow override, capture a reason |
| AI unavailable | **Fail open** — save proceeds, flagged as AI-unchecked; the curated table still fires |
| Persistence | Store every check + its outcome |

The two-source design is what makes fail-open safe: the deterministic table lookup needs no network and
always runs, so an outage degrades the feature instead of disabling it.

---

## Architecture

One AI call per save, on top of a deterministic core:

```
POST /api/records/interaction-check
  │
  ├─ 1. Load patient's cross-clinic prescription history  (existing unfiltered query pattern)
  ├─ 2. Filter to still-active meds                       (parse `duration` vs `visit_date`)
  │
  ├─ 3a. DETERMINISTIC: naive-normalise names → look up `drug_interactions`   ← always runs
  ├─ 3b. AI: one call through the provider adapter, prompt rendered from prompts/
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
account or endpoint. Because the design fails open, the deterministic table is the *load-bearing* safety
component and the AI is an enhancement — so Phases 1-3 deliver a complete, demoable, offline-capable
feature, and Phase 4 can slip without stranding half-built work.

| Phase | Scope | Depends on | External deps |
|---|---|---|---|
| 1 | ✅ **Done** — schema + deterministic checker + check endpoint | — | none |
| 2 | ✅ **Done** — audit wiring into record creation | 1 | none |
| 3 | Flutter banner + override UI + tests | 2 | none |
| 4 | Pluggable AI layer + prompt file | 1 | one AI endpoint (any) |

---

## Phase 1 — Deterministic core (backend, no AI) ✅ DONE

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
  ai_provider     String?                     // which adapter answered, for debugging
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
4. Sort `CRITICAL → MINOR`, return `{ conflicts, ai_available: false, ai_provider: null }`.

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

### Phase 1 outcome (2026-09-12)

Shipped, and verified against the local database and over HTTP with a real doctor token:

| File | Notes |
|---|---|
| `prisma/schema.prisma` | `DrugInteraction`, `InteractionCheck`, `InteractionSeverity` |
| `prisma/migrations/20260912122022_add_drug_interactions/` | tables, enum, FKs, unique pair index |
| `prisma/migrations/20260912122039_add_history_indexes/` | `medical_records.patient_id`, `prescriptions.record_id` |
| `utils/drugName.js` | **not in the original plan** — normalisation was pulled out of the checker into a shared util because the seeder must use the identical function, or table lookups silently miss |
| `utils/prescriptionWindow.js` | `parseDurationDays` also handles UK shorthand (`3/52`) |
| `services/interactionChecker.js` | AI seam marked for Phase 4 |
| `scripts/seed-drug-interactions.js` | 56 curated pairs, idempotent via upsert |
| `controllers/record.controller.js` | `checkDrugInteractions` handler |
| `routes/record.routes.js` | `POST /api/records/interaction-check`, declared above the `/:id` routes |

Checks that passed: cross-clinic CRITICAL conflict naming the source clinic and date; an expired course
correctly ignored; a safe drug returning nothing; CRITICAL sorted above MAJOR; empty prescription list
handled; 400s on bad `patient_id` and missing `prescriptions`; 401 without a token; audit row written.
All test rows were removed afterwards.

**Known gap, deliberately not filled:** the checker compares new drugs only against *existing* active
ones. Two conflicting drugs prescribed in the *same* visit do not fire. Closing it means including the
new drugs on both sides of the candidate-pair loop in `findTableConflicts` — a few lines — but it was
outside the approved scope, so it is left as a decision for Phase 2 or later.

---

## Phase 2 — Audit wiring (backend) ✅ DONE

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

### Phase 2 outcome (2026-09-12)

Shipped in `controllers/record.controller.js` only — no new files, no schema change, no new route
(`POST /api/records` already existed). Three edits: `check_id` / `override_reason` accepted off the body,
a new step 6 that validates the check before the record is written, and a link-back write after it.

Conflicts are re-read from the stored `interaction_checks` row, never from the request body, so a client
cannot save a conflicted record by omitting them.

Two decisions that refine the plan:

- **`overridden` is set to `true` only when the stored check actually recorded conflicts.** Writing
  `true` unconditionally, as the plan's wording implied, would mark clean checks as overridden and make
  the audit trail claim a doctor dismissed a warning that was never shown.
- **A check row is single-use.** Saving a second record against a check that already has a `record_id`
  is refused with 400, otherwise the audit trail cannot say which save the doctor was warned about.
  Not in the original plan; added because it is cheap and the row is the audit record.

The link-back update follows the file's existing post-create convention (`.catch` + warn, as with the
appointment auto-complete): the record is already committed at that point, so a failed audit write is
logged rather than turned into a misleading 500.

Verified against a real PostgreSQL 16 database by driving the real controller (25 assertions, all
passing, fixtures removed afterwards): cross-clinic CRITICAL conflict detected; conflicted save refused
with 400 naming `override_reason`; whitespace-only reason also refused; no record written on refusal;
with a reason the save returns 201 and the check row carries `record_id`, `overridden = true` and the
trimmed reason; a consumed check refused on reuse; a check belonging to a different patient refused;
a clean check saves with no reason and stores `overridden = false`; malformed `check_id` → 400 and
unknown `check_id` → 404, each for the right reason; and with no `check_id` at all the endpoint behaves
exactly as before. The server boots and both routes still gate unauthenticated callers at 401.

**Not covered:** no test over real HTTP with a Firebase token — the assertions drive the controller
directly. The route and its middleware were unchanged by this phase, so only the auth gate was smoke
tested.

---

## Phase 3 — Doctor UI (Flutter)

Goal: the feature is visible and usable end to end, still with no AI dependency.

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

## Phase 4 — Pluggable AI layer

Goal: catch brand names, misspellings and off-table pairs, through **whatever AI endpoint you point it
at** — and never become a hard dependency.

### 4.1 Layout

```
backend/
├── prompts/
│   └── drug-interaction.md              # the prompt — edited without touching code
└── services/
    └── ai/
        ├── index.js                     # provider registry + complete() + isAiEnabled()
        ├── promptLoader.js              # load + render {{placeholders}}
        ├── parseJson.js                 # tolerant JSON extraction from model text
        └── providers/
            ├── openaiCompatible.js      # fetch, zero deps
            ├── bedrock.js               # lazy @aws-sdk/client-bedrock-runtime
            └── sagemaker.js             # lazy @aws-sdk/client-sagemaker-runtime
```

### 4.2 The adapter contract

Every provider file exports exactly this, and nothing else:

```js
module.exports = {
  name: 'openai-compatible',
  isConfigured(),                                  // -> bool, from env only
  async complete({ system, user, maxTokens, temperature, signal }), // -> string
};
```

That one-method surface is what keeps this cheap to extend: **adding a provider is one new file plus one
line in the registry**, with no change to `interactionChecker.js`.

`services/ai/index.js`:
- Picks the adapter by `AI_PROVIDER` from a registry object; unknown value → log once, treat as disabled.
- `isAiEnabled()` = `AI_ENABLED !== 'false'` && the adapter's `isConfigured()`.
- `complete()` wraps the adapter with an `AbortController` timeout (`AI_TIMEOUT_MS`, default 8000) and
  normalises every failure into one thrown `AiUnavailableError`, so the checker has a single thing to catch.
- **`require` the AWS SDKs lazily inside the adapter**, so someone using an OpenAI key never has to install
  `@aws-sdk/*`. List both AWS packages under `optionalDependencies`.

**`openaiCompatible.js`** — one `fetch` POST to `${AI_BASE_URL}/chat/completions`, `Authorization: Bearer
${AI_API_KEY}`, body `{ model, messages: [{role:'system'},{role:'user'}], temperature, max_tokens }`, read
`data.choices[0].message.content`. Set `response_format: { type: 'json_object' }` when `AI_JSON_MODE=true`
— most compat endpoints support it, a few don't, hence the flag.

**`bedrock.js`** — `BedrockRuntimeClient` + `ConverseCommand` (the unified API; it handles Llama's prompt
format so you don't hand-roll `<|begin_of_text|>` templating). Credentials come from the default AWS chain
— `AWS_PROFILE` locally, the ECS **task role** in prod, no access keys in env, matching how
`AWS_MIGRATION_PLAN.md` §1.6 handles S3.

**`sagemaker.js`** — `SageMakerRuntimeClient` + `InvokeEndpointCommand` against `AI_SAGEMAKER_ENDPOINT`.
⚠️ SageMaker has **no standard payload shape** — it depends on the serving container. Target the common
HuggingFace TGI format (`{ inputs, parameters: { max_new_tokens, temperature } }`) and put the request and
response mapping in two clearly-commented functions at the top of the file, so retargeting a different
container is a local edit.

### 4.3 The prompt file — `prompts/drug-interaction.md`

Lifted out of the code entirely, version-controlled so prompt changes show up in git diffs. One file, split
by a `---USER---` delimiter line:

```md
You are a clinical pharmacology assistant helping a doctor at a walk-in clinic...
Return JSON only, matching exactly: { "conflicts": [ { ... } ] }
...

---USER---

## Patient's active medications (all clinics)
{{activeMedications}}

## Drugs about to be prescribed
{{newPrescriptions}}

## Reference interaction table
{{interactionTable}}
```

`promptLoader.js` exports `renderPrompt(name, vars)` — reads `prompts/<name>.md`, splits on `---USER---`,
substitutes `{{key}}`, returns `{ system, user }`. **Cache the file read when
`NODE_ENV === 'production'`; re-read every call otherwise** so prompt iteration needs no restart.

### 4.4 AI leg in `services/interactionChecker.js`

Plug into the seam left at Phase 1:

```js
if (!isAiEnabled()) return { conflicts: tableConflicts, ai_available: false, ai_provider: null };
try {
  const { system, user } = renderPrompt('drug-interaction', {...});
  const text = await complete({ system, user, temperature: 0, maxTokens: 1500 });
  aiConflicts = parseJson(text);            // tolerant; throws on unusable output
} catch (err) {
  console.error('❌ AI interaction check failed:', err.message);
  return { conflicts: tableConflicts, ai_available: false, ai_provider: null };   // ← fail open
}
```

`parseJson.js` — models do not reliably emit bare JSON, and only some endpoints support a JSON mode.
Extract the first balanced `{...}` (ignoring ``` fences), `JSON.parse` inside try/catch, validate each
conflict has the required keys and a known severity, drop malformed entries. **A parse failure is treated
exactly like an outage**, which is why this lives next to the adapters rather than in any one of them.

**Merge** by normalised unordered drug pair. Table severity wins where both legs hit; keep the model's
`explanation` and `suggested_alternative`. Sort `CRITICAL → MINOR`.

### 4.5 `scripts/test-ai-provider.js` (new) — the integration shortcut

A standalone CLI that renders the real prompt with a canned warfarin/ibuprofen case, calls whatever
provider is configured, and prints the raw text, the parsed conflicts, and the elapsed time.

This is what makes a new endpoint cheap to adopt: **point the env at it, run one command, see if it
works** — no DB, no Flutter build, no clicking through the app.

### 4.6 Env — `.env.example`

```bash
# ── AI provider (any OpenAI-compatible endpoint, Bedrock, or SageMaker) ──
AI_ENABLED=true
AI_PROVIDER=openai-compatible        # openai-compatible | bedrock | sagemaker
AI_TIMEOUT_MS=8000
AI_MAX_TOKENS=1500

# openai-compatible — works with OpenAI, Gemini, Groq, OpenRouter, Ollama, vLLM, LM Studio…
AI_BASE_URL=https://api.openai.com/v1
AI_API_KEY=
AI_MODEL=gpt-4o-mini
AI_JSON_MODE=true
#   Gemini : AI_BASE_URL=https://generativelanguage.googleapis.com/v1beta/openai
#   Groq   : AI_BASE_URL=https://api.groq.com/openai/v1
#   Ollama : AI_BASE_URL=http://localhost:11434/v1   (AI_API_KEY can be any non-empty string)

# bedrock — credentials come from the AWS chain (AWS_PROFILE locally, ECS task role in prod)
# AI_PROVIDER=bedrock
# AWS_REGION=ap-south-1
# AI_MODEL=<from: aws bedrock list-foundation-models --region ap-south-1 --by-provider meta>

# sagemaker
# AI_PROVIDER=sagemaker
# AWS_REGION=ap-south-1
# AI_SAGEMAKER_ENDPOINT=my-llama-endpoint
```

`package.json`: add `@aws-sdk/client-bedrock-runtime` and `@aws-sdk/client-sagemaker-runtime` under
**`optionalDependencies`**. `AWS_MIGRATION_PLAN.md` §1.6: note that if the deployed provider is Bedrock or
SageMaker, the ECS **task role** needs `bedrock:InvokeModel` / `sagemaker:InvokeEndpoint` on that resource.

> **Done when:** `node scripts/test-ai-provider.js` succeeds against at least two different providers
> (e.g. a local Ollama and one hosted key) with no code change — only `.env` edits. Then, through the API:
> submitting the *brand* name "Brufen" instead of "Ibuprofen" for a warfarin patient still returns the
> CRITICAL conflict with `ai_available: true` (the table alone cannot do this, so it proves the AI leg adds
> value). Finally set `AI_ENABLED=false` and confirm the endpoint still returns 200 with table-only
> conflicts.

---

## Cross-phase verification

Run at the end, once all four phases are in:

1. **Fail-open:** `AI_ENABLED=false` → warfarin + ibuprofen still returns CRITICAL, `ai_available: false`.
2. **Provider portability:** `scripts/test-ai-provider.js` passes against two different providers, env-only.
3. **AI value-add:** "Brufen" is caught, `ai_available: true`, `ai_provider` recorded on the check row.
4. **Resilience:** point `AI_BASE_URL` at an unreachable host → 200 with table-only conflicts within the
   timeout, error logged not thrown.
5. **End to end** (you drive the browser): rebuild the doctor web profile build, log in as Dr. Default
   Doctor, open a patient with a warfarin history, add ibuprofen, hit save → red banner with Clinic A's
   name and date → save refused without a reason → enter one → record saves and the appointment flips to
   completed.
6. **Audit:** query `interaction_checks` — one row, `record_id` set, `overridden = true`, reason stored.
7. `cd mobile_app && flutter analyze && flutter test`.

## Docs to update (per `CLAUDE.md`)

- `SNAPSHOT.md` — after Phase 1 add `services/interactionChecker.js`, `utils/prescriptionWindow.js`,
  `scripts/seed-drug-interactions.js`, migration #3; after Phase 4 add the `prompts/` and `services/ai/`
  trees and `scripts/test-ai-provider.js`.
- `MEMORY.md` — a dated note per phase as it lands, replacing the "plan only" status.
