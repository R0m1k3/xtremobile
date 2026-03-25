# 🚀 PHASE 2: PERFORMANCE PROFILING - EXECUTION PLAN

**Date:** March 25, 2026  
**Phase:** 2 of 3  
**Estimated Duration:** 2-3 hours  
**Lead:** Amelia (Developer) + Quinn (QA)

---

## 📊 PROFILING OBJECTIVES

1. **Baseline Metrics** - Establish performance baseline post-cleanup
2. **Component Benchmarks** - MediaKit vs VideoPlayer tradeoffs
3. **Memory Safety** - Detect leaks and lifecycle issues
4. **Encryption Overhead** - Hive performance impact
5. **Build Optimization** - Measure cleanup impact on build times

---

## 🛠️ PROFILING ENVIRONMENT SETUP

### Prerequisites
```bash
# 1. Ensure Flutter SDK is initialized
export PATH="/path/to/flutter/bin:$PATH"
flutter --version

# 2. Verify Android SDK
flutter doctor

# 3. Connect device or start emulator
flutter devices

# 4. Clean build environment
flutter clean
flutter pub get
```

### Target Devices
- **Primary:** Android 13+ device (real hardware if available)
- **Fallback:** Android 10-11 emulator (API 29-30)
- **Optional:** Multiple devices for fragmentation testing

---

## 📈 2.1: STARTUP TIME PROFILING

### Cold Start Measurement
```bash
# Build optimized APK
flutter build apk --release

# Install on device
adb install -r build/app/outputs/flutter-app.apk

# Measure cold start
adb shell am instrument -w \
  -e class=com.xtremflow.mobile.StartupTest \
  com.xtremflow.mobile.test/androidx.test.runner.AndroidJUnitRunner
```

### Expected Metrics to Capture
| Metric | Target | Notes |
|--------|--------|-------|
| Cold Start | < 2.0s | Full app initialization |
| Warm Start | < 0.5s | Background to foreground |
| First Paint | < 1.5s | Initial UI rendered |
| Interactive | < 2.5s | User interaction possible |

### Profiling Code
Create `lib/core/utils/startup_profiler.dart`:
```dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class StartupProfiler {
  static final _timings = <String, Stopwatch>{};

  static void start(String label) {
    _timings[label] = Stopwatch()..start();
    if (kDebugMode) print('⏱️  START: $label');
  }

  static void mark(String label) {
    final watch = _timings[label];
    if (watch != null) {
      watch.stop();
      final ms = watch.elapsedMilliseconds;
      if (kDebugMode) print('✅ $label: ${ms}ms');
    }
  }

  static Future<void> reportAll() async {
    if (kDebugMode) {
      print('\n=== STARTUP METRICS ===');
      _timings.forEach((key, watch) {
        print('$key: ${watch.elapsedMilliseconds}ms');
      });
    }
  }
}
```

Usage in `main.dart`:
```dart
void main() async {
  StartupProfiler.start('app_init');
  
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  
  StartupProfiler.mark('hive_init');
  
  runApp(const MyApp());
}
```

---

## 🎬 2.2: MEDIAKIT VS VIDEOPLAYER BENCHMARK

### Test Streams
- **IPTV Live:** Use sample M3U playlist (low latency required)
- **VOD Movie:** 2-hour file, H.264 codec
- **Edge Case:** High bitrate 4K stream (if available)

### Metrics to Compare
```
MediaKit Performance:
├─ Load Time: [measure]
├─ Memory (peak): [measure]
├─ CPU (avg): [measure]
├─ Codec Support: [test]
└─ Seek Response: [measure]

VideoPlayer Performance:
├─ Load Time: [measure]
├─ Memory (peak): [measure]
├─ CPU (avg): [measure]
├─ Codec Support: [test]
└─ Seek Response: [measure]
```

### Measurement Code
Create `lib/core/utils/video_profiler.dart`:
```dart
import 'dart:async';
import 'package:flutter/foundation.dart';

class VideoProfiler {
  static final metrics = <String, StreamMetrics>{};

  static void startStreamMetrics(String streamName) {
    metrics[streamName] = StreamMetrics(
      startTime: DateTime.now(),
      loadStart: DateTime.now(),
    );
  }

  static void markLoadComplete(String streamName) {
    metrics[streamName]?.loadTime = 
        DateTime.now().difference(metrics[streamName]!.loadStart).inMilliseconds;
    if (kDebugMode) {
      print('📺 Load Time: ${metrics[streamName]?.loadTime}ms');
    }
  }

  static void recordMemoryPeak(String streamName, int bytes) {
    metrics[streamName]?.peakMemoryMB = bytes ~/ (1024 * 1024);
  }

  static void recordCpuUsage(String streamName, double percentage) {
    metrics[streamName]?.avgCpuPercent = percentage;
  }
}

class StreamMetrics {
  DateTime startTime;
  DateTime loadStart;
  int? loadTime;
  int? peakMemoryMB;
  double? avgCpuPercent;
  bool? seekResponsive;

  StreamMetrics({
    required this.startTime,
    required this.loadStart,
  });
}
```

---

