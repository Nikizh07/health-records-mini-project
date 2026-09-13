# 🔄 Replace Firebase Credentials - Complete Guide

## Overview

You need to replace your friend's Firebase project with YOUR OWN Firebase project.

This involves:
1. Creating a new Firebase project
2. Updating mobile app credentials
3. Updating backend credentials
4. Enabling authentication methods

---

## 🎯 Step-by-Step Instructions

### PART 1: Create Your Firebase Project

#### 1. Go to Firebase Console
Visit: https://console.firebase.google.com/

#### 2. Create New Project
- Click **"Add project"** or **"Create a project"**
- Enter project name: `my-health-clinic` (or any name you want)
- Click **Continue**
- Disable Google Analytics (optional for testing)
- Click **Create project**
- Wait for project to be created
- Click **Continue**

---

### PART 2: Register Android App

#### 1. Add Android App
In your Firebase project dashboard:
- Click the **Android icon** (robot)
- Or click **"Add app"** → **Android**

#### 2. Enter Package Name
```
com.migranthealth.mobile_app
```
(This must match the package name in your Flutter app)

#### 3. Download google-services.json
- Click **"Download google-services.json"**
- Save this file

#### 4. Place the File
Move the downloaded file to:
```bash
backend/config/firebase-adminsdk.json
```

**Command:**
```bash
# From your downloads folder
mv ~/Downloads/google-services.json \
  /home/nksama/coding/Cloud-Based-Digital-Health-Record-Appointment-Management-System-main/mobile_app/android/app/google-services.json
```

#### 5. Click Next/Continue
- Skip the rest of the setup steps
- Click **Continue to console**

---

### PART 3: Get Firebase Configuration for Flutter

#### 1. Install Firebase CLI (if not installed)
```bash
curl -sL https://firebase.tools | bash
```

#### 2. Login to Firebase
```bash
firebase login
```
(This will open a browser - login with your Google account)

#### 3. Go to Flutter App Directory
```bash
cd /home/nksama/coding/Cloud-Based-Digital-Health-Record-Appointment-Management-System-main/mobile_app
```

#### 4. Install FlutterFire CLI
```bash
dart pub global activate flutterfire_cli
```

#### 5. Configure Firebase for Your Project
```bash
flutterfire configure
```

This will:
- Show you a list of your Firebase projects
- Select the one you just created
- Automatically generate `lib/firebase_options.dart` with YOUR credentials

Choose:
- ✅ Android
- ✅ iOS (if you want)
- ✅ Web (if you want)

**This will automatically replace the old `firebase_options.dart` file!**

---

### PART 4: Enable Authentication Methods

#### 1. Go to Authentication
In Firebase Console:
- Click **"Authentication"** in left sidebar
- Click **"Get started"** (if first time)

#### 2. Enable Phone Authentication (for OTP)
- Go to **"Sign-in method"** tab
- Find **"Phone"**
- Click on it
- Toggle **Enable**
- Click **Save**

**NOTE:** Phone auth requires billing, but you get 10,000 free verifications/month

#### 3. Enable Anonymous Authentication (for Guest Login)
- Still in **"Sign-in method"** tab
- Find **"Anonymous"**
- Click on it
- Toggle **Enable**
- Click **Save**

---

### PART 5: Setup Backend Credentials

#### 1. Download Firebase Admin SDK Key

In Firebase Console:
- Click ⚙️ **Settings** → **Project settings**
- Go to **"Service accounts"** tab
- Click **"Generate new private key"**
- Click **"Generate key"** in the dialog
- A JSON file will download

#### 2. Move the Downloaded File
```bash
# Rename and move to backend config folder
mv ~/Downloads/your-project-firebase-adminsdk-*.json \
  /home/nksama/coding/Cloud-Based-Digital-Health-Record-Appointment-Management-System-main/backend/config/firebase-adminsdk.json
```

#### 3. Update Backend .env File

Open `/backend/.env` and update:

```bash
FIREBASE_PROJECT_ID=your-project-id-here
```

Replace `your-project-id-here` with YOUR Firebase project ID (found in Firebase Console → Project Settings)

---

### PART 6: Enable Billing (Required for Phone OTP)

**Only if you want phone OTP to work:**

#### 1. Go to Google Cloud Console
Visit: https://console.cloud.google.com/

#### 2. Select Your Firebase Project
(Same project name as in Firebase)

#### 3. Enable Billing
- Click **"Billing"** in left sidebar
- Click **"Link a billing account"**
- Create new billing account or link existing one
- Add payment method (credit/debit card)

**Don't worry:** First 10,000 phone verifications per month are FREE

---

### PART 7: Test Everything

#### 1. Clean Flutter Build
```bash
cd /home/nksama/coding/Cloud-Based-Digital-Health-Record-Appointment-Management-System-main/mobile_app
flutter clean
flutter pub get
```

#### 2. Run the App
```bash
flutter run
```

#### 3. Test Guest Login
- Click **"Continue as Guest (Testing)"**
- Should authenticate successfully ✅

#### 4. Test Phone OTP (if billing enabled)
- Enter your phone number
- Click **"Send OTP"**
- Should receive SMS code
- Enter code to login

---

## 📋 Quick Command Summary

```bash
# 1. Install Firebase CLI
curl -sL https://firebase.tools | bash

# 2. Login
firebase login

# 3. Go to mobile app
cd /home/nksama/coding/Cloud-Based-Digital-Health-Record-Appointment-Management-System-main/mobile_app

# 4. Install FlutterFire CLI
dart pub global activate flutterfire_cli

# 5. Configure Firebase
flutterfire configure

# 6. Clean and rebuild
flutter clean
flutter pub get
flutter run
```

---

## 🗂️ Files That Will Change

### Mobile App:
- ✅ `mobile_app/lib/firebase_options.dart` - Auto-generated by flutterfire
- ✅ `mobile_app/android/app/google-services.json` - Downloaded from Firebase

### Backend:
- ✅ `backend/config/firebase-adminsdk.json` - Downloaded from Firebase
- ✅ `backend/.env` - Update FIREBASE_PROJECT_ID

---

## ✅ Checklist

- [ ] Created new Firebase project
- [ ] Registered Android app in Firebase
- [ ] Downloaded google-services.json
- [ ] Ran `flutterfire configure`
- [ ] Enabled Anonymous authentication
- [ ] Enabled Phone authentication (optional)
- [ ] Downloaded firebase-adminsdk.json for backend
- [ ] Updated backend/.env with new project ID
- [ ] Enabled billing (optional, for phone OTP)
- [ ] Tested guest login
- [ ] Tested phone OTP (if billing enabled)

---

## 🎉 You're Done!

After completing all steps, the app will use YOUR Firebase project instead of your friend's!

---

## 🆘 Troubleshooting

### Error: "Default Firebase app not initialized"
**Fix:** Run `flutterfire configure` again

### Error: "google-services.json not found"
**Fix:** Download from Firebase Console → Project Settings → Your apps → google-services.json

### Error: "Anonymous auth not allowed"
**Fix:** Enable Anonymous in Firebase Console → Authentication → Sign-in method

### Error: "Phone auth billing not enabled"
**Fix:** Either enable billing OR just use guest login for testing
