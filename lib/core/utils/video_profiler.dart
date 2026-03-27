import 'dart:async';
import 'package:flutter/foundation.dart';

/// Profiler for video playback performance metrics
class VideoProfiler {
  static final metrics = <String, VideoMetrics>{};

  /// Start profiling a video stream
  static void startStreamMetrics(String streamName) {
    metrics[streamName] = VideoMetrics(
      streamName: streamName,
      startTime: DateTime.now(),
      loadStart: DateTime.now(),
    );
    if (kDebugMode) {
      print('📺 START PROFILING: $streamName');
    }
  }

  /// Mark when video is ready to play
  static void markLoadComplete(String streamName) {
    final m = metrics[streamName];
    if (m != null) {
      m.loadTime = DateTime.now().difference(m.loadStart).inMilliseconds;
      if (kDebugMode) {
        print('✅ VIDEO LOADED: ${m.loadTime}ms');
      }
    }
  }

  /// Mark first frame rendered
  static void markFirstFrame(String streamName) {
    final m = metrics[streamName];
    if (m != null) {
      m.firstFrameTime = DateTime.now().difference(m.loadStart).inMilliseconds;
      if (kDebugMode) {
        print('🎬 FIRST FRAME: ${m.firstFrameTime}ms');
      }
    }
  }

  /// Record peak memory usage during playback
  static void recordMemoryPeak(String streamName, int bytes) {
    final m = metrics[streamName];
    if (m != null) {
      m.peakMemoryMB = bytes ~/ (1024 * 1024);
      if (kDebugMode) {
        print('💾 PEAK MEMORY: ${m.peakMemoryMB}MB');
      }
    }
  }

  /// Record average CPU usage
  static void recordCpuUsage(String streamName, double percentage) {
    final m = metrics[streamName];
    if (m != null) {
      m.avgCpuPercent = percentage;
      if (kDebugMode) {
        print('⚡ AVG CPU: ${percentage.toStringAsFixed(1)}%');
      }
    }
  }

  /// Mark seek response time
  static void markSeekResponse(String streamName, int durationMs) {
    final m = metrics[streamName];
    if (m != null) {
      m.seekResponseMs = durationMs;
      if (kDebugMode) {
        print('🔄 SEEK RESPONSE: ${durationMs}ms');
      }
    }
  }

  /// End profiling session
  static void endSession(String streamName) {
    final m = metrics[streamName];
    if (m != null) {
      m.endTime = DateTime.now();
      m.totalDurationMs = m.endTime!.difference(m.startTime).inMilliseconds;
      if (kDebugMode) {
        print('\n${'=' * 50}');
        print('📊 VIDEO METRICS: $streamName');
        print('=' * 50);
        m.printMetrics();
        print('=' * 50 + '\n');
      }
    }
  }

  /// Get summary of all metrics
  static void printSummary() {
    if (kDebugMode) {
      print('\n${'=' * 50}');
      print('📈 VIDEO PROFILING SUMMARY');
      print('=' * 50);
      metrics.forEach((key, m) {
        print('\n$key:');
        m.printMetrics();
      });
      print('=' * 50 + '\n');
    }
  }

  /// Export metrics as JSON
  static Map<String, dynamic> toJson() {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'metrics': {
        for (var e in metrics.entries) e.key: e.value.toJson(),
      },
    };
  }

  /// Reset all metrics
  static void reset() {
    metrics.clear();
  }
}

/// Container for video stream metrics
class VideoMetrics {
  final String streamName;
  final DateTime startTime;
  final DateTime loadStart;

  int? loadTime; // ms
  int? firstFrameTime; // ms
  int? peakMemoryMB;
  double? avgCpuPercent;
  int? seekResponseMs;
  DateTime? endTime;
  int? totalDurationMs;

  VideoMetrics({
    required this.streamName,
    required this.startTime,
    required this.loadStart,
  });

  void printMetrics() {
    print('  Load Time: ${loadTime ?? "N/A"}ms');
    print('  First Frame: ${firstFrameTime ?? "N/A"}ms');
    print('  Peak Memory: ${peakMemoryMB ?? "N/A"}MB');
    print('  Avg CPU: ${avgCpuPercent?.toStringAsFixed(1) ?? "N/A"}%');
    print('  Seek Response: ${seekResponseMs ?? "N/A"}ms');
    print('  Total Duration: ${totalDurationMs ?? "N/A"}ms');
  }

  Map<String, dynamic> toJson() {
    return {
      'streamName': streamName,
      'loadTime': loadTime,
      'firstFrameTime': firstFrameTime,
      'peakMemoryMB': peakMemoryMB,
      'avgCpuPercent': avgCpuPercent,
      'seekResponseMs': seekResponseMs,
      'totalDurationMs': totalDurationMs,
    };
  }
}
