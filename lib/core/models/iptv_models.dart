import 'dart:convert';

enum StreamType { live, vod, series }

/// Channel model for Live TV
class Channel {
  final String streamId;
  final String num;
  final String name;
  final String streamType;
  final String streamIcon;
  final String epgChannelId;
  final String categoryId;
  final String categoryName;

  const Channel({
    required this.streamId,
    required this.num,
    required this.name,
    required this.streamType,
    this.streamIcon = '',
    this.epgChannelId = '',
    required this.categoryId,
    required this.categoryName,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      streamId: json['stream_id']?.toString() ?? '',
      num: json['num']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      streamType: json['stream_type']?.toString() ?? '',
      streamIcon: json['stream_icon']?.toString() ?? '',
      epgChannelId: json['epg_channel_id']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'num': num,
      'name': name,
      'stream_type': streamType,
      'stream_icon': streamIcon,
      'epg_channel_id': epgChannelId,
      'category_id': categoryId,
      'category_name': categoryName,
    };
  }
}

/// VOD (Video on Demand) model for Movies
class VodItem {
  final String streamId;
  final String name;
  final String streamIcon;
  final String rating;
  final String categoryId;
  final String categoryName;
  final String containerExtension;

  const VodItem({
    required this.streamId,
    required this.name,
    this.streamIcon = '',
    this.rating = '',
    required this.categoryId,
    required this.categoryName,
    this.containerExtension = 'mp4',
  });

  factory VodItem.fromJson(Map<String, dynamic> json) {
    return VodItem(
      streamId: json['stream_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      streamIcon: json['stream_icon']?.toString() ?? '',
      rating: json['rating']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stream_id': streamId,
      'name': name,
      'stream_icon': streamIcon,
      'rating': rating,
      'category_id': categoryId,
      'category_name': categoryName,
      'container_extension': containerExtension,
    };
  }
}

/// Series model
class Series {
  final String seriesId;
  final String name;
  final String cover;
  final String plot;
  final String categoryId;
  final String categoryName;
  final String rating;

  const Series({
    required this.seriesId,
    required this.name,
    this.cover = '',
    this.plot = '',
    required this.categoryId,
    required this.categoryName,
    this.rating = '0',
  });

  factory Series.fromJson(Map<String, dynamic> json) {
    return Series(
      seriesId: json['series_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      plot: json['plot']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
      rating: json['rating']?.toString() ?? '0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'series_id': seriesId,
      'name': name,
      'cover': cover,
      'plot': plot,
      'category_id': categoryId,
      'category_name': categoryName,
      'rating': rating,
    };
  }

  /// UI Compatibility getters
  String get streamId => seriesId;
  String get coverUrl => cover;
  String get title => name;
}

/// EPG (Electronic Program Guide) entry
class EpgEntry {
  final String id;
  final String epgId;
  final String title;
  final String lang;
  final String start;
  final String end;
  final String description;
  final String channelId;

  const EpgEntry({
    required this.id,
    required this.epgId,
    required this.title,
    this.lang = '',
    required this.start,
    required this.end,
    this.description = '',
    required this.channelId,
  });

  factory EpgEntry.fromJson(Map<String, dynamic> json) {
    return EpgEntry(
      id: json['id']?.toString() ?? '',
      epgId: json['epg_id']?.toString() ?? '',
      title: _decodeBase64(json['title']?.toString()),
      lang: json['lang']?.toString() ?? '',
      start: json['start']?.toString() ?? '',
      end: json['end']?.toString() ?? '',
      description: _decodeBase64(json['description']?.toString()),
      channelId: json['channel_id']?.toString() ?? '',
    );
  }

  static String _decodeBase64(String? text) {
    if (text == null || text.isEmpty) return '';
    try {
      final bytes = base64Decode(text);
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return text;
    }
  }

  /// Calculate progress percentage for current program
  double getProgress() {
    try {
      final startTime = DateTime.parse(start);
      final endTime = DateTime.parse(end);
      final now = DateTime.now();

      if (now.isBefore(startTime)) return 0.0;
      if (now.isAfter(endTime)) return 1.0;

      final totalDuration = endTime.difference(startTime).inSeconds;
      final elapsed = now.difference(startTime).inSeconds;

      if (totalDuration == 0) return 0.0;
      return elapsed / totalDuration;
    } catch (e) {
      return 0.0;
    }
  }
}

/// Category model
class Category {
  final String categoryId;
  final String categoryName;
  final int parentId;

  const Category({
    required this.categoryId,
    required this.categoryName,
    this.parentId = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      categoryId: json['category_id']?.toString() ?? '',
      categoryName: json['category_name']?.toString() ?? '',
      parentId: int.tryParse(json['parent_id']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category_id': categoryId,
      'category_name': categoryName,
      'parent_id': parentId,
    };
  }
}

/// Series Episode model
class Episode {
  final String id;
  final String title;
  final String containerExtension;
  final String season;
  final int episodeNum;
  final int duration;

  const Episode({
    required this.id,
    required this.title,
    this.containerExtension = 'mp4',
    this.season = '1',
    this.episodeNum = 1,
    this.duration = 0,
  });

  /// UI Compatibility getters
  String get streamId => id;
  int? get durationSecs => duration;
  int get seasonNum => int.tryParse(season) ?? 1;

  factory Episode.fromJson(Map<String, dynamic> json) {
    return Episode(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      containerExtension: json['container_extension']?.toString() ?? 'mp4',
      season: json['season']?.toString() ?? '1',
      episodeNum: int.tryParse(json['episode_num']?.toString() ?? '1') ?? 1,
      duration: int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'container_extension': containerExtension,
      'season': season,
      'episode_num': episodeNum,
      'duration': duration,
    };
  }
}

/// Detailed Series Info
class SeriesInfo {
  final Series series;
  final Map<String, List<Episode>> episodes;

  const SeriesInfo({
    required this.series,
    required this.episodes,
  });

  /// UI Compatibility getters
  String? get coverUrl => series.cover;
  String get title => series.name;
  String? get rating => series.rating;
  String? get plot => series.plot;
}

/// Short EPG model
class ShortEPG {
  final String id;
  final String title;
  final String start;
  final String end;
  final String description;

  const ShortEPG({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.description = '',
  });

  factory ShortEPG.fromJson(Map<String, dynamic> json) {
    return ShortEPG(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      start: json['start']?.toString() ?? '',
      end: json['end']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
    );
  }

  /// Get progress percentage (compatibility with UI expectations)
  double get progress {
    try {
      final startTime = DateTime.parse(start);
      final endTime = DateTime.parse(end);
      final now = DateTime.now();
      if (now.isBefore(startTime)) return 0.0;
      if (now.isAfter(endTime)) return 1.0;
      final total = endTime.difference(startTime).inSeconds;
      final elapsed = now.difference(startTime).inSeconds;
      if (total == 0) return 0.0;
      return elapsed / total;
    } catch (_) {
      return 0.0;
    }
  }

  /// Get current program title
  String get nowPlaying => title;

  /// Get next program info (mocked or from data if available)
  String get nextPlaying => "Next Program";
}
