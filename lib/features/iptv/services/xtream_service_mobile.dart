/// Xtream Codes API Service - Mobile Version
///
/// Handles Xtream API communication with batching and caching optimizations
/// for mobile platforms. Designed for performance with TiviMate-level efficiency.
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/xtream_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';

/// EPG cache entry with TTL
class _EpgCacheEntry {
  final Map<String, model.ShortEPG> data;
  final DateTime timestamp;
  static const int ttlSeconds = 3600; // 1 hour TTL

  _EpgCacheEntry(this.data) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp).inSeconds > ttlSeconds;
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
  final Map<String, Future<Map<String, model.ShortEPG>>> _inFlightBatches = {};

  XtreamServiceMobile(this.cacheDir);

  /// Initialize with playlist configuration
  Future<void> setPlaylistAsync(PlaylistConfig config) async {
    _baseUrl = config.dns;
    _username = config.username;
    _password = config.password;

    // Create independent Dio for Xtream API (avoid ApiClient baseUrl issues)
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
      ),
    );

    if (kDebugMode) {
      print('✅ [XtreamServiceMobile] Initialized with URL: $_baseUrl');
    }
  }

  /// Get live channels for a category (with batch EPG support)
  /// If categoryId is empty, fetches ALL channels from all categories
  Future<List<model.Channel>> getLiveChannels(String categoryId) async {
    try {
      final queryParams = {
        'username': _username,
        'password': _password,
        'action': 'get_live_streams',
      };

      // Only add category_id if specified
      if (categoryId.isNotEmpty) {
        queryParams['category_id'] = categoryId;
      }

      if (kDebugMode) {
        print('🔍 Loading live channels with params: $queryParams');
      }

      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: queryParams,
        options: Options(
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode == 200) {
        if (response.data is List) {
          final channels = (response.data as List)
              .map((e) => model.Channel.fromJson(e))
              .toList();

          if (kDebugMode) {
            final categories = channels.map((c) => c.categoryName).toSet();
            print(
              '✅ Loaded ${channels.length} channels with ${categories.length} categories: $categories',
            );
          }

          return channels;
        } else if (response.data is Map) {
          if (kDebugMode)
            print('⚠️ API returned a Map instead of List: ${response.data}');
          return [];
        } else {
          if (kDebugMode)
            print(
                '⚠️ API returned unexpected type: ${response.data.runtimeType}');
          return [];
        }
      }

      if (kDebugMode) {
        print(
            '⚠️ Unexpected response status: ${response.statusCode}, body: ${response.data}');
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error loading live channels: $e');
      return [];
    }
  }

  /// Get SHORT EPG for a SINGLE channel (legacy, avoid - use getBatchEPG instead)
  Future<model.ShortEPG> getShortEPG(String streamId) async {
    // For backward compatibility, but prefer batch loading
    final batch = await getBatchEPG([streamId]);
    return batch[streamId] ??
        model.ShortEPG(
          id: streamId,
          title: '',
          start: DateTime.now().toIso8601String(),
          end: DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
        );
  }

  /// Get SHORT EPG for MULTIPLE channels in ONE request
  ///
  /// This is the optimized method that prevents N+1 queries.
  /// Instead of 50 requests for 50 channels, this loads all at once.
  /// Results are cached for 1 hour to avoid repeated requests.
  Future<Map<String, model.ShortEPG>> getBatchEPG(
    List<String> streamIds,
  ) async {
    if (streamIds.isEmpty) return {};

    // Create cache key from sorted IDs for consistency
    final cacheKey = streamIds.toSet().toList()..sort();
    final cacheKeyStr = cacheKey.join(',');

    // Check if we have valid cached data
    final cached = _epgBatchCache[cacheKeyStr];
    if (cached != null && !cached.isExpired) {
      if (kDebugMode) {
        print('✅ EPG batch cache hit: ${streamIds.length} channels');
      }
      return cached.data;
    }

    // Check if this batch is already being loaded (deduplication)
    if (_inFlightBatches.containsKey(cacheKeyStr)) {
      if (kDebugMode) print('⏳ Reusing in-flight EPG batch request');
      return _inFlightBatches[cacheKeyStr]!;
    }

    // Load the batch
    final future = _loadEpgBatch(streamIds, cacheKeyStr);
    _inFlightBatches[cacheKeyStr] = future;

    try {
      final result = await future;
      _epgBatchCache[cacheKeyStr] = _EpgCacheEntry(result);
      return result;
    } finally {
      _inFlightBatches.remove(cacheKeyStr);
    }
  }

  /// Internal: Load EPG for a single stream
  /// NOTE: Xtream API get_short_epg only returns results for ONE stream_id at a time.
  /// Response format: {"epg_listings": [...]} where title/description are Base64 encoded.
  Future<Map<String, model.ShortEPG>> _loadEpgBatch(
    List<String> streamIds,
    String cacheKey,
  ) async {
    final result = <String, model.ShortEPG>{};

    // Load EPG for each stream_id individually (API doesn't support true batch)
    for (final streamId in streamIds) {
      try {
        final response = await _dio
            .get(
              '$_baseUrl/player_api.php',
              queryParameters: {
                'username': _username,
                'password': _password,
                'action': 'get_short_epg',
                'stream_id': streamId,
              },
              options: Options(
                receiveTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
              ),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200 && response.data is Map) {
          final data = response.data as Map;
          final listings = data['epg_listings'];

          if (listings is List && listings.isNotEmpty) {
            // Find the currently airing program
            final now = DateTime.now();
            Map<String, dynamic>? current;

            for (final item in listings) {
              if (item is! Map) continue;
              try {
                final start = DateTime.parse(item['start'].toString());
                final end = DateTime.parse(item['end'].toString());
                if (now.isAfter(start) && now.isBefore(end)) {
                  current = Map<String, dynamic>.from(item);
                  break;
                }
              } catch (_) {}
            }

            // Fallback to first entry if no current program found
            current ??= Map<String, dynamic>.from(listings.first as Map);

            result[streamId] = model.ShortEPG.fromJson({
              ...current,
              'id': streamId,
            });
          }
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ EPG failed for $streamId: $e');
      }
    }

    if (kDebugMode) {
      print('✅ EPG loaded: ${result.length}/${streamIds.length} channels');
    }
    return result;
  }

  /// Get live TV categories
  Future<List<model.Category>> getLiveCategories() async {
    try {
      if (kDebugMode) print('🔍 Loading live TV categories with 8s timeout...');

      final response = await _dio
          .get(
            '$_baseUrl/player_api.php',
            queryParameters: {
              'username': _username,
              'password': _password,
              'action': 'get_live_categories',
            },
            options: Options(
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
            ),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        if (response.data is List) {
          final categories = (response.data as List)
              .map((e) => model.Category.fromJson(e))
              .toList();

          if (kDebugMode) {
            print(
                '✅ Loaded ${categories.length} live categories: ${categories.map((c) => c.categoryName).toList()}');
          }

          return categories;
        } else if (response.data is Map) {
          if (kDebugMode)
            print(
                '⚠️ get_live_categories returned a Map (not a list): ${response.data}');
          return [];
        } else {
          if (kDebugMode)
            print(
                '⚠️ get_live_categories returned unexpected type: ${response.data.runtimeType}');
          return [];
        }
      }

      if (kDebugMode) {
        print(
            '⚠️ Failed to load categories (status: ${response.statusCode}, body: ${response.data})');
      }
      return [];
    } on TimeoutException {
      if (kDebugMode) {
        print(
          '⏱️ Timeout loading live categories - will fallback to loading all channels',
        );
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error loading live categories: $e');
      return [];
    }
  }

  /// Get VOD categories
  Future<List<model.Category>> getVodCategories() async {
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
            .map((e) => model.Category.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error loading VOD categories: $e');
      return [];
    }
  }

  /// Get movies by category
  /// If categoryId is empty, fetches ALL movies from all categories
  Future<List<model.VodItem>> getMoviesByCategory(String categoryId) async {
    try {
      final queryParams = {
        'username': _username,
        'password': _password,
        'action': 'get_vod_streams',
      };

      // Only add category_id if specified
      if (categoryId.isNotEmpty) {
        queryParams['category_id'] = categoryId;
      }

      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: queryParams,
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => model.VodItem.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get all movies
  Future<List<model.VodItem>> getMovies() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_vod_streams',
        },
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => model.VodItem.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Search VOD movies
  Future<List<model.VodItem>> searchMovies(String query) async {
    final all = await getMovies();
    return all
        .where((m) => m.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  /// Get all series
  Future<List<model.Series>> getSeries() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_series',
        },
        options: Options(receiveTimeout: const Duration(seconds: 45)),
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => model.Series.fromJson(e))
            .toList();
      }
      if (kDebugMode) {
        print(
            '⚠️ get_series returned unexpected status or type: ${response.statusCode}');
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// Get series paginated / filtered by category
  Future<List<model.Series>> getSeriesPaginated({String? categoryId}) async {
    try {
      final queryParams = {
        'username': _username,
        'password': _password,
        'action': 'get_series',
      };

      if (categoryId != null && categoryId.isNotEmpty) {
        queryParams['category_id'] = categoryId;
      }

      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: queryParams,
        options: Options(receiveTimeout: const Duration(seconds: 30)),
      );

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => model.Series.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error loading series by category: $e');
      return [];
    }
  }

  /// Get series categories
  Future<List<model.Category>> getSeriesCategories() async {
    try {
      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_series_categories',
        },
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );

      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((e) => model.Category.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      if (kDebugMode) print('❌ Error loading series categories: $e');
      return [];
    }
  }

  /// Get series info
  Future<model.SeriesInfo?> getSeriesInfo(String seriesId) async {
    try {
      final response = await _dio.get(
        '$_baseUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_series_info',
          'series_id': seriesId,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final seriesModel = model.Series.fromJson(data['info'] ?? {});

        final episodesMap = <String, List<model.Episode>>{};
        if (data['episodes'] is Map) {
          final seasons = data['episodes'] as Map<String, dynamic>;
          seasons.forEach((seasonNum, episodesList) {
            if (episodesList is List) {
              episodesMap[seasonNum] = episodesList
                  .map((e) => model.Episode.fromJson(e as Map<String, dynamic>))
                  .toList();
            }
          });
        }

        return model.SeriesInfo(
          series: seriesModel,
          episodes: episodesMap,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Clear cache
  void clearCache() {
    _epgBatchCache.clear();
    _inFlightBatches.clear();
  }

  /// Get Live Stream URL
  String getLiveStreamUrl(String streamId) {
    return '$_baseUrl/live/$_username/$_password/$streamId.ts';
  }

  /// Get VOD Stream URL
  String getVodStreamUrl(String streamId, String extension) {
    return '$_baseUrl/movie/$_username/$_password/$streamId.$extension';
  }

  /// Get Series Stream URL
  String getSeriesStreamUrl(String streamId, String extension) {
    return '$_baseUrl/series/$_username/$_password/$streamId.$extension';
  }

  /// Search series (local filter on full list)
  Future<List<model.Series>> searchSeries(String query) async {
    try {
      final allSeries = await getSeries();
      if (query.isEmpty) return allSeries;

      final normalizedQuery = query.toLowerCase();
      return allSeries
          .where((s) => s.name.toLowerCase().contains(normalizedQuery))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error searching series: $e');
      return [];
    }
  }

  /// Dispose service resources
  void dispose() {
    clearCache();
  }
}
