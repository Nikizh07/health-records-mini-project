# Visual & Audio "Smart Prescriptions" via WhatsApp

## Context

A doctor prescribes medication and the patient leaves with a printed slip. An illiterate
migrant worker cannot read it — which pill is morning, which is night, how many to take.
They go home and take the wrong dose. This is the "last mile" failure of the whole record
system: the data is correct and the patient still gets it wrong.

This feature turns a saved prescription into a WhatsApp message the patient does not need
to read: voice notes in their language, and a pictogram (sun + pill = morning, moon + pill
= night). The doctor's workflow gains one button.

**The one hard constraint that shapes everything below:** the drug-interaction checker is
allowed to fail open, because a missed warning still leaves a doctor in the loop. This
feature is the opposite. A wrong schedule spoken to an illiterate patient is a dosing error
with *no literate reader downstream to catch it*. So this feature **fails closed** — if the
system cannot confidently describe a prescription, it does not describe it.

### Decisions taken

| Area | Decision |
|---|---|
| Schedule source | Structured chips on the prescription row, **AI pre-fills them** from the free text the doctor already types. AI does the work invisibly; the doctor confirms with a glance. |
| Safety gate | **Preview + confirm.** "Save & Send" saves the record, then shows the pictogram and the exact sentences that will be spoken. Nothing sends until the doctor confirms. |
| Languages | **en / hi / ta only**, matching the app's existing l10n. Any other `language_pref` falls back to English **and the preview says so** rather than silently sending the wrong language. |
| Pill identity | **Index + colour matched to the chart** — "medicine number one, the blue one". Needs no clinical data that isn't already there, and chart and audio can never disagree. |
| Delivery | Pluggable messaging layer; `twilio` default, `meta` alternative, `log` provider needing no credentials. |
| Voice | Pluggable TTS layer; `polly` / `google` / `mock`. |
| Pictogram | Deterministic SVG → PNG. Never AI image generation — a model that renders the wrong pill count is a patient-safety bug. |

All three new provider layers copy `backend/services/ai/` exactly: a `PROVIDERS` registry
object, an `isConfigured()` / `isEnabled()` pair, one error class, provider read per-call
from env, and a `scripts/test-*-provider.js` smoke test.

---

## Phase 0 — Unblock `main` (prerequisite, unrelated to this feature)

`main` currently **cannot boot**. Four files were committed with unresolved git conflict
markers, and `node --check backend/config/firebase.js` is a SyntaxError:

- `backend/config/firebase.js` — runtime break. `authenticate` requires it, so every
  request 500s. Resolve toward the `HEAD` side (it handles base64 and `\n`-escaped PEMs)
  but keep the newer side's decision that there is **no ADC fallback** — off GCP it can
  only fail later, at the first `verifyIdToken`.
- `backend/.env.example` — the `HEAD` side is the dead GCS world. Take the `d9f9611` side
  (`AWS_REGION`, `S3_BUCKET_NAME`); `GCS_BUCKET_NAME` is referenced nowhere. Salvage
  `HEAD`'s better `FIREBASE_SERVICE_ACCOUNT_JSON` comment.
- `README.md`, `SNAPSHOT.md` — documentation only.

**Verify:** `node --check` on every changed file, then `cd backend && npm run dev` reaches
"Server running" and `GET /api/health` answers 200.

---

## Phase 1 — Structured dose schedule (schema + deterministic core, no network)

The crux: `Prescription` has exactly three content columns — `medicine_name`, `dosage`,
`duration`, all free text. "Morning and night" exists only as prose inside `dosage`.

**Migration `20260921000000_add_dose_schedule`** — all columns nullable and additive, so
every existing read path is untouched:

```
prescriptions += slots            String[]   // ['MORNING','NIGHT']
                 food_relation    String?    // BEFORE | AFTER | WITH | ANY
                 pills_per_dose   Float?
                 prn              Boolean    @default(false)
                 prn_condition    String?    // "fever"
                 schedule_source  String?    // DOCTOR | AI | PARSED
```

`schedule_source` is the audit trail: it records whether the doctor typed it, the AI
guessed it, or a regex derived it. Phase 5 refuses to send anything still `null`.

