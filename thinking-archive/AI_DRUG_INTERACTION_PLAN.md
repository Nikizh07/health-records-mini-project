# Plan: AI Cross-Clinic Medication Conflict Detector

**Status: all four phases built (Phase 4 on 2026-09-13). Phase 4 is verified against fake providers only; a real model run is still to do.**
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
| 3 | ✅ **Done** — Flutter banner + override UI + tests | 2 | none |
| 4 | ✅ **Built** — pluggable AI layer + prompt file (real-model check pending) | 1 | one AI endpoint (any) |

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
  "confidence": "CERTAIN",
  "scope": "EXISTING"
}
```

`scope` says which leg found the pair, and the client must branch on it:

| `scope` | Meaning | `clinic_name` / `prescribed_on` |
|---|---|---|
| `EXISTING` | A new drug against something the patient is already taking, at any clinic | populated |
| `SAME_VISIT` | Two drugs in *this* prescription conflicting with each other | **both `null`** — neither has been dispensed, so there is nothing to attribute |

A drug pair is reported once. Where the patient is already on one of two new drugs, the richer
`EXISTING` conflict wins, so the clinic and date are never lost to a same-visit duplicate.

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

**Known gap at the time: closed 2026-09-12** (see *Same-visit conflicts* below). The checker originally
compared new drugs only against *existing* active ones, so two conflicting drugs prescribed in the same
visit did not fire.

---

## Same-visit conflicts ✅ DONE (2026-09-12)

Closed the gap Phase 1 left open, **before** the Phase 3 banner was built rather than after, because the
conflict object the banner renders changes shape: a same-visit conflict has no source clinic or date.
Retrofitting it later would have meant rebuilding the banner.

It also mattered on its own. A walk-in doctor writing a fresh prescription set — warfarin *and*
ibuprofen in one visit — got a clean result on a CRITICAL interaction. Once a banner exists and doctors
trust it, a silent miss on the case entirely within one doctor's control is worse than no banner.

In `services/interactionChecker.js`, `findTableConflicts` now runs two legs:

1. each new drug against the patient's active medications (`scope: 'EXISTING'`, as before);
2. each pair *within* the new prescription list (`scope: 'SAME_VISIT'`, `clinic_name` and
   `prescribed_on` both `null`, `confidence: 'CERTAIN'` — nothing is being assumed about a past course).

The load-bearing change is the removal of an early return: the function used to bail out when the
patient had no active medications, which is exactly the case where a same-visit pair is the *only*
thing that can fire. The candidate-pair query gained a third `OR` clause for new-against-new.

Deduplication moved from a directional key (`new|existing`) to the **ordered** pair, so one interaction
is reported once however it is reached. The existing leg runs first, so where both legs find the same
pair the `EXISTING` conflict — which names a clinic and a date — is the one kept.

Phase 2 needs no change: a same-visit conflict is stored in the check row like any other and demands an
`override_reason` through the same path.

**Verified** by `scripts/test-interactions.js` (see below): 80 assertions, including that the pair fires
with no history at all, is reported once regardless of drug order, that three new drugs yield all three
pairs, that a drug never conflicts with itself, and that the cross-clinic behaviour is unchanged.

### Regression suite — `scripts/test-interactions.js` (new)

Runs the whole feature against a real database over real HTTP, so `authenticate`, `requireRole`, the
controller and the error handler all execute. Firebase is stubbed in `require.cache` before the app
loads, so **no service account, no device and no app build are needed**:

```bash
cd backend && DATABASE_URL=postgresql://... node scripts/test-interactions.js
```

It creates its own timestamped fixtures and deletes them at the end. Point it at a development database.

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

## Phase 3 — Doctor UI (Flutter) ✅ DONE

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
`_DoctorAppointmentCard` status-chip style. Per conflict show: new drug, existing drug, explanation,
suggested alternative, and **branch on `scope`** — an `EXISTING` conflict names the clinic and date
("Clinic A, 15 Jan"), while a `SAME_VISIT` one has neither and must be phrased as both drugs being in
this prescription. Rendering a `SAME_VISIT` conflict with the `EXISTING` layout prints a null clinic. When `_aiUnavailable`, show a muted amber note
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

### Phase 3 outcome (2026-09-13)

`flutter analyze` clean, `flutter test` 12 passed / 2 skipped. The feature is now reachable by a doctor:
the app finally sends a `check_id`, so Phases 1-2 stop being dead code.

| File | Change |
|---|---|
| `lib/data/services/record_service.dart` | `checkDrugInteractions()`; `createMedicalRecord` gained `checkId` / `overrideReason` |
| `lib/presentation/screens/doctor/doctor_screens.dart` | pre-flight state, the reworked save flow, `_InteractionBanner` + `_ConflictTile`, `onChanged` on every prescription field |
| `test/clinic_flow_test.dart` | fake gained the check; six new cases |
| `test/interaction_contract_test.dart` | **new** — client/server contract, skips without a live backend |

Three decisions that depart from the plan as written:

- **A clean check saves in the same press.** The plan said the first press always runs the check and
  returns without saving. Taken literally that makes every clean prescription — the common case — a
  two-click save for no benefit. Now: conflicts found → banner and stop; nothing found → fall straight
  through to the save, still sending the `check_id` so the audit row is written and linked.
- **The "AI check unavailable" note rides with the banner instead of standing alone.** `ai_available` is
  `false` on every response until Phase 4 exists, so a standalone note would be permanent furniture that
  doctors learn to ignore. Its real job is qualifying a list that is being shown — "this may be
  incomplete". With nothing found the screen makes **no claim at all**, which still honours the rule
  against a green all-clear that cannot be backed up.
- **A check that cannot be reached warns once, then lets the save through.** Not in the plan. If the
  endpoint is unreachable the doctor is told, and a second press records the visit with no `check_id`.
  A walk-in clinic on a flaky connection must still be able to write the record; the alternative traps
  the doctor in a failing call with no way to save.

Testing notes for whoever comes next:

- The visit form scrolls, so `tester.tap()` on the save button **misses** on an 800px-tall test view.
  Call `tester.ensureVisible(button)` first — the original Ctrl+Enter test never hit this because a key
  event needs no hit test.
- The Ctrl+Enter test's expected payload changed: a clean save now carries `'check_id': 'chk-1'` and a
  null `override_reason`.
- `test/interaction_contract_test.dart` is the only thing that proves the Dart client and the Node API
  agree on field names — everything else uses a fake. It needs `HttpOverrides.global = null` (flutter_test
  fails real requests by default) and skips itself unless `TEST_ID_TOKEN` / `TEST_PATIENT_ID` are defined,
  so CI stays green. It has been run for real against the backend and passes.

**Not done:** the browser walkthrough in the "Done when" above is still yours to drive — the widget tests
cover the logic and the wording, not how it actually looks on screen.

---

## Phase 4 — Pluggable AI layer ✅ BUILT

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

### Phase 4 outcome (2026-09-13)

| File | Notes |
|---|---|
| `prompts/drug-interaction.md` | system and user halves split by `---USER---` |
| `services/ai/index.js` | registry, `isAiEnabled()`, `complete()`, **and** prompt rendering and JSON parsing |
| `services/ai/providers/openaiCompatible.js`, `bedrock.js`, `sagemaker.js` | the adapter contract as planned; AWS SDKs required lazily |
| `services/interactionChecker.js` | AI leg, attribution, merge |
| `scripts/test-ai-provider.js` | provider smoke test; no DB needed |
| `scripts/test-interactions.js` | +32 Phase 4 assertions against an in-process fake provider (112 total) |
| `.env.example`, `package.json` | `AI_*` vars; both AWS SDKs under `optionalDependencies` |
| `AWS_MIGRATION_PLAN.md` §1 | task-role permissions for Bedrock / SageMaker |

Departures from the plan:

- **`promptLoader.js` and `parseJson.js` were folded into `services/ai/index.js`.** Each was ~30 lines
  with one caller, so separate files added nothing. The provider files stay separate, as that is the
  extension point.
- **The model only names the pair; the server supplies everything else.** `clinic_name`,
  `prescribed_on`, `scope` and `confidence` come from the patient's real records. The model's names
  are matched back through `normaliseDrugName`, in either order, and a pair naming a drug that is in
  neither list is dropped. So a hallucinated drug can't reach the banner, and the clinic and date can
  never be invented. For this to work the prompt tells the model to copy names exactly.
- **AI-only conflicts carry `source: 'AI'`.** Where both legs hit a pair it stays `TABLE`, keeping the
  table's severity with the model's explanation. The app doesn't read `source`, so no Flutter change was
  needed.
- **The timeout is also enforced around the adapter** (`Promise.race`), not just passed as a `signal`, so
  an adapter that ignores the signal still can't hold a save open.
- **The whole curated table goes into the prompt** (56 rows, ~2k tokens). Marked with a `ponytail:`
  comment: filter it to the drugs involved once it grows into the hundreds.
- **SageMaker sends `do_sample: false` rather than `temperature: 0`**, because TGI rejects a zero
  temperature.

Verified:

- `scripts/test-interactions.js` passes 112/112 over real HTTP against the local DB. Phases 1-3 run with
  `AI_ENABLED=false` forced, so a key in `.env` can't change their results. The Phase 4 assertions cover:
  - Brufen caught with the clinic and date taken from the record, and `ai_provider` stored on the row.
  - The request shape: URL, bearer key, JSON mode, temperature 0, and a prompt that includes the
    cross-clinic med and the table but not expired courses.
  - Table severity winning over the model's, with the model's prose kept.
  - Hallucinated drugs, bad severities and malformed entries dropped.
  - JSON inside prose and code fences parsed.
  - A same-visit pair only the model knows about.
  - Fail-open on each failure mode, every time with 200, table-only results and `ai_available: false`:
    unparseable reply, wrong shape, HTTP 500, slower than the timeout (gave up at ~1.5 s),
    unreachable host, `AI_ENABLED=false` (provider never called), unknown `AI_PROVIDER`, missing key.
- `scripts/test-ai-provider.js` passes through all three adapters against local fakes: OpenAI-compatible
  over HTTP, Bedrock `Converse` over h2c via `AWS_ENDPOINT_URL`, and SageMaker `InvokeEndpoint`. With no
  config it exits 1 with a clear message; a blackholed host times out at the configured 1000 ms.

**Not done: no real model has been called.** No Ollama or API key is set up on this machine. The
"Done when" above still needs two real providers, e.g. a local Ollama and one hosted key. Until then
the prompt's quality, including whether a real model actually maps Brufen to ibuprofen, is unproven.

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

- ✅ `SNAPSHOT.md` — Phase 1 entries added (`services/interactionChecker.js`, `utils/drugName.js`,
  `utils/prescriptionWindow.js`, `scripts/seed-drug-interactions.js`, both new migrations), plus
  `scripts/test-interactions.js`. Phase 4 added the `prompts/` and `services/ai/` trees and
  `scripts/test-ai-provider.js`.
- ✅ `MEMORY.md` — dated notes recorded for Phase 1, Phase 2 and the same-visit fix.
- Phase 3 will add no backend files, but `SNAPSHOT.md` should gain the Flutter banner widget and the
  new `record_service.dart` method, and `MEMORY.md` a note that the feature is finally reachable by a
  doctor — until then Phases 1-2 are enforced by the API but nothing in the app sends a `check_id`.
