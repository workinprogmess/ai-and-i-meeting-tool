#!/bin/bash

# verification script for screencapturekit integration

echo "🔍 verifying screencapturekit setup..."
echo ""

# check if files exist
echo "✓ checking swift files:"
if [ -f "AI-and-I/ScreenCaptureManager.swift" ]; then
    echo "  ✅ ScreenCaptureManager.swift exists"
else
    echo "  ❌ ScreenCaptureManager.swift missing"
fi

if [ -f "AI-and-I/AppPickerView.swift" ]; then
    echo "  ✅ AppPickerView.swift exists"
else
    echo "  ❌ AppPickerView.swift missing"
fi

echo ""
echo "✓ checking project configuration:"

# check if screen recording permission is in project
if grep -q "NSScreenCaptureUsageDescription" AI-and-I.xcodeproj/project.pbxproj; then
    echo "  ✅ screen recording permission configured"
else
    echo "  ❌ screen recording permission missing"
fi

# check if mic permission is lowercase
if grep -q "ai&i needs microphone access" AI-and-I.xcodeproj/project.pbxproj; then
    echo "  ✅ microphone permission is lowercase"
else
    echo "  ⚠️  microphone permission might not be lowercase"
fi

echo ""
echo "📋 next steps:"
echo "  1. open AI-and-I.xcodeproj in xcode"
echo "  2. add the two swift files to the project"
echo "  3. build and run (⌘+r)"
echo "  4. test with zoom/teams/browser"
echo ""
echo "refer to ADD_FILES_TO_XCODE.md for detailed instructions"