**New `backend/utils/doseSchedule.js`** — pure, no DB, no network:

```js
parseDoseText(dosage, duration) -> {
  slots, food_relation, pills_per_dose, prn, prn_condition,
  days,            // via prescriptionWindow.parseDurationDays
  confidence       // CERTAIN | PARTIAL | NONE
}
SLOTS = ['MORNING','AFTERNOON','EVENING','NIGHT']
```

Handles the common shorthand: `1-0-1`, `1-1-1`, `OD/BD/TDS/QDS`, "twice daily", "morning
and night", "SOS"/"PRN"/"if fever", "before food"/"after meals". Anything it cannot place
returns `confidence: 'NONE'` — it must **never guess a slot**. Reuses
`prescriptionWindow.parseDurationDays` for the duration; that function already handles
`5 days`, `2 weeks`, `10d` and the UK `3/7` shorthand.

**New `backend/utils/language.js`** — the backend mirror of the Dart `parseLocale` in
`mobile_app/lib/providers/locale_provider.dart`:

```js
resolveLanguage(language_pref) -> { code: 'en'|'hi'|'ta', requested: 'Bengali', supported: false }
```

`supported: false` is the field the preview surfaces. Registration offers **eight**
languages and defaults to Bengali, so this is the common case, not an edge case.

**New `backend/scripts/test-dose-schedule.js`** — offline assertions in the style of
`test-s3-signing.js` (no DB, no network). Table-driven over ~40 real-world dosage strings,
including ones that must return `NONE`.

---

## Phase 2 — The AI autofill leg

**New `backend/prompts/dose-schedule.md`** — same convention as `drug-interaction.md`:
system half, a single `---USER---` line, user half with `{{placeholder}}` blocks that the
caller renders as pre-formatted bullet lists.

**New `backend/services/doseScheduleParser.js`**, shaped exactly like
`interactionChecker.js`:

```js
parseSchedules({ prescriptions }) -> {
  schedules: [...],        // one per prescription, in input order
  ai_available: boolean,
  ai_provider: string|null
}
renderSchedulePrompt(prescriptions)   // exported so the smoke test sends what production sends
```

1. Run `parseDoseText` on every row **first** — that result is the fallback and it already
   exists before the AI is touched.
2. `if (!isAiEnabled()) return deterministicOnly`.
3. Otherwise one `complete()` call, wrapped in a bare `try/catch` that returns the same
   deterministic fallback. Log `err.message` only.
4. **The model may only fill gaps.** Where the deterministic parse produced a slot, the
   model's answer for that field is discarded. The model never overrides a regex hit and
   never invents a drug name — same clamp as `attributeAiConflicts`.

`extractJsonObject` in `services/ai/index.js` is currently private. Export it (a one-line
change) rather than duplicating the balanced-brace scanner.

**New endpoint `POST /api/records/schedule-parse`** — body `{prescriptions:[...]}`,
gated by `requirePermission('record:write')` **only**. It touches no patient data, so it
deliberately does *not* go through `requirePatientAccess`; keeping it patient-free is what
lets the form autofill as the doctor types, before a patient is even selected.

Declare it alongside `/interaction-check`, i.e. **before** `/:id`, or the literal path gets
swallowed by the parameterised route.

---

## Phase 3 — Message composition (deterministic, no network)

**New `backend/messages/prescription.{en,hi,ta}.json`** — the spoken script comes from
**templates, not the LLM**. The model never writes a word the patient hears. Templates are
reviewable by a clinician and consistent across every patient:

```json
{
  "greeting": "{{name}}, yeh aapki dawai hai.",
  "scheduled": "Dawai number {{index}}, {{colour}} wali. {{slots}} {{food}}. {{days}} din tak.",
  "prn":       "Agar {{condition}} ho, toh dawai number {{index}} lena, {{colour}} wali.",
  "slots":     { "MORNING": "subah", "NIGHT": "raat ko" },
  "food":      { "AFTER": "khana khane ke baad" },
  "colours":   { "BLUE": "neeli", "RED": "laal" }
}
```

**New `backend/services/patientMessage/script.js`**

