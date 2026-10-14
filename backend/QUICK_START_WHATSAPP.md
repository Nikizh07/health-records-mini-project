# WhatsApp Quick Start (5 Minutes)

## Local Development (No WhatsApp)

```bash
# 1. Copy environment template
cp .env.example .env

# 2. Set these in .env:
MSG_PROVIDER=log
TTS_PROVIDER=mock
JWT_SECRET=$(openssl rand -base64 32)
PUBLIC_BASE_URL=http://localhost:3000

# 3. Start server
npm run dev

# 4. Test
node scripts/test-messaging-provider.js
```

✅ Messages write to `.scratch/messages/` - no external services needed!

---

## Production with Twilio (Real WhatsApp)

### One-Time Setup (5 min)

**1. Get Twilio Credentials** (free trial available)
```
https://www.twilio.com/try-twilio
→ Console → Messaging → WhatsApp Sandbox
```

Copy:
- Account SID: `ACxxxxx...`
- Auth Token: (click Show)
- Sandbox Number: `whatsapp:+14155238886`
- Join Code: `join <sandbox-name>`

**2. Configure `.env`**
```bash
MSG_PROVIDER=twilio-sandbox
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your_auth_token
TWILIO_SANDBOX_NUMBER=whatsapp:+14155238886
PUBLIC_BASE_URL=https://your-app.onrender.com  # or ngrok URL
JWT_SECRET=$(openssl rand -base64 32)
TTS_PROVIDER=mock  # or google/polly
```

**3. Make Server Public**

**Option A - Local with ngrok:**
```bash
# Terminal 1
npm run dev

# Terminal 2
ngrok http 3000
# Copy https://xyz.ngrok.io and set as PUBLIC_BASE_URL
```

**Option B - Deploy to cloud:**
Use Render/Heroku/AWS URL as `PUBLIC_BASE_URL`

**4. Patient Joins Sandbox (one-time per phone)**

Patient sends WhatsApp to `+1 415 523 8886`:
```
join <your-sandbox-name>
```

**5. Test**
```bash
node scripts/test-messaging-provider.js
```

---

## Configuration Matrix

| Environment | MSG_PROVIDER | TTS_PROVIDER | PUBLIC_BASE_URL | Notes |
|-------------|-------------|--------------|----------------|--------|
| **Local Dev** | `log` | `mock` | `http://localhost:3000` | No credentials needed |
| **Testing** | `twilio-sandbox` | `mock` | ngrok URL | Test real WhatsApp with silent audio |
| **Staging** | `twilio-sandbox` | `google` | Staging URL | Test with real audio |
| **Production** | `twilio-sandbox` | `google` or `polly` | Production URL | Full experience |

---

## Common Issues & Fixes

| Error | Fix |
|-------|-----|
| "No WhatsApp consent" | Patient must check consent box during registration |
| "Recipient not in sandbox" | Patient must send `join <name>` to sandbox number first |
| "Media URL not accessible" | Check `PUBLIC_BASE_URL` is publicly reachable |
| "Invalid phone format" | Phone must be E.164: `+919876543210` |
| Preview shows no blockers but send fails | Check backend logs for specific error |

---

## Smoke Tests

```bash
# Test TTS
TTS_PROVIDER=mock JWT_SECRET=test node scripts/test-tts-provider.js

# Test Messaging
node scripts/test-messaging-provider.js

# Test full flow (requires database)
# Send from Flutter app → Check .scratch/messages/ or WhatsApp
```

---

## Need Help?

📖 Full guide: `/WHATSAPP_SETUP.md`
🔧 Twilio docs: https://www.twilio.com/docs/whatsapp/sandbox
💬 Issues: Check backend logs with `npm run dev`
