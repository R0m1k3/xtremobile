import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Mobile-specific settings (stored locally in Hive)
/// Simplified version without server API dependencies
class MobileSettings {
  final List<String> liveTvKeywords;
  final List<String> moviesKeywords;
  final List<String> seriesKeywords;
  final bool showClock;
  final bool showDebugStats;
  final String decoderMode; // 'auto', 'mediacodec' (HW), 'no' (SW)
  final String playerEngine; // 'ultra' (MPV), 'lite' (ExoPlayer)
  final int bufferDuration; // seconds, 0 = auto

  const MobileSettings({
    this.liveTvKeywords = const [],
    this.moviesKeywords = const [],
    this.seriesKeywords = const [],
    this.showClock = false,
    this.showDebugStats = false,
    this.decoderMode = 'auto',
    this.playerEngine = 'ultra',
    this.bufferDuration = 0,
  });

  MobileSettings copyWith({
    List<String>? liveTvKeywords,
    List<String>? moviesKeywords,
    List<String>? seriesKeywords,
    bool? showClock,
    bool? showDebugStats,
    String? decoderMode,
    String? playerEngine,
    int? bufferDuration,
  }) {
    return MobileSettings(
      liveTvKeywords: liveTvKeywords ?? this.liveTvKeywords,
      moviesKeywords: moviesKeywords ?? this.moviesKeywords,
      seriesKeywords: seriesKeywords ?? this.seriesKeywords,
      showClock: showClock ?? this.showClock,
      showDebugStats: showDebugStats ?? this.showDebugStats,
      decoderMode: decoderMode ?? this.decoderMode,
      playerEngine: playerEngine ?? this.playerEngine,
      bufferDuration: bufferDuration ?? this.bufferDuration,
    );
  }

  /// Check if category matches Live TV filter
  bool matchesLiveTvFilter(String? category) {
    if (liveTvKeywords.isEmpty) return true;
    if (category == null) return true;
    final lowerCategory = category.toLowerCase();
    return liveTvKeywords.any(
      (keyword) => lowerCategory.contains(keyword.toLowerCase()),
    );
  }

  /// Check if category matches Movies filter
  bool matchesMoviesFilter(String? category) {
    if (moviesKeywords.isEmpty) return true;
    if (category == null) return true;
    final lowerCategory = category.toLowerCase();
    return moviesKeywords.any(
      (keyword) => lowerCategory.contains(keyword.toLowerCase()),
    );
  }

  /// Check if category matches Series filter
  bool matchesSeriesFilter(String? category) {
    if (seriesKeywords.isEmpty) return true;
    if (category == null) return true;
    final lowerCategory = category.toLowerCase();
    return seriesKeywords.any(
      (keyword) => lowerCategory.contains(keyword.toLowerCase()),
    );
  }
}

class MobileSettingsNotifier extends StateNotifier<MobileSettings> {
  static const String _boxName = 'mobile_settings';
  Box? _box;

  MobileSettingsNotifier() : super(const MobileSettings()) {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(_boxName);

    final liveTv =
        _box?.get('liveTvKeywords', defaultValue: <String>[]) as List?;
    final movies =
        _box?.get('moviesKeywords', defaultValue: <String>[]) as List?;
    final series =
        _box?.get('seriesKeywords', defaultValue: <String>[]) as List?;
    final showClock = _box?.get('showClock', defaultValue: false) as bool?;
    final showDebugStats =
        _box?.get('showDebugStats', defaultValue: false) as bool?;
    final decoderMode =
        _box?.get('decoderMode', defaultValue: 'auto') as String?;
    final playerEngine =
        _box?.get('playerEngine', defaultValue: 'ultra') as String?;
    final buffer = _box?.get('bufferDuration', defaultValue: 0) as int?;

    state = MobileSettings(
      liveTvKeywords: liveTv?.cast<String>() ?? [],
      moviesKeywords: movies?.cast<String>() ?? [],
      seriesKeywords: series?.cast<String>() ?? [],
      showClock: showClock ?? false,
      showDebugStats: showDebugStats ?? false,
      decoderMode: decoderMode ?? 'auto',
      playerEngine: playerEngine ?? 'ultra',
      bufferDuration: buffer ?? 0,
    );
  }

  void setLiveTvKeywords(List<String> keywords) {
    state = state.copyWith(liveTvKeywords: keywords);
    _box?.put('liveTvKeywords', keywords);
  }

  void setMoviesKeywords(List<String> keywords) {
    state = state.copyWith(moviesKeywords: keywords);
    _box?.put('moviesKeywords', keywords);
  }

  void setSeriesKeywords(List<String> keywords) {
    state = state.copyWith(seriesKeywords: keywords);
    _box?.put('seriesKeywords', keywords);
  }

  void toggleShowClock(bool value) {
    state = state.copyWith(showClock: value);
    _box?.put('showClock', value);
  }

  void toggleShowDebugStats(bool value) {
    state = state.copyWith(showDebugStats: value);
    _box?.put('showDebugStats', value);
  }

  void setDecoderMode(String mode) {
    state = state.copyWith(decoderMode: mode);
    _box?.put('decoderMode', mode);
  }

  void setPlayerEngine(String engine) {
    state = state.copyWith(playerEngine: engine);
    _box?.put('playerEngine', engine);
  }

  void setBufferDuration(int seconds) {
    state = state.copyWith(bufferDuration: seconds);
    _box?.put('bufferDuration', seconds);
  }
}

final mobileSettingsProvider =
    StateNotifierProvider<MobileSettingsNotifier, MobileSettings>((ref) {
  return MobileSettingsNotifier();
});