```js
buildScript(record, language) -> {
  language_used, requested_language, supported,
  segments: [ { key, index, text, gloss } ]   // gloss = the English rendering
}
```

`gloss` is what the doctor reads in the preview to verify a Hindi or Tamil sentence they
may not speak. One segment per prescription, so each becomes its own voice note, exactly
as in the pitch.

**New `backend/services/patientMessage/pictogram.js`**

```js
buildSvg(schedules, palette) -> string
rasterise(svg) -> Promise<Buffer|null>     // null when the rasteriser is absent
```

A hand-written SVG grid: one row per medicine, columns for morning / afternoon / evening /
night, a filled pill glyph in the cells that apply, a colour swatch and a large numeral at
the row head matching what the audio says. Icons are inline SVG paths committed to the
repo — nothing is fetched at render time.

`@resvg/resvg-js` as an **optionalDependency**, lazily required inside `rasterise()`,
exactly like the AWS SDKs in the AI providers. If it is missing, `rasterise` returns `null`
and the send proceeds with audio + text only. The image is the one component allowed to
fail soft — it is an aid, not the instruction.

**New `backend/scripts/test-patient-message.js`** — offline: every template key present in
all three languages, no unfilled `{{placeholder}}` survives rendering, a `NONE`-confidence
schedule produces no scheduled segment, and the SVG contains one row per prescription.

---

## Phase 4 — TTS provider layer

**New `backend/services/tts/index.js`** + `providers/{polly,google,mock}.js`. Contract
mirrors the AI layer:

```js
{ name, isConfigured(), synthesize({ text, languageCode, signal }) -> Buffer }
// index.js exports: { TtsUnavailableError, isTtsEnabled, synthesize }
```

- `polly` — lazy `require('@aws-sdk/client-polly')`, optionalDependency, credentials from
  the default AWS chain like `config/s3.js`. Env: `TTS_PROVIDER`, `AWS_REGION`, `TTS_VOICE_*`.
- `google` — bare `fetch` against the REST endpoint with an API key, no SDK, following
  `openaiCompatible.js`.
- `mock` — returns a tiny fixed WAV so the whole pipeline runs locally with no credentials.

> **Verify before committing to a provider.** I have not confirmed which Indian-language
> voices each provider currently ships. Hindi is widely available; **Tamil is the one to
> check** — do not assume it exists on a given provider. First task of this phase is to
> query the provider's own voice list (`aws polly describe-voices --region ap-south-1`, or
> Google's `voices.list`) and pick the provider from the result. If the chosen provider has
> no Tamil voice, `resolveLanguage` degrades `ta` → `en` and the preview says so — the same
> honest-degradation path already built in Phase 1 for Bengali.

**Generalise `backend/config/s3.js` without touching the report path.** It is currently
hardcoded to the `report_file_url` field. Add two primitives and re-express the existing
two in terms of them, so all current callers keep working unchanged:

```js
putObject(buffer, key, mimetype)          // what putReport already does
signKey(key, ttlSeconds = URL_TTL_SECONDS) -> string|null
putReport  = (b,k,m) => putObject(b,k,m)
signReport = (record) => ...signKey(record.report_file_url)...
```

Key convention, following `reports/<recordId>/…`:
`messages/<recordId>/<messageId>/audio-<n>.mp3` and `.../chart.png`. The `messages/` prefix
is what lets the IAM policy scope separately from `reports/*`.

Note `BUCKET` is captured at module load — `scripts/test-s3-signing.js` already documents
the `delete require.cache[...]` workaround for tests.

---

## Phase 5 — Messaging layer, delivery record, send endpoint

**Migration `20260921010000_add_patient_messages`:**

```
model PatientMessage {
  id, record_id, patient_id, doctor_id,
  language          String
  status            MessageStatus   // QUEUED SENT DELIVERED FAILED
  provider          String?
  provider_message_id String?
  error             String?
  payload           Json            // the exact segments + asset keys that were sent
  created_at, sent_at
}
patients += whatsapp_opt_in     Boolean @default(false)
            whatsapp_opt_in_at  DateTime?
```

