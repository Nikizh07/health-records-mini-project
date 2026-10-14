# WhatsApp Configuration Guide for Smart Prescriptions

This guide walks you through setting up WhatsApp messaging for the Smart Prescriptions feature, which sends prescription instructions to patients via voice notes and pictograms.

## Overview

The system supports two messaging providers:
1. **`log`** - For local development (no credentials needed)
2. **`twilio-sandbox`** - For real WhatsApp delivery via Twilio

## Quick Start: Local Development (No WhatsApp)

For pure local testing without WhatsApp delivery:

```bash
cd backend

# In your .env file:
MSG_PROVIDER=log
TTS_PROVIDER=mock
JWT_SECRET=$(openssl rand -base64 32)
PUBLIC_BASE_URL=http://localhost:3000

# Start the server
npm run dev
```

Messages will be written to `backend/.scratch/messages/log_<timestamp>/` with:
- Audio files (`.mp3`)
- Pictogram chart (`.png`)
- Message transcript (`.txt`)

## Production Setup: Twilio WhatsApp Sandbox

### Step 1: Create Twilio Account

1. Sign up at https://www.twilio.com/try-twilio (free trial available)
2. Verify your email and phone number
3. Go to **Console Dashboard**

### Step 2: Get WhatsApp Sandbox Credentials

1. In Twilio Console, navigate to:
   ```
   Messaging → Try it out → Send a WhatsApp message
   ```

2. Note down these values:
   - **Account SID**: Starts with `AC...` (found in Console Dashboard)
   - **Auth Token**: Click "Show" to reveal (found in Console Dashboard)
   - **Sandbox Number**: Format `whatsapp:+14155238886` (shown in sandbox page)
   - **Sandbox Name**: Your unique join code (e.g., `join difficult-victory`)

### Step 3: Configure Environment Variables

In your `backend/.env` file:

```bash
# Messaging Provider
MSG_PROVIDER=twilio-sandbox
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your_auth_token_from_console
TWILIO_SANDBOX_NUMBER=whatsapp:+14155238886

# Public URL (required for Twilio to fetch media)
PUBLIC_BASE_URL=https://your-app.onrender.com

# Text-to-Speech (choose one)
TTS_PROVIDER=mock                    # Start with mock for testing
# TTS_PROVIDER=google                # Or use Google Cloud TTS
# TTS_PROVIDER=polly                 # Or use AWS Polly

# Security
JWT_SECRET=$(openssl rand -base64 32)
```

### Step 4: Make Your Server Publicly Accessible

Twilio needs to fetch media files from your server. You have two options:

#### Option A: Local Development with ngrok

```bash
# Install ngrok (if not installed)
# https://ngrok.com/download

# Start your backend server
cd backend
npm run dev

# In another terminal, expose it via ngrok
ngrok http 3000

# Copy the HTTPS URL (e.g., https://abc123.ngrok.io)
# Update your .env:
PUBLIC_BASE_URL=https://abc123.ngrok.io
```

**Important**: Restart your backend after changing `PUBLIC_BASE_URL` so the new value is loaded.

#### Option B: Production Deployment

Deploy to a cloud platform with a public URL:
- **Render**: `https://your-app.onrender.com`
- **Heroku**: `https://your-app.herokuapp.com`
- **AWS/GCP**: Your domain or load balancer URL

Set `PUBLIC_BASE_URL` to your production URL.

### Step 5: Patient Must Join the Sandbox

**This is a one-time step per patient's phone number.**

Each patient must send a WhatsApp message to join your sandbox:

1. Patient opens WhatsApp
2. Patient sends message to: `+1 415 523 8886` (or your sandbox number)
3. Patient types: `join <your-sandbox-name>` (e.g., `join difficult-victory`)
4. Patient receives confirmation: "You are all set!"

**Without this step, messages will fail with an error.**

### Step 6: Test the Integration

```bash
# Smoke test the messaging provider
cd backend
node scripts/test-messaging-provider.js

# Expected output (with twilio-sandbox):
# ✓ Messaging provider twilio-sandbox configured
# ✓ Message sent successfully
# Provider message ID: SM...
```

If you see errors, check:
- Twilio credentials are correct
- `PUBLIC_BASE_URL` is accessible from the internet
- Patient has joined the sandbox (if testing with real number)

## Text-to-Speech Configuration

Choose one TTS provider for voice notes:

### Option 1: Mock (No Setup)

```bash
TTS_PROVIDER=mock
```

Generates silent 1-second WAV files. Perfect for testing the flow without audio quality.

### Option 2: Google Cloud TTS

```bash
TTS_PROVIDER=google
GOOGLE_TTS_API_KEY=your_google_api_key

# Optional: customize voices (defaults shown)
TTS_VOICE_EN=en-IN-Standard-A      # Indian English
TTS_VOICE_HI=hi-IN-Standard-A      # Hindi
TTS_VOICE_TA=ta-IN-Standard-A      # Tamil
```

**Setup:**
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Enable "Cloud Text-to-Speech API"
3. Create an API key: **APIs & Services → Credentials → Create Credentials → API Key**
4. Verify Tamil voice availability:
   ```bash
   curl "https://texttospeech.googleapis.com/v1/voices?key=YOUR_KEY" | \
     jq '.voices[] | select(.languageCodes[] | contains("ta-IN"))'
   ```

### Option 3: AWS Polly

```bash
TTS_PROVIDER=polly
AWS_REGION=ap-south-1

# Optional: customize voices (defaults shown)
TTS_VOICE_EN=Kajal                 # Indian English female
TTS_VOICE_HI=Aditi                 # Hindi female
TTS_VOICE_TA=                      # Must verify availability
```

