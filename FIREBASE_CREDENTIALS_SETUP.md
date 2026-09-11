# 🔑 Firebase Credentials Setup Guide

## Current Status

✅ **Mobile App** - Fully configured with Firebase credentials  
⚠️ **Backend** - Needs Firebase Admin SDK service account key

---

## 📱 Mobile App Credentials (Already Done ✅)

**File:** `mobile_app/lib/firebase_options.dart`

```
Project ID: migrant-workers-89bb8
API Key: AIzaSyA0KFDGwLdfbNSi13y3CpHxs_282JuCSMM
Storage Bucket: migrant-workers-89bb8.appspot.com
```

**No action needed for mobile app!**

---

## 🖥️ Backend Credentials Setup (Required)

### What You Need:

1. ✅ `.env` file (I just created it for you)
2. ❌ Firebase Admin SDK JSON key (you need to download this)

---

## 📥 Download Firebase Admin SDK Key

### Step 1: Go to Firebase Console

Open: https://console.firebase.google.com/

### Step 2: Select Your Project

Click on: **migrant-workers-89bb8**

### Step 3: Open Project Settings

Click the ⚙️ gear icon (top-left) → **Project settings**

### Step 4: Go to Service Accounts Tab

Click on the **Service accounts** tab at the top

### Step 5: Generate Private Key

You'll see a section that says:
```
Admin SDK configuration snippet
```

Click the button: **Generate new private key**

### Step 6: Confirm Download

A dialog will appear:
```
Generate new private key?
A new private key will be generated and downloaded. 
This key should be kept secure.
```

Click: **Generate key**

A JSON file will download, something like:
```
migrant-workers-89bb8-firebase-adminsdk-xxxxx-xxxxxxxxxx.json
```

### Step 7: Rename and Move the File

**Rename** the downloaded file to:
```
firebase-adminsdk.json
```

**Move** it to:
```
backend/config/firebase-adminsdk.json
```

Full path should be:
```
/home/nksama/coding/Cloud-Based-Digital-Health-Record-Appointment-Management-System-main/backend/config/firebase-adminsdk.json
```

---

## ✅ Verify Setup

After placing the file, your backend structure should look like:

```
backend/
├── config/
│   ├── firebase-adminsdk.json  ← Should exist now
│   ├── firebase.js
│   ├── db.js
│   └── prisma.js
├── .env                         ← I created this
├── .env.example
└── server.js
```

---

## 🧪 Test Backend

Once the file is in place:

```bash
cd backend
npm install
npm run dev
```

You should see:
```
✅ Firebase Admin initialized successfully
🚀 Server running on port 3000
```

If you see an error about missing firebase-adminsdk.json, the file is not in the right location.

---

## 🔒 Security Notes

**IMPORTANT:** 
- ❌ **NEVER** commit `firebase-adminsdk.json` to git
- ❌ **NEVER** share this file publicly
- ✅ It's already in `.gitignore` as `firebase-adminsdk*.json`

This file contains private keys that give full access to your Firebase project!

---

## 📋 Summary of Your Credentials

### Mobile App (Flutter)
```
File: mobile_app/lib/firebase_options.dart
Status: ✅ Configured
Project: migrant-workers-89bb8
```

### Backend (Node.js)
```
File: backend/.env
Status: ✅ Created

File: backend/config/firebase-adminsdk.json
Status: ⏳ You need to download from Firebase Console
```

---

## 🎯 Next Steps

1. ✅ Enable Anonymous Authentication in Firebase Console (from previous guide)
2. ⏳ Download firebase-adminsdk.json and place in backend/config/
3. ⏳ Update DATABASE_URL in backend/.env with your database credentials
4. ✅ Run mobile app: `flutter run`
5. ✅ Click "Continue as Guest (Testing)" button

---

## ❓ Need Help?

If you're having trouble finding the Firebase Admin SDK key:
- Make sure you're logged into Firebase Console
- Make sure you've selected the correct project (migrant-workers-89bb8)
- The Service Accounts tab is under Project Settings (gear icon)
