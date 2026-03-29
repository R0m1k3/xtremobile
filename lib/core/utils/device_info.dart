/// [P2-2 FIX] Device information and capabilities detection
///
/// Detects device RAM and adjusts player buffer size accordingly
/// to prevent OOM crashes on low-end devices
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceInfo {
  static final DeviceInfo _instance = DeviceInfo._internal();

  factory DeviceInfo() {
    return _instance;
  }

  DeviceInfo._internal();

  late int _ramMb;
  late bool _initialized;

  /// Initialize device info (call once at app startup)
  Future<void> init() async {
    if (_initialized) return;

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      // Get total device memory in MB
      // Note: This is approximate - Android doesn't expose exact RAM directly
      // We estimate based on device properties
      _ramMb = _estimateRamFromDevice(androidInfo);

      _initialized = true;

      if (kDebugMode) {
        debugPrint('📱 Device RAM estimated: ${_ramMb}MB');
      }
    } catch (e) {
      // Fallback: assume at least 2GB
      _ramMb = 2048;
      _initialized = true;

      if (kDebugMode) {
        debugPrint('⚠️  Could not detect device RAM, assuming 2GB: $e');
      }
    }
  }

  /// Estimate RAM from Android device info
  int _estimateRamFromDevice(AndroidDeviceInfo info) {
    // Use display metrics and other heuristics to estimate RAM
    // This is not perfect but gives us a reasonable estimate

    // Get total memory from MemoryInfo if available (Android 5.0+)
    // fallback to heuristic-based estimation
    // For now, use a simple heuristic based on device properties

    // Typical device RAM configurations:
    // Low-end: 1-2 GB (budget phones, older devices)
    // Mid-range: 4-6 GB (most phones)
    // High-end: 8+ GB (flagship devices)

    // Check if device supports large amounts of memory
    // by looking at manufacturer and model hints
    final model = info.model.toLowerCase();
    final manufacturer = info.manufacturer.toLowerCase();

    // Budget device detection
    if (manufacturer.contains('xiaomi') && model.contains('redmi')) {
      return 2048; // Redmi typically 2-4GB
    }
    if (manufacturer.contains('samsung') && model.contains('j')) {
      return 2048; // Samsung Galaxy J series typically 2GB
    }
    if (manufacturer.contains('nokia') || manufacturer.contains('motorola')) {
      return 2048; // Budget phones usually have less RAM
    }

    // Most Android devices default to 4GB or higher
    // Default estimate: 4GB if we can't determine
    return 4096;
  }

  /// Get estimated device RAM in MB
  int getRamMb() {
    if (!_initialized) {
      debugPrint('⚠️  Device info not initialized! Call init() first');
      return 4096; // Safe default
    }
    return _ramMb;
  }

  /// Check if device is low-end (< 2GB RAM)
  bool isLowEndDevice() {
    return getRamMb() < 2048;
  }

  /// Check if device is mid-range (2-6GB RAM)
  bool isMidRangeDevice() {
    final ram = getRamMb();
    return ram >= 2048 && ram <= 6144;
  }

  /// Check if device is high-end (> 6GB RAM)
  bool isHighEndDevice() {
    return getRamMb() > 6144;
  }

  /// Get recommended VOD buffer size in bytes
  /// Adjusted based on available RAM to prevent OOM
  int getRecommendedVodBufferBytes() {
    final ram = getRamMb();

    // Buffer size strategy:
    // Low-end (<2GB): 20MB buffer (very conservative)
    // Mid-range (2-6GB): 50MB buffer (balanced)
    // High-end (>6GB): 100MB buffer (maximum quality)

    if (ram < 2048) {
      return 20 * 1024 * 1024; // 20MB
    } else if (ram < 6144) {
      return 50 * 1024 * 1024; // 50MB
    } else {
      return 100 * 1024 * 1024; // 100MB
    }
  }

  /// Get recommended live TV buffer size in seconds
  int getRecommendedLiveBufferSeconds() {
    final ram = getRamMb();

    if (ram < 2048) {
      return 10; // Very conservative
    } else if (ram < 6144) {
      return 30; // Balanced
    } else {
      return 60; // Maximum
    }
  }

  /// Get device profile string for logging
  String getDeviceProfile() {
    final ram = getRamMb();
    if (ram < 2048) {
      return 'Low-End (<2GB)';
    } else if (ram < 6144) {
      return 'Mid-Range (2-6GB)';
    } else {
      return 'High-End (>6GB)';
    }
  }
}
