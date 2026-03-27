import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Pattern for IPTV stream metadata resolution
/// Handles URL validation, DNS resolution, and codec detection
class StreamResolverPattern {
  /// Result of stream resolution
  final String url;
  final String? codec;
  final int? bitrate;
  final bool isResolvable;
  final String? error;

  StreamResolverPattern({
    required this.url,
    this.codec,
    this.bitrate,
    required this.isResolvable,
    this.error,
  });

  /// Resolve stream URL with parallel checks
  static Future<StreamResolverPattern> resolve(
    String streamUrl, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      if (streamUrl.isEmpty) {
        return StreamResolverPattern(
          url: streamUrl,
          isResolvable: false,
          error: 'Empty URL',
        );
      }

      // Parallel resolution attempts
      final results = await Future.wait([
        _validateUrl(streamUrl).timeout(timeout, onTimeout: () => false),
        _performDnsResolution(streamUrl).timeout(timeout, onTimeout: () => false),
      ], eagerError: false).catchError((_) => [false, false]);

      final isValid = results[0];
      final dnsResolved = results[1];

      if (!isValid) {
        return StreamResolverPattern(
          url: streamUrl,
          isResolvable: false,
          error: 'Invalid URL format',
        );
      }

      if (!dnsResolved) {
        if (kDebugMode) {
          debugPrint('⚠️  DNS resolution warning for: $streamUrl');
        }
      }

      return StreamResolverPattern(
        url: streamUrl,
        isResolvable: true,
        codec: await _detectCodec(streamUrl),
      );
    } catch (e) {
      return StreamResolverPattern(
        url: streamUrl,
        isResolvable: false,
        error: e.toString(),
      );
    }
  }

  /// Validate URL format
  static Future<bool> _validateUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// Perform DNS resolution
  static Future<bool> _performDnsResolution(String url) async {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;

      if (host.isEmpty) return false;

      // Attempt DNS lookup
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));

      return result.isNotEmpty;
    } on SocketException {
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Detect codec from URL or headers
  static Future<String?> _detectCodec(String url) async {
    try {
      // Extract codec hints from URL
      if (url.contains('h264')) return 'h264';
      if (url.contains('h265') || url.contains('hevc')) return 'hevc';
      if (url.contains('vp9')) return 'vp9';
      if (url.contains('av1')) return 'av1';

      // Default to h264 for IPTV streams
      return 'h264';
    } catch (e) {
      return null;
    }
  }

  /// Get human-readable status
  String get statusMessage {
    if (isResolvable) return '✅ Resolvable';
    return '❌ ${error ?? "Unresolvable"}';
  }

  /// Export as JSON
  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'codec': codec,
      'bitrate': bitrate,
      'isResolvable': isResolvable,
      'error': error,
      'status': statusMessage,
    };
  }
}
