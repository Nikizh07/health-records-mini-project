#!/bin/bash

# Firebase Configuration Checker
# Run this to see what credentials are currently configured

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║          Firebase Configuration Status Check                  ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Check Mobile App
echo "📱 MOBILE APP (Flutter):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "mobile_app/lib/firebase_options.dart" ]; then
    echo "✅ firebase_options.dart exists"
    PROJECT_ID=$(grep -o 'projectId: [^,]*' mobile_app/lib/firebase_options.dart | head -1 | cut -d "'" -f 2)
    API_KEY=$(grep -o 'apiKey: [^,]*' mobile_app/lib/firebase_options.dart | head -1 | cut -d "'" -f 2)
    echo "   Project ID: $PROJECT_ID"
    echo "   API Key: ${API_KEY:0:20}..."
else
    echo "❌ firebase_options.dart NOT FOUND"
fi

if [ -f "mobile_app/android/app/google-services.json" ]; then
    echo "✅ google-services.json exists"
    GS_PROJECT=$(grep -o '"project_id": "[^"]*"' mobile_app/android/app/google-services.json | head -1 | cut -d '"' -f 4)
    echo "   Project ID: $GS_PROJECT"
else
    echo "❌ google-services.json NOT FOUND"
fi

echo ""

# Check Backend
echo "🖥️  BACKEND (Node.js):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "backend/.env" ]; then
    echo "✅ .env file exists"
    ENV_PROJECT=$(grep FIREBASE_PROJECT_ID backend/.env | cut -d '=' -f 2)
    echo "   Project ID: $ENV_PROJECT"
else
    echo "❌ .env file NOT FOUND"
fi

if [ -f "backend/config/firebase-adminsdk.json" ]; then
    echo "✅ firebase-adminsdk.json exists"
    ADMIN_PROJECT=$(grep -o '"project_id": "[^"]*"' backend/config/firebase-adminsdk.json | head -1 | cut -d '"' -f 4)
    echo "   Project ID: $ADMIN_PROJECT"
else
    echo "❌ firebase-adminsdk.json NOT FOUND"
fi

echo ""

# Summary
echo "📊 SUMMARY:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if all project IDs match
ALL_PROJECTS=()
[ ! -z "$PROJECT_ID" ] && ALL_PROJECTS+=("$PROJECT_ID")
[ ! -z "$GS_PROJECT" ] && ALL_PROJECTS+=("$GS_PROJECT")
[ ! -z "$ENV_PROJECT" ] && ALL_PROJECTS+=("$ENV_PROJECT")
[ ! -z "$ADMIN_PROJECT" ] && ALL_PROJECTS+=("$ADMIN_PROJECT")

if [ ${#ALL_PROJECTS[@]} -eq 0 ]; then
    echo "❌ NO Firebase configuration found!"
    echo ""
    echo "📖 Follow: REPLACE_FIREBASE_CREDENTIALS.md"
elif [ $(printf '%s\n' "${ALL_PROJECTS[@]}" | sort -u | wc -l) -eq 1 ]; then
    echo "✅ All files configured for project: ${ALL_PROJECTS[0]}"
    echo ""
    echo "🎯 This is your friend's project. To use yours:"
    echo "   See: REPLACE_FIREBASE_CREDENTIALS.md"
else
    echo "⚠️  Mixed project IDs detected!"
    echo "   Some files have different Firebase projects"
    echo ""
    echo "📖 Follow: REPLACE_FIREBASE_CREDENTIALS.md"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "For detailed setup: REPLACE_FIREBASE_CREDENTIALS.md"
echo "Quick reference: QUICK_FIREBASE_SETUP.txt"