`payload` stores what was actually sent, not what would be regenerated — the audit has to
survive a later template edit.

**New `backend/services/messaging/index.js`** + `providers/{twilio,meta,log}.js`:

```js
{ name, isConfigured(), send({ to, body, media }) -> { providerMessageId } }
// media: [{ buffer, mimetype, filename, url }]
```

The contract carries **both** `buffer` and `url` because the two real providers need
opposite things, and this is the single most important detail in the phase:

- **Twilio** fetches `MediaUrl` from the public internet. It needs `url` — a presigned S3
  URL. Which means **the Twilio path cannot work until the S3 bucket actually exists**;
  per `MEMORY.md`, nothing is provisioned on AWS yet. It also means the 900-second
  presigned TTL must comfortably outlive Twilio's fetch (it does, but the TTL is now
  load-bearing for a second reason — worth a comment at `URL_TTL_SECONDS`).
- **Meta Cloud API** uploads the bytes first to obtain a `media_id`, then sends that. It
  needs `buffer` and **no public URL at all** — which makes it the better fit for local
  and Render testing, at the cost of business verification up front.
- **`log`** writes the assets to a scratch dir and prints the transcript. This is the
  provider the demo runs on, and the only one that works with zero credentials and zero
  AWS.

Both real adapters use bare `fetch` — Twilio's API is form-encoded POST with basic auth,
Meta's is JSON with a bearer token. No SDK, no new dependency, consistent with
`openaiCompatible.js`.

**New `backend/services/patientMessage/send.js`** — the orchestrator: resolve language →
build script → synthesize one audio per segment → build + rasterise the pictogram → put
assets → send → update the row.

**New `backend/controllers/patientMessage.controller.js`** and three routes on
`record.routes.js`, each `requirePermission('message:send')` →
`requirePatientAccess(<ACTION>, fromRecord)`:

| Route | Purpose |
|---|---|
| `POST /records/:id/patient-message/preview` | Builds the script + pictogram, stores nothing, sends nothing. Returns segments with glosses, the chart as a data URI, `language_used`/`supported`, and `blockers`. |
| `POST /records/:id/patient-message/send` | Creates the `QUEUED` row, does the work, updates to `SENT`/`FAILED`. |
| `GET /records/:id/patient-message` | Latest status, for the record detail screen. |

**New permission `message:send`**, granted to `DOCTOR`. `backend/scripts/test-auth-rbac.js`
generates its matrix from `config/permissions.js` and **fails if a permission has neither
an `ENDPOINTS` entry nor a `LATER` entry** — so this phase must add the row, not just the
permission.

**Fail-closed rules, enforced server-side** (the UI must not be the only guard):

1. `whatsapp_opt_in` false → 409 `{code:'NO_WHATSAPP_CONSENT'}`.
2. Any prescription whose schedule is still unset or `prn` without a condition → 400
   `{code:'SCHEDULE_INCOMPLETE', prescription_ids}`. This is the fail-closed promise: an
   unparseable prescription blocks the send rather than being described vaguely.
3. Patient phone missing or not E.164 via `utils/phone.js` → 400.

**On async vs synchronous — I recommend against my own first instinct.** A fire-and-forget
`setImmediate` in a single-process Express app with no queue gives the worst of both: no
durability across a restart *and* no feedback to the doctor. Instead: **write the `QUEUED`
row first, then do the work synchronously, then update the row.** The work is bounded
(≈3–6 TTS calls + 2 S3 puts + 1 HTTP POST), the doctor is already standing at a confirm
dialog, and a row stranded in `QUEUED` by a crash is visibly resumable. The client raises
`receiveTimeout` for this one call (Dio 5 allows it per-request via `Options`) — the global
10 s in `createApiClient()` stays untouched. If throughput ever matters, the `QUEUED` row
is already the queue.

---

## Phase 6 — Flutter

All in `mobile_app/lib/presentation/screens/doctor/doctor_screens.dart` (2495 lines) unless
noted. **Do not run `dart format` on this file** — it is unformatted and the formatter
rewrites ~1300 lines.

