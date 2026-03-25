/// Xtream Codes API Service - Mobile Version
///
/// Handles Xtream API communication with batching and caching optimizations
/// for mobile platforms. Designed for performance with TiviMate-level efficiency.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/xtream_models.dart';
import 'package:xtremflow/core/models/playlist_config.dart';
import 'package:xtremflow/core/api/api_client.dart';

/// EPG cache entry with TTL
class _EpgCacheEntry {
  final Map<String, ShortEpg> data;
  final DateTime timestamp;
  static const int ttlSeconds = 3600; // 1 hour TTL

  _EpgCacheEntry(this.data) : timestamp = DateTime.now();

  bool get isExpired => DateTime.now().difference(timestamp).inSeconds > ttlSeconds;
}

/// Xtream API Service for Mobile
///
/// Optimized for Android with:
/// - Batch EPG loading (N+1 prevention)
/// - Provider-level caching with TTL
/// - Configurable timeouts and retries
/// - Memory-efficient streaming
class XtreamServiceMobile {
  final String cacheDir;
  late Dio _dio;
  late String _baseUrl;
  late String _username;
  late String _password;

  // Batch EPG cache to prevent N+1 queries
  final Map<String, _EpgCacheEntry> _epgBatchCache = {};

  // In-flight batch requests to deduplicate concurrent calls
  final Map<String, Future<Map<String, ShortEpg>>> _inFlightBatches = {};

  XtreamServiceMobile(this.cacheDir);

  /// Initialize with playlist configuration
  Future<void> setPlaylistAsync(PlaylistConfig config) async {
    _baseUrl = config.serverUrl;
    _username = config.username;
    _password = config.password;

    // Use shared Dio instance from ApiClient (with DNS resolution, etc.)
    _dio = ApiClient.instance;
  }

  /// Get live channels for a category (with batch EPG support)
  Future<List<Channel>> getLiveChannels(String categoryId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_live_streams',
          'category_id': categoryId,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => Channel.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error loading live channels: $e');
      return [];
    }
  }

  /// Get SHORT EPG for a SINGLE channel (legacy, avoid - use getBatchEPG instead)
  Future<ShortEpg> getShortEPG(String streamId) async {
    // For backward compatibility, but prefer batch loading
    final batch = await getBatchEPG([streamId]);
    return batch[streamId] ?? ShortEpg(nowPlaying: null, nextPlaying: null);
  }

  /// Get SHORT EPG for MULTIPLE channels in ONE request
  ///
  /// This is the optimized method that prevents N+1 queries.
  /// Instead of 50 requests for 50 channels, this loads all at once.
  /// Results are cached for 1 hour to avoid repeated requests.
  Future<Map<String, ShortEpg>> getBatchEPG(List<String> streamIds) async {
    if (streamIds.isEmpty) return {};

    // Create cache key from sorted IDs for consistency
    final cacheKey = streamIds.toSet().toString();

    // Check if we have valid cached data
    final cached = _epgBatchCache[cacheKey];
    if (cached != null && !cached.isExpired) {
      if (kDebugMode) print('✅ EPG batch cache hit: ${streamIds.length} channels');
      return cached.data;
    }

    // Check if this batch is already being loaded (deduplication)
    if (_inFlightBatches.containsKey(cacheKey)) {
      if (kDebugMode) print('⏳ Reusing in-flight EPG batch request');
      return _inFlightBatches[cacheKey]!;
    }

    // Load the batch
    final future = _loadEpgBatch(streamIds, cacheKey);
    _inFlightBatches[cacheKey] = future;

    try {
      final result = await future;
      _epgBatchCache[cacheKey] = _EpgCacheEntry(result);
      return result;
    } finally {
      _inFlightBatches.remove(cacheKey);
    }
  }

  /// Internal: Load EPG batch from API
  Future<Map<String, ShortEpg>> _loadEpgBatch(
      List<String> streamIds, String cacheKey) async {
    try {
      final result = <String, ShortEpg>{};

      // Join stream IDs for API call (or use multiple calls if API limits)
      final streamIdParam = streamIds.join(',');

      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_short_epg',
          'stream_id': streamIdParam,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
        ),
      );

      if (response.statusCode == 200 && response.data is List) {
        final items = (response.data as List);

        for (var item in items) {
          if (item is Map && item.containsKey('stream_id')) {
            final streamId = item['stream_id'].toString();
            result[streamId] = ShortEpg(
              nowPlaying: item['now_playing'] ?? item['now'],
              nextPlaying: item['next_playing'] ?? item['next'],
            );
          }
        }

        if (kDebugMode) {
          print('✅ Loaded EPG for ${result.length}/${streamIds.length} channels');
        }
      }

      return result;
    } catch (e) {
      if (kDebugMode) print('❌ Error loading EPG batch: $e');
      // Return empty map on error - EPG is optional
      return {};
    }
  }

  /// Get VOD categories
  Future<List<Category>> getVodCategories() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_vod_categories',
        },
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => Category.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error loading VOD categories: $e');
      return [];
    }
  }

  /// Search VOD movies
  Future<List<Movie>> searchMovies(String query) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'search',
          'search': query,
        },
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => Movie.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error searching movies: $e');
      return [];
    }
  }

  /// Clear EPG cache (for manual refresh)
  void clearEpgCache() {
    _epgBatchCache.clear();
    _inFlightBatches.clear();
    if (kDebugMode) print('🗑️  EPG cache cleared');
  }

  /// Get cache stats for debugging
  Map<String, dynamic> getCacheStats() {
    return {
      'epg_cache_entries': _epgBatchCache.length,
      'in_flight_batches': _inFlightBatches.length,
      'expired_entries': _epgBatchCache.values.where((e) => e.isExpired).length,
    };
  }
}

/// Short EPG for a channel (now playing + next up)
class ShortEpg {
  final String? nowPlaying;
  final String? nextPlaying;

  ShortEpg({required this.nowPlaying, required this.nextPlaying});

  factory ShortEpg.fromJson(Map<String, dynamic> json) {
    return ShortEpg(
      nowPlaying: json['now_playing'] ?? json['now'],
      nextPlaying: json['next_playing'] ?? json['next'],
    );
  }
}
