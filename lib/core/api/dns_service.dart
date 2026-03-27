/// [P2-1 FIX] Unified DNS Resolution Service
///
/// Consolidates DnsResolver and DnsFallbackInterceptor into a single service
/// with shared cache to prevent duplicate DNS calls.
///
/// Problem: Two separate DNS implementations with two separate caches
/// - DnsResolver: Manual DoH resolution (proactive)
/// - DnsFallbackInterceptor: Fallback on DNS error (reactive)
/// - Result: Same hostname resolved twice, wasting network calls
///
/// Solution: Single unified service with shared cache

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class UnifiedDnsService {
  // Singleton instance
  static final UnifiedDnsService _instance = UnifiedDnsService._internal();

  factory UnifiedDnsService() {
    return _instance;
  }

  UnifiedDnsService._internal();

  // Shared DNS cache with TTL tracking
  final Map<String, _DnsCacheEntry> _cache = {};

  // In-flight requests to deduplicate concurrent calls
  final Map<String, Future<String?>> _inFlightRequests = {};

  static const int _cacheTtlSeconds = 3600; // 1 hour TTL

  /// Resolve hostname to IP using DNS-over-HTTPS
  /// Returns null if resolution fails
  /// Shared cache prevents duplicate calls
  Future<String?> resolve(String hostname) async {
    // Check if we have valid cached entry
    final cached = _cache[hostname];
    if (cached != null && !cached.isExpired) {
      if (kDebugMode) {
        debugPrint('✅ DNS Cache hit: $hostname -> ${cached.ip}');
      }
      return cached.ip;
    }

    // Check if this hostname is already being resolved (deduplication)
    if (_inFlightRequests.containsKey(hostname)) {
      if (kDebugMode) {
        debugPrint('⏳ DNS: Reusing in-flight request for $hostname');
      }
      return _inFlightRequests[hostname];
    }

    // Perform resolution
    final future = _performResolution(hostname);
    _inFlightRequests[hostname] = future;

    try {
      final ip = await future;

      // Cache successful resolution
      if (ip != null) {
        _cache[hostname] = _DnsCacheEntry(ip);
        if (kDebugMode) {
          debugPrint('✅ DNS Resolved: $hostname -> $ip');
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ DNS Failed: Could not resolve $hostname');
        }
      }

      return ip;
    } finally {
      _inFlightRequests.remove(hostname);
    }
  }

  /// Perform actual DNS resolution via DoH
  Future<String?> _performResolution(String hostname) async {
    // Try Google DNS via IP first (avoids needing DNS to query DNS)
    String? ip = await _queryDoH(
      'https://8.8.8.8/resolve?name=$hostname&type=A',
    );

    // Fallback to Cloudflare
    ip ??= await _queryDoH(
      'https://1.1.1.1/dns-query?name=$hostname&type=A',
      headers: {'accept': 'application/dns-json'},
    );

    return ip;
  }

  /// Query DNS provider via HTTPS
  Future<String?> _queryDoH(
    String url, {
    Map<String, String>? headers,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = (cert, host, port) => true;

      final request = await client.getUrl(Uri.parse(url));
      request.headers.add('accept', 'application/dns-json');

      if (headers != null) {
        headers.forEach((k, v) => request.headers.add(k, v));
      }

      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body);

        if (json['Status'] == 0 && json['Answer'] != null) {
          final answers = json['Answer'] as List;
          for (final ans in answers) {
            if (ans['type'] == 1) {
              // Type A record
              return ans['data'] as String;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('DNS DoH query error: $e');
      }
    } finally {
      client?.close();
    }

    return null;
  }

  /// Get cache stats for debugging
  Map<String, dynamic> getCacheStats() {
    final expiredCount = _cache.values.where((e) => e.isExpired).length;
    return {
      'total_entries': _cache.length,
      'expired_entries': expiredCount,
      'valid_entries': _cache.length - expiredCount,
      'in_flight_requests': _inFlightRequests.length,
    };
  }

  /// Clear DNS cache
  void clearCache() {
    _cache.clear();
    if (kDebugMode) {
      debugPrint('🗑️  DNS cache cleared');
    }
  }
}

/// Cache entry with TTL
class _DnsCacheEntry {
  final String ip;
  final DateTime timestamp;

  _DnsCacheEntry(this.ip) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp).inSeconds > 3600;
}
