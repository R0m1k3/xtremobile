#!/bin/bash

# XtreMobile Build Script
# Builds optimized release APK with performance improvements

set -e

echo "🚀 XtreMobile Build Script"
echo "=========================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check Flutter is available
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter not found in PATH${NC}"
    echo ""
    echo "Please ensure Flutter is installed and added to PATH:"
    echo "  export PATH=\"\$PATH:\$HOME/flutter/bin\""
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Flutter found$(flutter --version | head -1)${NC}"
echo ""

# Verify Android SDK
echo "Checking Android SDK..."
flutter doctor -v 2>/dev/null | head -20
echo ""

cd "$(dirname "$0")"

echo -e "${YELLOW}Step 1: Clean build cache${NC}"
flutter clean
echo -e "${GREEN}✅ Clean complete${NC}"
echo ""

echo -e "${YELLOW}Step 2: Get dependencies${NC}"
flutter pub get
echo -e "${GREEN}✅ Dependencies updated${NC}"
echo ""

echo -e "${YELLOW}Step 3: Generate code${NC}"
flutter pub run build_runner build --delete-conflicting-outputs 2>/dev/null || echo "No code generation needed"
echo -e "${GREEN}✅ Code generation complete${NC}"
echo ""

echo -e "${YELLOW}Step 4: Build APK (Release)${NC}"
echo "Building optimized release APK..."
flutter build apk --release \
  --target-platform android-arm64 \
  --split-per-abi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful!${NC}"
    echo ""
    echo "Output APKs:"
    find build/app/outputs/flutter-apk -name "*.apk" -type f -exec ls -lh {} \;
    echo ""
    echo "Next steps:"
    echo "  1. Connect Android device or start emulator"
    echo "  2. Run: adb install -r build/app/outputs/flutter-apk/app-release.apk"
    echo "  3. Or: flutter install --release"
else
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Build complete!${NC}"
