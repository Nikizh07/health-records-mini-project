# Guest Login Setup Guide

## What Was Changed

A temporary **Guest Sign-In** feature has been added to bypass the phone OTP authentication issue (billing requirement).

### Changes Made:

1. **`auth_service.dart`**: Added `signInAsGuest()` method using Firebase Anonymous Authentication
2. **`auth_provider.dart`**: Added guest sign-in logic in `AuthNotifier`
3. **`login_screen.dart`**: Added "Continue as Guest (Testing)" button on the login screen

---

## Enable Anonymous Authentication in Firebase Console

**IMPORTANT:** You must enable Anonymous Authentication in your Firebase project for this to work.

### Steps:

1. Go to [Firebase Console](https://console.firebase.google.com/)

2. Select your project: **migrant-workers-89bb8**

3. Navigate to: **Authentication** → **Sign-in method**

4. Find **Anonymous** in the list of providers

5. Click on **Anonymous**

6. Toggle **Enable** to ON

7. Click **Save**

---

## How to Use Guest Login

1. Launch the mobile app
2. On the login screen, you'll see a new button: **"Continue as Guest (Testing)"**
3. Click it to sign in anonymously without phone verification
4. You'll be redirected to registration or dashboard depending on whether a profile exists

---

## What Guest Mode Does

- Creates an anonymous Firebase user (no phone number required)
- Generates a valid Firebase ID token
- Backend authentication middleware accepts it
- User can create a patient profile and use the app normally
- Guest sessions are temporary and linked to the device

---

## Guest Mode Limitations

- **Not persistent across app reinstalls** (anonymous UID changes)
- **Cannot recover account** if app data is cleared
- Should only be used for **testing/development**

---

## For Production

Once billing is enabled on Firebase:
1. Phone OTP authentication will work properly
2. You can remove or hide the guest login button
3. Users will have persistent, recoverable accounts

---

## Testing the Feature

After enabling Anonymous Authentication in Firebase Console:

```bash
cd mobile_app
flutter clean
flutter pub get
flutter run
```

Click "Continue as Guest (Testing)" on the login screen. You should be authenticated successfully!

---

## Backend Compatibility

The existing backend already supports anonymous authentication:
- `authenticate.js` middleware handles anonymous Firebase tokens
- It gracefully handles missing phone numbers
- Role defaults to 'PATIENT' for anonymous users

No backend changes were needed! ✅
