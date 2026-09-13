# 🔧 Enable Anonymous Authentication in Firebase

## ⚠️ CRITICAL: You Must Do This First!

The error **"only allowed for admins"** means Anonymous Authentication is **disabled** in your Firebase project.

---

## 📋 Step-by-Step Instructions

### 1. Open Firebase Console

Go to: **https://console.firebase.google.com/**

### 2. Select Your Project

Click on: **migrant-workers-89bb8**

### 3. Navigate to Authentication

In the left sidebar, click: **Authentication**

### 4. Go to Sign-in Method Tab

At the top, click the **"Sign-in method"** tab

### 5. Find Anonymous Provider

Scroll down the list of providers until you see:

```
┌─────────────────────────────────────┐
│  Anonymous                          │
│  Disabled                    ↓ ••• │
└─────────────────────────────────────┘
```

### 6. Enable It

- Click on the **Anonymous** row
- You'll see a toggle switch
- Turn it **ON** (it should turn blue/green)
- Click **Save**

### 7. Verify It's Enabled

You should now see:

```
┌─────────────────────────────────────┐
│  Anonymous                          │
│  Enabled                     ↓ ••• │
└─────────────────────────────────────┘
```

---

## 🚀 After Enabling

### Option 1: Hot Reload (Quick)
In your terminal where `flutter run` is running, press:
```
r
```

### Option 2: Restart App (Recommended)
In your terminal, press:
```
q
```
Then run again:
```bash
flutter run
```

### Option 3: Full Clean (If still having issues)
```bash
flutter clean
flutter pub get
flutter run
```

---

## 🧪 Test Guest Login

1. App should now be running
2. On the login screen, click: **"Continue as Guest (Testing)"**
3. Should authenticate successfully ✅
4. Should redirect to registration or dashboard

---

## ❓ Still Having Issues?

### Check Firebase Console Again
Make sure Anonymous shows as **"Enabled"**, not "Disabled"

### Check Error Message
Run with logs:
```bash
flutter run --verbose
```

Look for errors containing:
- `firebase_auth`
- `operation-not-allowed`
- `ADMIN_ONLY_OPERATION`

### Common Errors:

**Error:** `[firebase_auth/operation-not-allowed]`
**Fix:** Anonymous auth is still disabled. Check Firebase Console again.

**Error:** `[firebase_auth/network-request-failed]`
**Fix:** Check internet connection. Firebase requires internet.

**Error:** `[firebase_auth/app-not-authorized]`
**Fix:** Your Firebase config might be incorrect. Check `firebase_options.dart`

---

## 📸 Visual Guide

**Firebase Console → Authentication → Sign-in method**

```
╔═══════════════════════════════════════════════╗
║  Sign-in method                               ║
╠═══════════════════════════════════════════════╣
║                                               ║
║  Sign-in providers                            ║
║                                               ║
║  ┌──────────────────────────────────────────┐ ║
║  │ Email/Password              Disabled     │ ║
║  └──────────────────────────────────────────┘ ║
║                                               ║
║  ┌──────────────────────────────────────────┐ ║
║  │ Phone                       Disabled     │ ║
║  └──────────────────────────────────────────┘ ║
║                                               ║
║  ┌──────────────────────────────────────────┐ ║
║  │ Anonymous          👈 CLICK HERE         │ ║
║  │                             Disabled  ↓  │ ║
║  └──────────────────────────────────────────┘ ║
║                                               ║
║  ┌──────────────────────────────────────────┐ ║
║  │ Google                      Disabled     │ ║
║  └──────────────────────────────────────────┘ ║
║                                               ║
╚═══════════════════════════════════════════════╝
```

**After Clicking:**

```
╔═══════════════════════════════════════════════╗
║  Anonymous                                    ║
╠═══════════════════════════════════════════════╣
║                                               ║
║  Enable anonymous sign-in                     ║
║                                               ║
║  ┌──────────────────────┐                    ║
║  │  OFF      👉 ON  ✓   │  👈 TOGGLE THIS   ║
║  └──────────────────────┘                    ║
║                                               ║
║  Allows users to sign in anonymously         ║
║  without creating an account.                ║
║                                               ║
║              [ Cancel ]  [ Save ]            ║
║                              👆 CLICK SAVE    ║
╚═══════════════════════════════════════════════╝
```

---

## ✅ Success!

Once enabled and app is restarted, guest login should work perfectly!

Project ID: **migrant-workers-89bb8**