- **`_PrescriptionEntry`** (line 1063) gains schedule state alongside its three
  `TextEditingController`s: `Set<String> slots`, `String? food`, `bool prn`,
  `prnConditionController`, `double? pillsPerDose`, `String source`.
- **`_PrescriptionCard`** (line 2070) gains a chip row under the three existing fields:
  four slot `FilterChip`s, a food `SegmentedButton`, a PRN toggle revealing a condition
  field. Keep the existing `LayoutBuilder` responsive split (≥640 px one row, else
  stacked). Chips edited by hand set `source = 'DOCTOR'`.
- **Autofill** fires on `dosage`/`duration` blur → `POST /records/schedule-parse` → fills
  only chips the doctor has not touched. The existing `onChanged: (_) => onChanged()` wiring
  into `_invalidateInteractionCheck` is the precedent; reuse the same hook.
- **`_submitRecord()`** (lines 1175–1438) becomes `_submitRecord({bool send = false})` and
  must **capture `createMedicalRecord`'s returned Map**, which it currently discards — the
  new record's `id` is needed for every message route.
- **New `Save & Send to Patient` button** directly below the existing submit button at
  line 1796, before the Ctrl+Enter tip. Keeping the plain save button intact means the
  existing single-press flow (and `clinic_flow_test.dart`) is unaffected.
