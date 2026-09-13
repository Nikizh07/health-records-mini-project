# 🚀 Quick Start - Guest Login

## Problem
❌ Phone OTP authentication failing with error: `BILLING_NOT_ENABLED`

## Solution
✅ Added temporary **Guest Sign-In** to bypass OTP requirement

---

## 📋 Setup Steps (5 minutes)

### 1. Enable Anonymous Auth in Firebase Console

```
1. Visit: https://console.firebase.google.com/
2. Select project: migrant-workers-89bb8
3. Go to: Authentication → Sign-in method
4. Find "Anonymous" provider
5. Toggle to ENABLE
6. Click Save
```

### 2. Run the App

```bash
cd mobile_app
flutter clean
flutter pub get
flutter run
```

### 3. Login as Guest

On the login screen, click:
**"Continue as Guest (Testing)"**

---

## 🎯 What You'll See

**Login Screen Now Has:**
- 📱 Normal phone OTP input (currently broken due to billing)
- ⚠️ Yellow info banner: "OTP not working? Use Guest mode below"
- 👤 **New Button**: "Continue as Guest (Testing)"

**After Clicking Guest Login:**
- Authenticates via Firebase Anonymous Auth
- Gets valid Firebase token
- Backend accepts it ✅
- Redirects to registration or dashboard

---

## ✨ Files Modified

| File | Changes |
|------|---------|
| `lib/data/services/auth_service.dart` | Added `signInAsGuest()` method |
| `lib/providers/auth_provider.dart` | Added guest sign-in state logic |
| `lib/presentation/screens/auth/login_screen.dart` | Added guest button + info banner |

**No backend changes needed!** Backend already supports anonymous Firebase tokens.

---

## ⚠️ Important Notes

**Guest Mode is for TESTING ONLY:**
- Sessions are temporary
- Not persistent across reinstalls
- No account recovery
- Data lost if app cleared

**For Production:**
- Enable billing on Firebase project
- Phone OTP will work properly
- Remove/hide guest login button

---

## 🔧 Troubleshooting

**If Guest Login Fails:**

1. Check Firebase Console: Anonymous auth must be ENABLED
2. Restart app after enabling: `flutter clean && flutter run`
3. Check logs: `flutter logs`

**Common Error:**
```
[firebase_auth/operation-not-allowed] 
The identity provider configuration is not found
```
**Fix:** Enable Anonymous authentication in Firebase Console

---

## 📱 Test Flow

```
Login Screen
    ↓
Click "Continue as Guest (Testing)"
    ↓
Firebase Anonymous Auth
    ↓
Get Firebase Token
    ↓
Backend Validates Token ✅
    ↓
Check if Profile Exists
    ├─ YES → Dashboard
    └─ NO  → Registration Screen
```

---

## 🎉 Ready to Test!

Enable Anonymous Auth in Firebase Console, then run the app and click the guest button!

For detailed information, see: `GUEST_LOGIN_SETUP.md`
