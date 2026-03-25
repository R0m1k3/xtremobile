# 🔨 BUILD GUIDE - XtreMobile

**Application:** XtreMobile IPTV
**Target Platform:** Android (ARM64)
**Build Type:** Release APK
**Status:** Ready to build

---

## 📋 PREREQUISITES

### Required
- **Flutter SDK** 3.0.0+ ([Install](https://flutter.dev/docs/get-started/install))
- **Android SDK** with API 30+ (usually bundled with Flutter)
- **Java JDK** 11+ (required by Android SDK)
- **Git** (for version control)

### Optional
- Android Device (for testing)
- Android Emulator

---

## 🚀 BUILD STEPS

### Option 1: Using Build Script (Recommended)

```bash
# Make script executable
chmod +x build.sh

# Run build
./build.sh
```

### Option 2: Manual Build

```bash
# 1. Clean previous builds
flutter clean

# 2. Get dependencies
flutter pub get

# 3. Generate code (if needed)
flutter pub run build_runner build --delete-conflicting-outputs

# 4. Build release APK
flutter build apk --release \
  --target-platform android-arm64 \
  --split-per-abi
```

### Option 3: Using IDE

```
Android Studio / VS Code:
1. Open project in IDE
2. Run → Flutter Build → Build APK (Release)
```

---

## 📊 BUILD OUTPUT

Successful build produces APK at:
```
build/app/outputs/flutter-apk/app-release.apk
```

File size: ~50-80 MB (after optimizations)

---

## 🔧 SETUP FLUTTER (if not installed)

### macOS
```bash
# Using Homebrew
brew install flutter

# Or download manually
git clone https://github.com/flutter/flutter.git -b stable

# Add to PATH
export PATH="$PATH:$HOME/flutter/bin"
```

### Linux
```bash
# Download Flutter
git clone https://github.com/flutter/flutter.git -b stable ~/flutter

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="$PATH:$HOME/flutter/bin"

# Verify
flutter doctor
```

### Windows
```powershell
# Download from https://flutter.dev/docs/get-started/install/windows
# Or use scoop:
scoop install flutter

# Add to PATH in Environment Variables
```

### Verify Installation
```bash
flutter doctor -v
```

Should show:
```
✓ Flutter (Channel stable)
✓ Android toolchain
✓ Android SDK
✓ Java version
```

---

## 📱 INSTALL ON DEVICE

### Connect Device
```bash
# List connected devices
adb devices

# Or use Flutter
flutter devices
```

### Install APK
```bash
# Method 1: Using adb
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Method 2: Using Flutter
flutter install --release

# Method 3: Drag to device (if file manager available)
open build/app/outputs/flutter-apk/
# Then drag app-release.apk to Android device
```

---

## 🧪 VERIFY BUILD

### Check APK Size
```bash
ls -lh build/app/outputs/flutter-apk/app-release.apk
```

### Verify with aapt (Android Asset Packaging Tool)
```bash
aapt dump badging build/app/outputs/flutter-apk/app-release.apk
```

### Test Installation
1. Install APK on device
2. Launch app
3. Verify:
   - No crashes on startup
   - Smooth navigation
   - Video playback works
   - All tabs load correctly

---

## 🐛 TROUBLESHOOTING

### "Flutter not found"
```bash
# Add to PATH
export PATH="$PATH:$HOME/flutter/bin"

# Or specify full path
/path/to/flutter/bin/flutter build apk --release
```

### "Android SDK not found"
```bash
flutter config --android-sdk /path/to/android-sdk
flutter doctor
```

### "Gradle build failed"
```bash
# Clean and retry
flutter clean
flutter pub get
flutter build apk --release
```

### "Java version error"
```bash
# Check Java version
java -version

# Should be 11 or higher
# If not, install Java 11 JDK
```

### "Out of memory during build"
```bash
# Increase Gradle memory
export _JAVA_OPTIONS="-Xmx4g"
flutter build apk --release
```

### "Dependency resolution failed"
```bash
# Clear pub cache
flutter pub cache clean

# Update pubspec
flutter pub upgrade

# Rebuild
flutter pub get
flutter build apk --release
```

---

## 📊 BUILD CONFIGURATION

### Current Configuration
```yaml
name: xtremflow
version: 1.5.1+11
minSdk: 30
targetSdk: 34
```

### Optimizations Applied
```
✅ APK split by ABI (smaller downloads)
✅ Release mode (optimized, no debug symbols)
✅ ARM64 architecture (most common Android devices)
✅ Minified Dart code
✅ Tree-shaking unused code
```

Expected Results:
- Build size: 50-80 MB
- Installation time: <1 minute
- Startup time: 3-5 seconds (cold)
- Memory: 400-500 MB peak

---

## 🎯 NEXT STEPS AFTER BUILD

1. **Install on Device**
   ```bash
   adb install -r build/app/outputs/flutter-apk/app-release.apk
   ```

2. **Test Performance**
   - Measure startup time
   - Test tab switching
   - Play sample stream
   - Monitor memory usage

3. **Validate Optimizations**
   - Cold startup should be 3-5s
   - Tab switching should be instant
   - No crashes
   - Smooth playback

4. **Distribute**
   - Upload to Play Store
   - Share via Google Drive
   - Use internal testing

---

## 📦 BUILD VARIANTS

### Debug Build (for testing)
```bash
flutter build apk --debug
# Much faster build, can debug on device
# Not for release
```

### Release Build (for production)
```bash
flutter build apk --release
# Optimized, minified, tree-shaken
# Ready for Play Store
```

### App Bundle (for Play Store)
```bash
flutter build appbundle --release
# Smaller downloads per device
# Recommended for Play Store
```

---

## ✅ BUILD CHECKLIST

- [ ] Flutter SDK installed (3.0.0+)
- [ ] Android SDK with API 30+
- [ ] Java JDK 11+
- [ ] All dependencies resolved (`flutter pub get`)
- [ ] Code compiles without errors
- [ ] Tests pass (if applicable)
- [ ] APK builds successfully
- [ ] APK installs on device
- [ ] App launches without crashes
- [ ] All optimizations working

---

## 📞 SUPPORT

If you encounter build issues:

1. Check Flutter Doctor
   ```bash
   flutter doctor -v
   ```

2. Check Android SDK
   ```bash
   flutter config --show-config
   ```

3. Check Gradle
   ```bash
   cd android && ./gradlew --version
   ```

4. Review build output
   ```bash
   flutter build apk --release -v 2>&1 | tail -50
   ```

---

**Last Updated:** March 25, 2026
**Status:** ✅ Ready to Build
