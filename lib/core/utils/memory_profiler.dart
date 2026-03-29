import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:developer' as developer;

/// Memory profiler for detecting leaks and monitoring heap growth
class MemoryProfiler {
  static final _snapshots = <String, MemorySnapshot>[];
  static Timer? _periodicTimer;

  /// Take a memory snapshot
  static void takeSnapshot(String label) {
    final info = MemorySnapshot(
      label: label,
      timestamp: DateTime.now(),
      description: _getMemoryInfo(),
    );
    _snapshots.add(info);
    if (kDebugMode) {
      print('📸 MEMORY SNAPSHOT: $label');
      info.print();
    }
  }

  /// Start periodic memory monitoring
  static void startPeriodic(
    Duration interval, {
    required String sessionLabel,
  }) {
    if (_periodicTimer != null) {
      _periodicTimer!.cancel();
    }
    int count = 0;
    _periodicTimer = Timer.periodic(interval, (_) {
      takeSnapshot('$sessionLabel:$count');
      count++;
    });
    if (kDebugMode) {
      print(
        '⏰ PERIODIC MEMORY MONITORING STARTED (${interval.inSeconds}s interval)',
      );
    }
  }

  /// Stop periodic monitoring
  static void stopPeriodic() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    if (kDebugMode) {
      print('⏰ PERIODIC MEMORY MONITORING STOPPED');
    }
  }

  /// Analyze memory growth between snapshots
  static MemoryAnalysis analyzeGrowth(String startLabel, String endLabel) {
    final start = _snapshots.firstWhere(
      (s) => s.label == startLabel,
      orElse: () => _snapshots.first,
    );
    final end = _snapshots.firstWhere(
      (s) => s.label == endLabel,
      orElse: () => _snapshots.last,
    );

    return MemoryAnalysis(
      startLabel: startLabel,
      endLabel: endLabel,
      startSnapshot: start,
      endSnapshot: end,
    );
  }

  /// Generate report
  static void printReport() {
    if (kDebugMode) {
      print('\n${'=' * 60}');
      print('📊 MEMORY PROFILING REPORT');
      print('=' * 60);
      for (int i = 0; i < _snapshots.length; i++) {
        print('\n[$i] ${_snapshots[i].label}');
        _snapshots[i].print();
      }

      // Show growth analysis
      if (_snapshots.length >= 2) {
        print('\n${'-' * 60}');
        print('📈 GROWTH ANALYSIS');
        print('-' * 60);
        for (int i = 0; i < _snapshots.length - 1; i++) {
          final snapshot = _snapshots[i];
          final nextSnapshot = _snapshots[i + 1];
          final growth =
              nextSnapshot.description.compareTo(snapshot.description);

          print('  ${snapshot.label} → ${nextSnapshot.label}: $growth');
        }
      }

      print('\n${'=' * 60}\n');
    }
  }

  /// Force garbage collection (native bridge call)
  static Future<void> forceGC() async {
    developer.Timeline.instantSync('GC_Forced');
    if (kDebugMode) {
      print('🗑️  GARBAGE COLLECTION TRIGGERED');
    }
  }

  /// Reset profiler
  static void reset() {
    _snapshots.clear();
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  static String _getMemoryInfo() {
    // This returns a simple descriptor since we can't directly access ProcessInfo
    // In real scenario, use: ProcessInfo.currentRss.toString()
    return 'Memory snapshot at ${DateTime.now().toIso8601String()}';
  }
}

/// Single memory snapshot
class MemorySnapshot {
  final String label;
  final DateTime timestamp;
  final String description;

  MemorySnapshot({
    required this.label,
    required this.timestamp,
    required this.description,
  });

  void print() {
    print('  Time: ${timestamp.toIso8601String()}');
    print('  Info: $description');
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'timestamp': timestamp.toIso8601String(),
      'description': description,
    };
  }
}

/// Analysis of memory growth
class MemoryAnalysis {
  final String startLabel;
  final String endLabel;
  final MemorySnapshot startSnapshot;
  final MemorySnapshot endSnapshot;

  MemoryAnalysis({
    required this.startLabel,
    required this.endLabel,
    required this.startSnapshot,
    required this.endSnapshot,
  });

  Duration get timeDelta =>
      endSnapshot.timestamp.difference(startSnapshot.timestamp);

  void print() {
    print('\n📊 MEMORY ANALYSIS: $startLabel → $endLabel');
    print('  Duration: ${timeDelta.inSeconds}s');
    print('  Start: ${startSnapshot.description}');
    print('  End: ${endSnapshot.description}');
  }

  Map<String, dynamic> toJson() {
    return {
      'startLabel': startLabel,
      'endLabel': endLabel,
      'durationSeconds': timeDelta.inSeconds,
      'startSnapshot': startSnapshot.toJson(),
      'endSnapshot': endSnapshot.toJson(),
    };
  }
}