## 💾 2.3: MEMORY LEAK DETECTION

### Test Procedure
1. **Load stream** - MediaKit player
2. **Monitor heap** - 15 minutes continuous playback
3. **Check growth** - Should plateau after stabilization
4. **Lifecycle test** - Pause/resume, hide/show 10 cycles

### Memory Monitoring
```bash
# Connect device and run profiling
adb shell dumpsys meminfo com.xtremflow.mobile

# Capture baseline
adb shell dumpsys meminfo com.xtremflow.mobile > baseline.txt

# After 15min playback
adb shell dumpsys meminfo com.xtremflow.mobile > after_playback.txt

# Compare
diff baseline.txt after_playback.txt
```

### Critical Metrics
- **Native Heap:** Should not grow indefinitely
- **Dart Heap:** Should stabilize after initial ramp
- **Graphics Memory:** Should be constant during playback
- **PSS Total:** Final < Initial + 50MB

---

## 🔐 2.4: HIVE ENCRYPTION OVERHEAD

### Benchmark Code
```dart
import 'package:hive/hive.dart';
import 'dart:typed_data';

Future<void> benchmarkHiveEncryption() async {
  // Test data: 1000 playlists × 100 channels each
  final testBoxName = 'benchmark_test';
  
  // Scenario 1: Unencrypted writes
  final unencryptedBox = await Hive.openBox(testBoxName);
  final unencStart = Stopwatch()..start();
  
  for (int i = 0; i < 1000; i++) {
    await unencryptedBox.put('key_$i', 'value_' * 50);
  }
  unencStart.stop();
  
  await unencryptedBox.deleteFromDisk();
  
  // Scenario 2: Encrypted writes
  final encryptionKey = Hive.generateSecureKey();
  final encryptedBox = await Hive.openBox(
    testBoxName,
    encryptionCipher: HiveAesCipher(encryptionKey),
  );
  final encStart = Stopwatch()..start();
  
  for (int i = 0; i < 1000; i++) {
    await encryptedBox.put('key_$i', 'value_' * 50);
  }
  encStart.stop();
  
  await encryptedBox.deleteFromDisk();
  
  print('Write Performance:');
  print('  Unencrypted: ${unencStart.elapsedMilliseconds}ms');
  print('  Encrypted:   ${encStart.elapsedMilliseconds}ms');
  print('  Overhead:    ${((encStart.elapsedMilliseconds / unencStart.elapsedMilliseconds - 1) * 100).toStringAsFixed(1)}%');
}
```

### Expected Overhead
- **Target:** < 15% performance impact
- **Acceptable:** < 25% impact
- **Concern:** > 30% impact

---

## 📋 EXECUTION CHECKLIST

### Pre-Profiling
- [ ] Flutter SDK fully initialized (version 3.x+)
- [ ] Android SDK API 30+ available
- [ ] Device/emulator connected and responsive
- [ ] App builds cleanly (`flutter build apk --release`)
- [ ] Logcat cleared: `adb logcat -c`

### During Profiling
- [ ] Device plugged in, not charging (stable power)
- [ ] No other apps running
- [ ] Network stable (for stream tests)
- [ ] Screen timeout disabled
- [ ] Developer mode enabled

### Metrics Collection
- [ ] Startup timing (3 runs, average)
- [ ] Video load time (MediaKit)
- [ ] Video load time (VideoPlayer)
- [ ] Memory baseline before/after
- [ ] CPU usage during playback
- [ ] Hive encryption overhead

---

## 📊 RESULTS TEMPLATE

Create `PHASE_2_PROFILING_RESULTS.md` after execution:

```markdown
# Phase 2 Profiling Results

## 2.1 Startup Time
- Cold Start: XXXms ✅/❌
- Warm Start: XXXms
- First Paint: XXXms
- Bottleneck: [component]

## 2.2 Video Playback
| Component | Metric | Result | Target | Status |
|-----------|--------|--------|--------|--------|
| MediaKit | Load Time | XXXms | <500ms | ✅/❌ |
| MediaKit | Memory | XXmb | <150MB | ✅/❌ |
| VideoPlayer | Load Time | XXXms | <500ms | ✅/❌ |
| VideoPlayer | Memory | XXmb | <150MB | ✅/❌ |

## 2.3 Memory Leaks
- Baseline PSS: XXmb
- After 15min: XXmb
- Growth Rate: Xmb/min
- Status: ✅ CLEAN / ⚠️ INVESTIGATE

## 2.4 Hive Encryption
- Write Overhead: X%
- Read Overhead: X%
- Status: ✅ ACCEPTABLE / ⚠️ NEEDS REVIEW
```

---

## 🎯 NEXT STEPS

**After profiling completes:**
1. Execute Phase 3: Architecture Refactor
2. Review findings with team
3. Create optimization tickets for bottlenecks
4. Plan Phase 4: Production Build

**Ready to proceed?** Run commands in order:
```bash
flutter clean
flutter pub get
flutter build apk --release
# Then run test procedure for each section
```

---

**Lead Responsibility:** Amelia  
**Technical Support:** Winston (Architecture insights)  
**QA Validation:** Quinn (Test execution)
