import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import '../../../core/models/playlist_config.dart';
import '../../../core/models/iptv_models.dart';
import '../../../core/api/dns_resolver.dart';
import '../models/xtream_models.dart' as xm;

/// Xtream Codes API Service for Mobile (no dart:html dependency)
///
/// Handles all communication with Xtream API servers
class XtreamServiceMobile {
  late final Dio _dio;
  late final CacheOptions _cacheOptions;

  PlaylistConfig? _currentPlaylist;
  String? _resolvedIp; // Cached resolved IP for the playlist server
  String? _originalHost; // Original hostname for Host header

  // In-memory cache for pagination performance
  List<dynamic>? _cachedMoviesRaw;
  List<dynamic>? _cachedSeriesRaw;
  Map<String, String>? _cachedVodCategories;
  Map<String, String>? _cachedSeriesCategories;

  late final HiveCacheStore _cacheStore;

  XtreamServiceMobile(String cachePath) {
    _cacheStore = HiveCacheStore(cachePath);
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    // Setup caching for API responses - 24h cache for VOD content
    _cacheOptions = CacheOptions(
      store: _cacheStore,
      policy: CachePolicy.forceCache,
      maxStale: const Duration(hours: 24),
      priority: CachePriority.high,
      keyBuilder: (request) {
        // Use the Original Host header if available to generate a stable cache key
        // regardless of the resolved IP address used for the connection
        if (request.headers.containsKey('Host')) {
          final host = request.headers['Host'] as String;
          final uri = request.uri;
          // Reconstruct URI with the original hostname
          final stableUri = uri.replace(host: host);
          return stableUri.toString();
        }
        return request.uri.toString();
      },
    );

    _dio.interceptors.add(DioCacheInterceptor(options: _cacheOptions));
  }

  /// Initialize connection with a playlist - now async for DNS resolution
  Future<void> setPlaylistAsync(PlaylistConfig playlist) async {
    _currentPlaylist = playlist;

    // Extract hostname from DNS URL
    final uri = Uri.tryParse(playlist.dns);
    if (uri != null && uri.host.isNotEmpty) {
      _originalHost = uri.host;

      // Proactively resolve DNS
      print('XtreamServiceMobile: Pre-resolving ${uri.host}');
      _resolvedIp = await DnsResolver.resolve(uri.host);

      if (_resolvedIp != null) {
        print('XtreamServiceMobile: Will use IP $_resolvedIp for ${uri.host}');
      } else {
        print(
          'XtreamServiceMobile: DNS resolution failed, will use hostname directly',
        );
      }
    }
  }

  /// Legacy sync method - calls async internally
  void setPlaylist(PlaylistConfig playlist) {
    _currentPlaylist = playlist;
    // Trigger async resolution in background
    final uri = Uri.tryParse(playlist.dns);
    if (uri != null && uri.host.isNotEmpty) {
      _originalHost = uri.host;
      DnsResolver.resolve(uri.host).then((ip) {
        _resolvedIp = ip;
      });
    }
  }

  /// Get the API base URL, using resolved IP if available
  String get _effectiveApiBaseUrl {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    if (_resolvedIp != null && _originalHost != null) {
      // Replace hostname with IP in the URL
      final originalUrl = _currentPlaylist!.apiBaseUrl;
      return originalUrl.replaceFirst(_originalHost!, _resolvedIp!);
    }
    return _currentPlaylist!.apiBaseUrl;
  }

  /// Get effective DNS base, using resolved IP if available
  String get _effectiveDnsBase {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    if (_resolvedIp != null && _originalHost != null) {
      return _currentPlaylist!.dns.replaceFirst(_originalHost!, _resolvedIp!);
    }
    return _currentPlaylist!.dns;
  }

  /// Get request options with Host header if using IP
  Options _getOptions() {
    final opts = Options(extra: _cacheOptions.toExtra());
    if (_resolvedIp != null && _originalHost != null) {
      opts.headers = {'Host': _originalHost!};
    }
    return opts;
  }

  PlaylistConfig? get currentPlaylist => _currentPlaylist;

