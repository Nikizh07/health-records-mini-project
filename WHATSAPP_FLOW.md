# WhatsApp Smart Prescriptions Flow

## User Journey

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. PATIENT REGISTRATION                                         │
│                                                                 │
│    [Registration Form]                                          │
│    ┌────────────────────────────────────┐                      │
│    │ Name: Ahmad Khan                   │                      │
│    │ DOB: 1985-03-15                    │                      │
│    │ Language: Hindi                    │                      │
│    │ ☑ Send WhatsApp prescription       │ ← Patient opts in   │
│    │   messages (Hindi/English/Tamil)   │                      │
│    └────────────────────────────────────┘                      │
│                                                                 │
│    Database: whatsapp_opt_in = true ✓                          │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 2. DOCTOR CONSULTATION                                          │
│                                                                 │
│    [Visit Notes Form]                                           │
│    Diagnosis: Upper respiratory infection                       │
│                                                                 │
│    Prescription #1:                                             │
│    ┌────────────────────────────────────┐                      │
│    │ Medicine: Amoxicillin 500mg        │                      │
│    │ Dosage: 1 tablet twice daily       │ ← Doctor types      │
│    │ Duration: 7 days                   │                      │
│    └────────────────────────────────────┘                      │
│                                                                 │
│    🤖 AI Autofills on blur:                                    │
│    [☑Morning] [☐Afternoon] [☐Evening] [☑Night]                │
│    Food: (•After) ○Before ○With ○Anytime                       │
│                                                                 │
│    Doctor can manually adjust chips                             │
│                                                                 │
│    [Save Visit Record]  [Save & Send to Patient] ← New button  │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 3. PREVIEW DIALOG                                               │
│                                                                 │
│    ┌─────────────────────────────────────────────────────┐    │
│    │ Message Preview                              [×]     │    │
│    ├─────────────────────────────────────────────────────┤    │
│    │                                                      │    │
│    │ ⚠ Bengali not available — sending in English        │    │
│    │                                                      │    │
│    │ Visual Schedule:                                     │    │
│    │ ┌───────────────────────────────────────────────┐  │    │
│    │ │  #1  🔵  [🌅] [  ] [  ] [🌙]  Amoxicillin    │  │    │
│    │ │  #2  🔴  [🌅] [☀] [🌆] [🌙]  Paracetamol    │  │    │
│    │ └───────────────────────────────────────────────┘  │    │
│    │                                                      │    │
│    │ Voice Instructions (2 notes):                        │    │
│    │                                                      │    │
│    │ 🔊 #1: "Ahmad, yeh aapki dawai hai. Dawai         │    │
│    │     number 1, neeli wali. Subah aur raat ko,      │    │
│    │     khana khane ke baad. 7 din tak."               │    │
│    │     English: "Ahmad, this is your medicine..."     │    │
│    │                                                      │    │
│    │ 🔊 #2: "Dawai number 2, laal wali..."            │    │
│    │                                                      │    │
│    │                [Cancel]  [Send to Patient]         │    │
│    └─────────────────────────────────────────────────────┘    │
│                                                                 │
│    ✓ Doctor verifies visual + text before sending              │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 4. BACKEND PROCESSING (60s timeout)                             │
│                                                                 │
│    ① Validate consent & schedule completeness                   │
│    ② Build script from templates (not AI!)                      │
│    ③ Generate voice notes (TTS):                                │
│       • English: en-IN-Standard-A                               │
│       • Hindi:   hi-IN-Standard-A                               │
│       • Tamil:   ta-IN-Standard-A                               │
│    ④ Render pictogram (deterministic SVG → PNG)                │
│    ⑤ Store assets as base64 in database                         │
│    ⑥ Generate signed media URLs (15min expiry)                  │
│    ⑦ Send via messaging provider                                │
│                                                                 │
│    PatientMessage row: status = QUEUED → SENT                   │
└─────────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────────┐
│ 5. PATIENT RECEIVES MESSAGE                                     │
│                                                                 │
│    📱 WhatsApp Message from Clinic:                            │
│    ┌─────────────────────────────────────────┐                │
│    │  🏥 Migrant Worker Clinic                │                │
│    │                                          │                │
│    │  📊 [Pictogram Chart]                   │                │
│    │                                          │                │
│    │  🔊 Voice Note 1 (0:15)                 │ ← Tap to play  │
│    │  🔊 Voice Note 2 (0:12)                 │   in Hindi     │
│    │                                          │                │
│    │  Text fallback:                          │                │
│    │  "Medicine #1: Blue pill, morning       │                │
│    │   and night after food for 7 days"      │                │
│    └─────────────────────────────────────────┘                │
│                                                                 │
│    ✓ Patient understands even if illiterate                    │
│    ✓ Visual + audio removes ambiguity                          │
│    ✓ Correct dosing → better outcomes                          │
└─────────────────────────────────────────────────────────────────┘
```

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        FLUTTER APP                              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  DoctorAddRecordScreen                                    │  │
│  │  • Schedule chips with autofill                           │  │
│  │  • "Save & Send" button                                   │  │
│  └────────────────────────────┬─────────────────────────────┘  │
│                               │                                 │
│  ┌────────────────────────────▼─────────────────────────────┐  │
│  │  PatientMessagePreviewDialog                              │  │
│  │  • Shows chart + voice segments                           │  │
│  │  • Blocks send if incomplete                              │  │
│  └────────────────────────────┬─────────────────────────────┘  │
└────────────────────────────────┼─────────────────────────────────┘
                                │ POST /records/:id/patient-message/send
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      EXPRESS BACKEND                            │
│                                                                 │
│  POST /records/schedule-parse (autofill)                        │
│    └─→ services/doseScheduleParser.js                           │
│         • Deterministic regex patterns                          │
│         • AI fills gaps (never overrides)                       │
│                                                                 │
│  POST /records/:id/patient-message/preview                      │
│    └─→ services/patientMessage/send.js                          │
│         • Build script from templates                           │
│         • Render SVG chart                                      │
│         • Check blockers (consent, schedule, phone)             │
│                                                                 │
│  POST /records/:id/patient-message/send                         │
│    └─→ services/patientMessage/send.js                          │
│         ① Validate                                              │
│         ② TTS synthesis (3 providers)                           │
│            ├─ mock     → silent WAV                             │
│            ├─ google   → Google Cloud TTS API                   │
│            └─ polly    → AWS Polly SDK                          │
│         ③ Rasterize chart (SVG → PNG)                           │
│         ④ Store in PatientMessage.payload                       │
│         ⑤ Generate signed URLs                                  │
│         ⑥ Send via messaging provider                           │
│            ├─ log            → .scratch/messages/               │
│            └─ twilio-sandbox → Twilio WhatsApp API              │
│                                                                 │
│  GET /api/media/:token/:filename                                │
│    └─→ routes/media.routes.js                                   │
│         • Verify JWT token (15min expiry)                       │
│         • Stream from PatientMessage.payload                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    EXTERNAL SERVICES                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  TWILIO WHATSAPP SANDBOX                                 │  │
│  │  • Fetches media from /api/media/:token/:filename        │  │
│  │  • Delivers to patient's WhatsApp                        │  │
│  │  • Requires patient to "join sandbox" first              │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  TTS PROVIDERS (choose one)                              │  │
│  │  • Google Cloud TTS API                                  │  │
│  │  • AWS Polly                                             │  │
│  │  • Mock (silent WAV for testing)                         │  │
│  └─────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

```
┌─────────────┐
│ Prescription│  dosage: "1-0-1 after food"
│    Row      │  duration: "7 days"
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ POST /schedule-parse    │  AI + Regex
│  (on blur)              │
└──────┬──────────────────┘
       │
       ▼ {slots:['MORNING','NIGHT'], food_relation:'AFTER', ...}
