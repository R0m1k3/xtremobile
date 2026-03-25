import 'dart:async';
import 'package:flutter/foundation.dart';

/// Profiler for startup time measurements
class StartupProfiler {
  static final _timings = <String, Stopwatch>{};
  static final _marks = <String, DateTime>{};

  /// Start timing a phase
  static void start(String label) {
    _timings[label] = Stopwatch()..start();
    _marks[label] = DateTime.now();
    if (kDebugMode) {
      print('⏱️  START: $label (${DateTime.now().toIso8601String()})');
    }
  }

  /// Mark completion of a phase
  static void mark(String label) {
    final watch = _timings[label];
    if (watch != null) {
      watch.stop();
      final ms = watch.elapsedMilliseconds;
      if (kDebugMode) {
        print('✅ $label: ${ms}ms');
      }
    }
  }

  /// Get elapsed time for a label
  static int? getElapsedMs(String label) {
    return _timings[label]?.elapsedMilliseconds;
  }

  /// Report all metrics
  static Future<void> reportAll() async {
    if (kDebugMode) {
      print('\n' + ('=' * 50));
      print('⏱️  STARTUP METRICS');
      print('=' * 50);
      _timings.forEach((key, watch) {
        print('  $key: ${watch.elapsedMilliseconds}ms');
      });
      print('=' * 50 + '\n');
    }
  }

  /// Export metrics as JSON for logging
  static Map<String, int> toJson() {
    return _timings
        .map((key, watch) => MapEntry(key, watch.elapsedMilliseconds));
  }

  /// Reset all timings
  static void reset() {
    _timings.clear();
    _marks.clear();
  }
}