  /// Generate direct stream URL for live TV (MPEG-TS format for maximum compatibility)
  String getLiveStreamUrl(String streamId) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    // Use .ts format (MPEG-TS) for better compatibility with more providers
    return '$_effectiveDnsBase/live/${_currentPlaylist!.username}/${_currentPlaylist!.password}/$streamId.ts';
  }

  /// Generate stream URL for VOD (movies)
  String getVodStreamUrl(String streamId, String containerExtension) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    return '$_effectiveDnsBase/movie/${_currentPlaylist!.username}/${_currentPlaylist!.password}/$streamId.$containerExtension';
  }

  /// Generate stream URL for series episodes
  String getSeriesStreamUrl(String streamId, String containerExtension) {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    return '$_effectiveDnsBase/series/${_currentPlaylist!.username}/${_currentPlaylist!.password}/$streamId.$containerExtension';
  }

  /// Authenticate and get server info
  Future<Map<String, dynamic>> authenticate() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
        },
        options: _getOptions(),
      );

      if (response.data is! Map<String, dynamic>) {
        if (response.data is String) {
          throw Exception('Auth Error: ${response.data}');
        }
        throw Exception('Invalid auth response format');
      }
      return response.data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Authentication failed: $e');
    }
  }

  /// Load categories mapping (category_id -> category_name)
  Future<Map<String, String>> _getLiveCategories() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_live_categories',
        },
        options: _getOptions(),
      );

      if (response.data is! List) {
        if (response.data is String) {
          throw Exception('Category Error: ${response.data}');
        }
        return {};
      }
      final List<dynamic> categories = response.data as List<dynamic>;
      final Map<String, String> categoryMap = {};

      for (final cat in categories) {
        final catData = cat as Map<String, dynamic>;
        final id = catData['category_id']?.toString() ?? '';
        final name = catData['category_name']?.toString() ?? 'Unknown';
        if (id.isNotEmpty) {
          categoryMap[id] = name;
        }
      }

      return categoryMap;
    } catch (e) {
      return {}; // Return empty map on error, channels will be "Uncategorized"
    }
  }

  /// Get all live TV channels grouped by category
  Future<Map<String, List<Channel>>> getLiveChannels() async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // First, load categories to get the mapping
      final categoryMap = await _getLiveCategories();

      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_live_streams',
        },
        options: _getOptions(),
      );

      if (response.data is! List) {
        if (response.data is String) {
          throw Exception('Live TV Error: ${response.data}');
        }
        return {};
      }
      final List<dynamic> streams = response.data as List<dynamic>;
      final Map<String, List<Channel>> groupedChannels = {};

      for (final streamData in streams) {
        try {
          final data = streamData as Map<String, dynamic>;
          // Get category name from our mapping using category_id
          final categoryId = data['category_id']?.toString() ?? '';
          final categoryName = categoryMap[categoryId] ?? 'Uncategorized';

          // Inject category_name into data before parsing
          data['category_name'] = categoryName;

          final channel = Channel.fromJson(data);

          if (!groupedChannels.containsKey(categoryName)) {
            groupedChannels[categoryName] = [];
          }
          groupedChannels[categoryName]!.add(channel);
        } catch (e) {
          // Skip malformed channel
          continue;
        }
      }

      return groupedChannels;
    } catch (e) {
      throw Exception('Failed to fetch live channels: $e');
    }
  }

  /// Load VOD categories mapping
  Future<Map<String, String>> getVodCategories() async {
    if (_currentPlaylist == null) return {};

    try {
      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_vod_categories',
        },
        options: _getOptions(),
      );

      if (response.data is! List) return {};
      final List<dynamic> categories = response.data as List<dynamic>;
      final Map<String, String> categoryMap = {};

      for (final cat in categories) {
        final catData = cat as Map<String, dynamic>;
        final id = catData['category_id']?.toString() ?? '';
        final name = catData['category_name']?.toString() ?? 'Unknown';
        if (id.isNotEmpty) categoryMap[id] = name;
      }

      return categoryMap;
    } catch (e) {
      return {};
    }
  }

  /// Load Series categories mapping
  Future<Map<String, String>> _getSeriesCategories() async {
    if (_currentPlaylist == null) return {};

    try {
      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_series_categories',
        },
        options: _getOptions(),
      );

      if (response.data is! List) return {};
      final List<dynamic> categories = response.data as List<dynamic>;
      final Map<String, String> categoryMap = {};

      for (final cat in categories) {
        final catData = cat as Map<String, dynamic>;
        final id = catData['category_id']?.toString() ?? '';
        final name = catData['category_name']?.toString() ?? 'Unknown';
        if (id.isNotEmpty) categoryMap[id] = name;
      }

      return categoryMap;
    } catch (e) {
      return {};
    }
  }

  /// Get movies with pagination support (uses in-memory cache for performance)
  Future<List<xm.Movie>> getMoviesPaginated({
    int offset = 0,
    int limit = 100,
  }) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // Load from cache or fetch from API
      if (_cachedMoviesRaw == null) {
        // First load: fetch from API and cache
        _cachedVodCategories ??= await getVodCategories();

        final response = await _dio.get(
          _effectiveApiBaseUrl,
          queryParameters: {
            'username': _currentPlaylist!.username,
            'password': _currentPlaylist!.password,
            'action': 'get_vod_streams',
          },
          options: _getOptions(),
        );

        if (response.data is! List) {
          if (response.data is String) {
            throw Exception('VOD Error: ${response.data}');
          }
          _cachedMoviesRaw = [];
        } else {
          _cachedMoviesRaw = response.data as List<dynamic>;
        }
      }

      final allMovies = _cachedMoviesRaw!;
      final categoryMap = _cachedVodCategories!;

      // Apply pagination
      final endIndex = (offset + limit) > allMovies.length
          ? allMovies.length
          : offset + limit;
      if (offset >= allMovies.length) return [];

      final paginatedMovies = allMovies.sublist(offset, endIndex);

      final List<xm.Movie> movies = [];
      for (final movieData in paginatedMovies) {
        try {
          final data =
              Map<String, dynamic>.from(movieData as Map<String, dynamic>);
          final categoryId = data['category_id']?.toString() ?? '';
          data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
          movies.add(xm.Movie.fromJson(data));
        } catch (e) {
          continue;
        }
      }
      return movies;
    } catch (e) {
      throw Exception('Failed to fetch movies: $e');
    }
  }

  /// Get movies by category (Fast, optimized for large libraries)
  Future<List<xm.Movie>> getMoviesByCategory(String categoryId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final categoryMap = await getVodCategories();
      final categoryName = categoryMap[categoryId] ?? 'Unknown';

      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_vod_streams',
          'category_id': categoryId,
        },
        options: _getOptions(),
      );

      if (response.data is! List) return [];
      final List<dynamic> moviesRaw = response.data as List<dynamic>;

      final List<xm.Movie> movies = [];
      for (final movieData in moviesRaw) {
        try {
          final data =
              Map<String, dynamic>.from(movieData as Map<String, dynamic>);
          data['category_name'] = categoryName;
          movies.add(xm.Movie.fromJson(data));
        } catch (e) {
          continue;
        }
      }
      return movies;
    } catch (e) {
      // Return empty list instead of throwing to prevent UI crash
      return [];
    }
  }

  /// Search movies in the entire catalogue
  Future<List<xm.Movie>> searchMovies(String query) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    if (query.isEmpty) return [];

    try {
      // Ensure data is loaded in cache
      if (_cachedMoviesRaw == null) {
        await getMoviesPaginated(limit: 1);
      }

      final allMovies = _cachedMoviesRaw ?? [];
      final categoryMap = _cachedVodCategories ?? await getVodCategories();

      final queryLower = query.toLowerCase();

      // Filter by search query (Local Cache)
      final List<xm.Movie> results = [];

      // Efficient filtering: check name matches, limited to 100 results
      final matches = allMovies.where((m) {
        final name = (m['name']?.toString() ?? '').toLowerCase();
        return name.contains(queryLower);
      }).take(100);

      for (final movieData in matches) {
        try {
          final data =
              Map<String, dynamic>.from(movieData as Map<String, dynamic>);
          final categoryId = data['category_id']?.toString() ?? '';
          data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
          results.add(xm.Movie.fromJson(data));
        } catch (e) {
          continue;
        }
      }
      return results;
    } catch (e) {
      debugPrint('Search error: $e');
      return [];
    }
  }

  /// Get series with pagination support (uses in-memory cache for performance)
  Future<List<xm.Series>> getSeriesPaginated({
    int offset = 0,
    int limit = 100,
  }) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      // Load from cache or fetch from API
      if (_cachedSeriesRaw == null) {
        // First load: fetch from API and cache
        _cachedSeriesCategories ??= await _getSeriesCategories();

        final response = await _dio.get(
          _effectiveApiBaseUrl,
          queryParameters: {
            'username': _currentPlaylist!.username,
            'password': _currentPlaylist!.password,
            'action': 'get_series',
          },
          options: _getOptions(),
        );

        if (response.data is! List) {
          if (response.data is String) {
            throw Exception('Series Error: ${response.data}');
          }
          _cachedSeriesRaw = [];
        } else {
          _cachedSeriesRaw = response.data as List<dynamic>;
        }
      }

      final allSeries = _cachedSeriesRaw!;
      final categoryMap = _cachedSeriesCategories!;

      // Apply pagination
      final endIndex = (offset + limit) > allSeries.length
          ? allSeries.length
          : offset + limit;
      if (offset >= allSeries.length) return [];

      final paginatedSeries = allSeries.sublist(offset, endIndex);

      final List<xm.Series> seriesList = [];
      for (final seriesData in paginatedSeries) {
        try {
          final data =
              Map<String, dynamic>.from(seriesData as Map<String, dynamic>);
          final categoryId = data['category_id']?.toString() ?? '';
          data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
          seriesList.add(xm.Series.fromJson(data));
        } catch (e) {
          continue;
        }
      }
      return seriesList;
    } catch (e) {
      throw Exception('Failed to fetch series: $e');
    }
  }

  /// Search series in the entire catalogue
  Future<List<xm.Series>> searchSeries(String query) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');
    if (query.isEmpty) return [];

    try {
      // Ensure data is loaded in cache
      if (_cachedSeriesRaw == null) {
        await getSeriesPaginated(limit: 1);
      }

      final allSeries = _cachedSeriesRaw ?? [];
      final categoryMap =
          _cachedSeriesCategories ?? await _getSeriesCategories();

      final queryLower = query.toLowerCase();

      // Filter by search query (Local Cache)
      final List<xm.Series> results = [];

      final matches = allSeries.where((s) {
        final name = (s['name']?.toString() ?? '').toLowerCase();
        return name.contains(queryLower);
      }).take(100);

      for (final seriesData in matches) {
        try {
          final data =
              Map<String, dynamic>.from(seriesData as Map<String, dynamic>);
          final categoryId = data['category_id']?.toString() ?? '';
          data['category_name'] = categoryMap[categoryId] ?? 'Uncategorized';
          results.add(xm.Series.fromJson(data));
        } catch (e) {
          continue;
        }
      }
      return results;
    } catch (e) {
      debugPrint('Search series error: $e');
      return [];
    }
  }

  /// Get series info with seasons and episodes
  Future<xm.SeriesInfo> getSeriesInfo(String seriesId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_series_info',
          'series_id': seriesId,
        },
        options: _getOptions(),
      );

      if (response.data is! Map<String, dynamic>) {
        throw Exception('Invalid response format for Series Info');
      }
      return xm.SeriesInfo.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      throw Exception('Failed to fetch series info: $e');
    }
  }

  /// Get short EPG for a specific stream
  Future<List<EpgEntry>> getShortEpg(String streamId) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_short_epg',
          'stream_id': streamId,
        },
        options: Options(
          headers: _resolvedIp != null && _originalHost != null
              ? {'Host': _originalHost!}
              : null,
          extra: CacheOptions(
            store: _cacheOptions.store,
            policy: CachePolicy.request,
            maxStale: const Duration(minutes: 5), // EPG changes frequently
          ).toExtra(),
        ),
      );

      if (response.data == null || response.data['epg_listings'] == null) {
        return [];
      }

      if (response.data['epg_listings'] is! List) return [];
      final List<dynamic> epgData =
          response.data['epg_listings'] as List<dynamic>;
      return epgData
          .map((entry) => EpgEntry.fromJson(entry as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // EPG is optional, don't throw on failure
      return [];
    }
  }

  /// Get short EPG as ShortEPG object (for EPGWidget)
  /// Caches results for 12 hours by default
  Future<xm.ShortEPG> getShortEPG(
    String streamId, {
    bool forceRefresh = false,
  }) async {
    if (_currentPlaylist == null) throw Exception('No playlist configured');

    try {
      final response = await _dio.get(
        _effectiveApiBaseUrl,
        queryParameters: {
          'username': _currentPlaylist!.username,
          'password': _currentPlaylist!.password,
          'action': 'get_short_epg',
          'stream_id': streamId,
        },
        options: Options(
          headers: _resolvedIp != null && _originalHost != null
              ? {'Host': _originalHost!}
              : null,
          extra: CacheOptions(
            store: _cacheOptions.store,
            policy: forceRefresh ? CachePolicy.refresh : CachePolicy.request,
            maxStale: const Duration(hours: 12), // Cache for 12h as requested
          ).toExtra(),
        ),
      );

      if (response.data == null) {
        return const xm.ShortEPG();
      }

      if (response.data is! Map<String, dynamic>) {
        return const xm.ShortEPG();
      }
      return xm.ShortEPG.fromJson(response.data as Map<String, dynamic>);
    } catch (e) {
      // EPG is optional, don't throw on failure
      return const xm.ShortEPG();
    }
  }

  /// Clear in-memory cache (call on refresh)
  void clearCache() {
    _cachedMoviesRaw = null;
    _cachedSeriesRaw = null;
    _cachedVodCategories = null;
    _cachedSeriesCategories = null;
  }

  /// Force refresh all cached data (clears both memory and Hive HTTP cache)
  /// This will cause the next API calls to fetch fresh data from the server
  Future<void> forceRefreshCache() async {
    // Clear in-memory cache
    clearCache();

    // Clear HTTP cache (Hive store)
    try {
      await _cacheStore.clean();
      print('XtreamServiceMobile: Cache cleared successfully');
    } catch (e) {
      print('XtreamServiceMobile: Error clearing cache: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    clearCache();
    _dio.close();
  }
}