- **New `PatientMessagePreviewDialog`** — put it in a **new file**
  `presentation/screens/doctor/patient_message_dialog.dart` rather than growing a
  2495-line file further. Shows the chart via `Image.memory` (the preview returns a data
  URI, so no presigned-URL expiry to manage), each segment's spoken text with its English
  gloss, and a banner when `supported == false` ("Bengali is not available — sending in
  English"). `Send` is disabled while `blockers` is non-empty.
  Uses `showDialog` — close it with the **builder's own context**
  (`Navigator.of(dialogContext).pop()`), per the `ShellRoute` gotcha in `MEMORY.md`.
- **`record_service.dart`** gains `parseSchedules`, `previewPatientMessage`,
  `sendPatientMessage`, `getPatientMessageStatus`. The send call passes
  `Options(receiveTimeout: Duration(seconds: 60))`.
- **Audio playback:** none, deliberately. The app has no audio dependency today; adding
  `audioplayers` for a doctor-side preview is not worth it. The doctor verifies the
  **text + gloss**, which is what they can actually check. If in-app playback is wanted
  later, that is a one-package follow-up.
- **Opt-in capture:** a WhatsApp consent checkbox in the two registration dialogs —
  `auth/patient_registration_screen.dart` and the desk dialog in
  `reception/reception_screens.dart`. Both already carry the duplicated 8-language list;
  this is the natural place to note that only three are spoken.
- **Strings stay English**, consistent with every other doctor/reception screen — only
  `main.dart`, `dashboard_screen.dart` and `profile_screen.dart` use `AppLocalizations`
  today. The *patient-facing* text is in `backend/messages/`, which is the part that
  actually needs translating.

---

## Phase 7 — Tests and docs

| Script | Kind |
|---|---|
| `scripts/test-dose-schedule.js` | offline, table-driven (Phase 1) |
| `scripts/test-patient-message.js` | offline: templates, script, SVG (Phase 3) |
| `scripts/test-tts-provider.js` | smoke test, mirrors `test-ai-provider.js` (Phase 4) |
| `scripts/test-patient-message-api.js` | real HTTP, stubbed Firebase, self-cleaning fixtures — the `test-interactions.js` harness (Phase 5) |
| `scripts/test-auth-rbac.js` | **must change**: add `message:send` to the `ENDPOINTS` matrix |
| `scripts/test-interactions.js` | should stay green untouched — confirms Phase 1's columns are genuinely additive |
| `test/clinic_flow_test.dart` | new case: chips autofill, preview opens, Send disabled while blocked |

Docs, per `CLAUDE.md`: update the tree in `SNAPSHOT.md`, add a dated entry to `MEMORY.md`,
extend `backend/.env.example` with the `TTS_*` / `MSG_*` blocks, and add a Postman folder
`08. Smart Prescriptions`.

---

## Verification

```bash
# Phase 0 — the backend boots again
cd backend && node --check config/firebase.js && npm run dev   # then GET /api/health
```

```bash
# Offline suites — no DB, no network, no credentials
cd backend && node scripts/test-dose-schedule.js && node scripts/test-patient-message.js
```

```bash
# Full stack locally, with the log messaging provider and the mock TTS
cd backend && docker compose up -d && npx prisma migrate deploy
MSG_PROVIDER=log TTS_PROVIDER=mock npm run dev
```

```bash
# Regression — both existing suites must stay green
cd backend && node scripts/test-auth-rbac.js && node scripts/test-interactions.js
```

```bash
cd mobile_app && flutter analyze && flutter test
```

**End-to-end click-through** (the user drives the browser, per their stated preference):
doctor signs in on `:5001` → opens a patient → types "1 tab twice daily after food" and
"5 days" → sees the chips fill themselves → presses *Save & Send to Patient* → preview
shows the chart, the Hindi sentence and its English gloss → *Send* → the `log` provider's
output directory contains one PNG and N audio files, and `GET /records/:id/patient-message`
reports `SENT`.

**Real WhatsApp delivery is deliberately the last step and is gated on infrastructure that
does not exist yet** — Twilio needs publicly fetchable media URLs, which needs the S3
bucket from `AWS_MIGRATION_PLAN.md` §1. Until then the `log` provider is the honest demo.
The Meta adapter is the path that would work without S3, since it uploads bytes directly.

---

## Known risks and open gaps

1. **S3 is not provisioned.** The Twilio path is untestable end-to-end until it is. Stated
   above; the `log` and `meta` providers are the ways around it.
2. **Tamil TTS is unconfirmed.** Verify the provider's actual voice list in Phase 4 before
   committing; the degradation path exists either way.
3. **Bengali is the registration default** and is not spoken. Every Bengali-preferring
   patient gets English audio with a preview warning. The real fix — narrowing the
   registration dropdown to supported languages, or adding Bengali TTS — is out of scope
   here but should be recorded in `MEMORY.md`.
4. **The 8-language dropdown is duplicated** in `patient_registration_screen.dart:22-31`
   and `reception_screens.dart:61-70`. Touching one without the other is an easy mistake
   while adding the opt-in checkbox.
5. **`report_file_url` reuse.** `signReport` is field-specific; Phase 4 generalises it
   *underneath* rather than changing its signature, so the three existing read paths that
   depend on it are not disturbed.
6. **Re-sending.** A doctor who corrects a record after sending will want to re-send. The
   `PatientMessage` rows are append-only, so this works, but the patient receives two sets
   of instructions with no indication which supersedes. Out of scope; worth a note.

```
## CLAUDE REMARKS

hree things from the exploration that shaped the whole design:

Prescription has no timing field. Just medicine_name, dosage, duration — all free text. "Morning and night" only exists as prose inside dosage. So the plan adds nullable structured columns plus tap-chips on the visit form, with the AI pre-filling them from what the doctor already typed. AI does the work invisibly; the doctor confirms with a glance; the patient hears something verified.

This feature has to fail closed. The drug checker fails open because a missed warning still leaves a doctor in the loop. Here there's no literate reader downstream to catch a bad instruction, so an unparseable prescription blocks the send rather than getting described vaguely. Same reason the spoken script comes from per-language templates, not LLM generation — the model never writes a word the patient hears.

main doesn't boot right now. Four files carry committed git conflict markers, and backend/config/firebase.js is a hard SyntaxError — authenticate requires it, so every request 500s. That's Phase 0, unrelated to this feature but blocking any work on it.

Two honest caveats in the plan rather than glossed over: real Twilio delivery needs publicly fetchable media URLs, so it's blocked on the S3 bucket that AWS_MIGRATION_PLAN.md §1 hasn't provisioned (the log provider is the demo path; Meta's API uploads bytes directly and would work without S3). And I did not verify which Tamil voices Polly or Google actually ship — that's the first task of Phase 4, not an assumption.

One process note: I'd launched a design-critique pass in the background, and it stopped before finishing when the earlier session ended. So this plan is my own design without that second opinion. Say the word if you want me to run it.
```