┌─────────────────────────┐
│  Schedule Chips         │  Doctor can override
│  [☑Morning] [☑Night]    │
│  Food: (•After)         │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ POST /create-record     │  Saves with schedule
│                         │
└──────┬──────────────────┘
       │
       ▼ recordId
┌─────────────────────────┐
│ POST /preview           │  Builds message without sending
│                         │
└──────┬──────────────────┘
       │
       ▼ {segments, chart, blockers, language_used}
┌─────────────────────────┐
│  Preview Dialog         │  Doctor reviews
│  Shows: Chart + Script  │
└──────┬──────────────────┘
       │ Confirm
       ▼
┌─────────────────────────┐
│ POST /send              │  Full pipeline
│                         │
│ ① TTS: text → audio     │  3 languages
│ ② Render: SVG → PNG     │  Deterministic
│ ③ Store: base64 → DB    │  In payload column
│ ④ Sign: URL + JWT       │  15min expiry
│ ⑤ Send: Twilio API      │  WhatsApp delivery
│                         │
└──────┬──────────────────┘
       │
       ▼ {status:'SENT', provider_message_id:'SM...'}
┌─────────────────────────┐
│  PatientMessage Row     │
│  status: SENT           │  Audit trail
│  payload: {...}         │  Assets + transcript
│  sent_at: now()         │
└─────────────────────────┘
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| **Templates not LLM** | Voice script must be clinically verified, never hallucinated |
| **Deterministic pictogram** | Wrong pill count = patient safety bug, never use AI image gen |
| **Fail-closed** | Incomplete schedule blocks send vs vague instruction |
| **Base64 in DB** | Simple for sandbox, no S3 dependency |
| **Signed URLs** | 15min expiry = security, patient doesn't keep working link forever |
| **AI fills gaps only** | Never overrides doctor's manual edits (source='DOCTOR' tracking) |
| **60s timeout** | TTS synthesis for 3 languages + image render needs time |
| **Pluggable providers** | Easy to swap mock → sandbox → production |

## Fail-Closed Validation

The system refuses to send if:

```typescript
Blockers = [
  !whatsapp_opt_in          → "Patient has not consented"
  !phone || invalid_format  → "Invalid phone number"
  !prescription.slots       → "Schedule incomplete for medicine #X"
  prescription.prn && !prn_condition → "PRN needs condition"
  !PUBLIC_BASE_URL          → "Server not publicly accessible"
]

if (blockers.length > 0) {
  // Preview shows blockers
  // Send button disabled
  // Error on API call
}
```

This ensures **no vague or incorrect instructions reach the patient**.

## Performance Characteristics

| Operation | Duration | Notes |
|-----------|----------|-------|
| Schedule autofill | <2s | AI + regex, runs on blur |
| Preview generation | <3s | Script + SVG only, no TTS |
| Full send (mock TTS) | 5-8s | Fast for testing |
| Full send (Google/Polly) | 15-30s | TTS synthesis is slow |
| Media URL fetch | <100ms | Streams from DB via signed token |
| Message delivery | 1-5s | Twilio API latency |

The 60-second timeout accommodates worst-case TTS latency (3 languages × 2 segments each).