/// Watch history for mobile (stored locally)
class MobileWatchHistory {
  final Set<String> watchedMovies;
  final Set<String> watchedEpisodes;
  final Map<String, int> resumePositions; // streamId -> position in seconds

  const MobileWatchHistory({
    this.watchedMovies = const {},
    this.watchedEpisodes = const {},
    this.resumePositions = const {},
  });

  MobileWatchHistory copyWith({
    Set<String>? watchedMovies,
    Set<String>? watchedEpisodes,
    Map<String, int>? resumePositions,
  }) {
    return MobileWatchHistory(
      watchedMovies: watchedMovies ?? this.watchedMovies,
      watchedEpisodes: watchedEpisodes ?? this.watchedEpisodes,
      resumePositions: resumePositions ?? this.resumePositions,
    );
  }

  bool isMovieWatched(String streamId) => watchedMovies.contains(streamId);
  bool isEpisodeWatched(String episodeKey) =>
      watchedEpisodes.contains(episodeKey);

  /// Get resume position in seconds (0 if none saved)
  int getResumePosition(String contentId) => resumePositions[contentId] ?? 0;

  static String episodeKey(dynamic seriesId, int season, int episodeNum) {
    return '$seriesId:$season:$episodeNum';
  }
}

class MobileWatchHistoryNotifier extends StateNotifier<MobileWatchHistory> {
  static const String _boxName = 'mobile_watch_history';
  Box? _box;

  MobileWatchHistoryNotifier() : super(const MobileWatchHistory()) {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(_boxName);

    final movies =
        _box?.get('watchedMovies', defaultValue: <String>[]) as List?;
    final episodes =
        _box?.get('watchedEpisodes', defaultValue: <String>[]) as List?;
    final positionsRaw = _box?.get('resumePositions');

    // Safe conversion for resumePositions map
    Map<String, int> positions = {};
    if (positionsRaw != null && positionsRaw is Map) {
      positionsRaw.forEach((key, value) {
        if (key is String && value is int) {
          positions[key] = value;
        } else if (key is String && value is num) {
          positions[key] = value.toInt();
        }
      });
    }

    state = MobileWatchHistory(
      watchedMovies: movies?.cast<String>().toSet() ?? {},
      watchedEpisodes: episodes?.cast<String>().toSet() ?? {},
      resumePositions: positions,
    );
  }

  void markMovieWatched(String streamId) {
    final updated = {...state.watchedMovies, streamId};
    // Clear resume position when marked as fully watched
    final positions = {...state.resumePositions};
    positions.remove(streamId);
    state = state.copyWith(watchedMovies: updated, resumePositions: positions);
    _box?.put('watchedMovies', updated.toList());
    _box?.put('resumePositions', positions);
  }

  void toggleMovieWatched(String streamId) {
    final movies = {...state.watchedMovies};
    if (movies.contains(streamId)) {
      movies.remove(streamId);
    } else {
      movies.add(streamId);
    }
    state = state.copyWith(watchedMovies: movies);
    _box?.put('watchedMovies', movies.toList());
  }

  void markEpisodeWatched(String episodeKey) {
    final updated = {...state.watchedEpisodes, episodeKey};
    // Clear resume position when marked as fully watched
    final positions = {...state.resumePositions};
    positions.remove(episodeKey);
    state =
        state.copyWith(watchedEpisodes: updated, resumePositions: positions);
    _box?.put('watchedEpisodes', updated.toList());
    _box?.put('resumePositions', positions);
  }

  /// Save resume position for movie or episode
  void saveResumePosition(String contentId, int positionSeconds) {
    // Only save if position is meaningful (> 30 seconds)
    if (positionSeconds < 30) {
      debugPrint(
          '[WatchHistory] Position too short ($positionSeconds), skipping save');
      return;
    }

    debugPrint(
        '[WatchHistory] Saving position for $contentId: ${positionSeconds}s');
    final positions = {...state.resumePositions, contentId: positionSeconds};
    state = state.copyWith(resumePositions: positions);
    _box?.put('resumePositions', Map<String, int>.from(positions));
  }

  /// Clear resume position (when content finished or user wants to restart)
  void clearResumePosition(String contentId) {
    final positions = {...state.resumePositions};
    positions.remove(contentId);
    state = state.copyWith(resumePositions: positions);
    _box?.put('resumePositions', positions);
  }
}

final mobileWatchHistoryProvider =
    StateNotifierProvider<MobileWatchHistoryNotifier, MobileWatchHistory>(
        (ref) {
  return MobileWatchHistoryNotifier();
});

/// Favorites for mobile (stored locally)
class MobileFavoritesNotifier extends StateNotifier<Set<String>> {
  static const String _boxName = 'mobile_favorites';
  Box? _box;

  MobileFavoritesNotifier() : super({}) {
    _init();
  }

  Future<void> _init() async {
    _box = await Hive.openBox(_boxName);
    final favorites = _box?.get('favorites', defaultValue: <String>[]) as List?;
    state = favorites?.cast<String>().toSet() ?? {};
  }

  void toggle(String streamId) {
    final updated = {...state};
    if (updated.contains(streamId)) {
      updated.remove(streamId);
    } else {
      updated.add(streamId);
    }
    state = updated;
    _box?.put('favorites', updated.toList());
  }

  bool isFavorite(String streamId) => state.contains(streamId);
}

final mobileFavoritesProvider =
    StateNotifierProvider<MobileFavoritesNotifier, Set<String>>((ref) {
  return MobileFavoritesNotifier();
});