**Setup:**
1. Configure AWS credentials (uses standard AWS SDK chain)
2. Verify Tamil voice availability:
   ```bash
   aws polly describe-voices --region ap-south-1 --language-code ta-IN
   ```
3. If Tamil unavailable, patients with Tamil preference receive English audio

**Note:** AWS credentials come from:
- Local: `AWS_PROFILE` or `~/.aws/credentials`
- Production: ECS task role or EC2 instance role

## Security Considerations

### JWT Secret

The `JWT_SECRET` is used to sign media URLs (15-minute expiry). Generate a strong secret:

```bash
openssl rand -base64 32
```

**Never commit this to git.** Rotate it periodically in production.

### Phone Number Format

Patient phone numbers must be in E.164 format:
- ✅ Correct: `+919876543210` (country code + number)
- ❌ Wrong: `9876543210` (missing country code)
- ❌ Wrong: `919876543210` (missing + sign)

The backend validates phone format before sending.

### WhatsApp Consent

Patients must opt-in to WhatsApp messages:
1. Checkbox in patient registration screen
2. Checkbox in reception desk registration dialog
3. Database field: `patients.whatsapp_opt_in`

The send endpoint returns `409` if consent is not granted.

## Troubleshooting

### "No WhatsApp consent" Error

**Symptom:** Preview shows blocker: "Patient has not consented to WhatsApp messages"

**Solution:** 
- Have patient re-register and check the WhatsApp consent box, OR
- Update database directly:
  ```sql
  UPDATE patients 
  SET whatsapp_opt_in = true, 
      whatsapp_opt_in_at = NOW() 
  WHERE id = 'patient-id';
  ```

### "Patient must join sandbox" Error

**Symptom:** Message fails with "Recipient not in sandbox"

**Solution:**
- Patient must send `join <sandbox-name>` to Twilio number first
- Check sandbox participants in Twilio Console → WhatsApp Sandbox

### "Media URL not accessible" Error

**Symptom:** Message sends but media shows as broken link

**Solution:**
- Check `PUBLIC_BASE_URL` is accessible from internet
- For ngrok: make sure ngrok is still running (URLs change on restart)
- For production: verify firewall/security groups allow inbound HTTPS

### "Invalid phone number" Error

**Symptom:** Send fails with "Invalid phone format"

**Solution:**
- Ensure phone is E.164 format: `+[country code][number]`
- Example: India = `+91`, US = `+1`

### Messages Not Sending from Flutter App

**Symptom:** Button works but nothing happens

**Solution:**
1. Check backend logs for errors
2. Verify all environment variables are set
3. Test with smoke test script:
   ```bash
   cd backend
   node scripts/test-messaging-provider.js
   ```
4. Check Flutter console for API errors

## Upgrading to Production WhatsApp Business API

The Twilio Sandbox is for testing only. For production:

1. **Apply for WhatsApp Business API**
   - Go to Twilio Console → WhatsApp → Request Production Access
   - Facebook will review your business (1-2 weeks)
   - Must have:
     - Registered business
     - Business Facebook account
     - Business use case description

2. **Update Configuration**
   ```bash
   # Change from sandbox number to your approved number
   TWILIO_SANDBOX_NUMBER=whatsapp:+1234567890
   ```

3. **Remove Join Requirement**
   - Approved numbers don't require "join" step
   - Patients can receive messages immediately after consent

4. **Message Templates**
   - WhatsApp Business requires pre-approved message templates
   - Template variables can be customized per message
   - Current implementation uses "free-form" messages (sandbox only)

## Testing Checklist

Before going live, test:

- [ ] Local `log` provider writes files correctly
- [ ] Twilio sandbox credentials work with smoke test
- [ ] Patient can join sandbox and receive test message
- [ ] TTS generates audio in all three languages (en/hi/ta)
- [ ] Pictogram renders correctly with 1-4 prescriptions
- [ ] Preview dialog shows chart and segments
- [ ] Send button disabled when blockers present
- [ ] Language fallback warning shows for unsupported languages
- [ ] 60-second timeout doesn't cause issues
- [ ] Media URLs expire after 15 minutes as expected

## Support Resources

- **Twilio WhatsApp Sandbox**: https://www.twilio.com/docs/whatsapp/sandbox
- **Google Cloud TTS**: https://cloud.google.com/text-to-speech/docs
- **AWS Polly**: https://docs.aws.amazon.com/polly/
- **ngrok Documentation**: https://ngrok.com/docs

## Cost Estimates

### Twilio WhatsApp (India pricing as of 2024)

- **Sandbox**: Free (testing only, limited users)
- **Business Conversation**: ₹0.45 per conversation
- **Service Conversation**: ₹0.65 per conversation
- **Media Messages**: Same as text (media hosting included)

A "conversation" is a 24-hour window after first message.

### Google Cloud TTS

- **First 1M characters/month**: Free
- **Additional characters**: $4 per 1M characters
- Average prescription: ~200 characters × 3 languages = 600 chars
- 1000 messages = 600K characters ≈ Free tier

### AWS Polly

- **First 12 months**: 5M characters free (new accounts)
- **After free tier**: $4 per 1M characters
- Same cost structure as Google TTS

## Architecture Notes

The implementation uses:
- **Pluggable providers**: Easy to add Meta/WhatsApp official API later
- **Media stored in database**: As base64 in `PatientMessage.payload`
- **Signed URLs**: JWT tokens with 15-minute expiry for security
- **Fail-closed design**: Incomplete schedules block send rather than sending vague instructions
- **Template-based**: Voice scripts use JSON templates, never LLM-generated
- **Deterministic rendering**: SVG pictograms never use AI (safety-critical)

This design makes the feature testable without external services and production-ready with minimal configuration changes.
