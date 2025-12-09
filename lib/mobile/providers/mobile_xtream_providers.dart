import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/playlist_config.dart';
import '../../core/models/iptv_models.dart' show Channel;
import '../../features/iptv/services/xtream_service_mobile.dart';
import '../../features/iptv/models/xtream_models.dart';

export '../../features/iptv/models/xtream_models.dart';

/// Mobile-specific Xtream service provider (no dart:html dependency)
import 'package:path_provider/path_provider.dart';

/// Mobile-specific Xtream service provider (no dart:html dependency)
final mobileXtreamServiceProvider = FutureProvider.family<XtreamServiceMobile, PlaylistConfig>((ref, playlist) async {
  final dir = await getApplicationDocumentsDirectory();
  final service = XtreamServiceMobile(dir.path);
  service.setPlaylist(playlist);
  return service;
});

/// Mobile-specific live channels provider
final mobileLiveChannelsProvider = FutureProvider.family<Map<String, List<Channel>>, PlaylistConfig>((ref, playlist) async {
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  return service.getLiveChannels();
});

/// Mobile-specific movies pagination provider
final mobileMoviesProvider = FutureProvider.family<List<Movie>, PlaylistConfig>((ref, playlist) async {
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  return service.getMoviesPaginated(offset: 0, limit: 100);
});

/// Mobile-specific series pagination provider
final mobileSeriesProvider = FutureProvider.family<List<Series>, PlaylistConfig>((ref, playlist) async {
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  return service.getSeriesPaginated(offset: 0, limit: 100);
});

/// Mobile-specific series info provider
final mobileSeriesInfoProvider = FutureProvider.family<SeriesInfo, String>((ref, seriesId) {
  throw UnimplementedError('Use mobileSeriesInfoByPlaylistProvider instead');
});

/// Series info with playlist context
class SeriesInfoRequest {
  final PlaylistConfig playlist;
  final String seriesId;
  
  SeriesInfoRequest({required this.playlist, required this.seriesId});
  
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeriesInfoRequest &&
          runtimeType == other.runtimeType &&
          playlist == other.playlist &&
          seriesId == other.seriesId;
  
  @override
  int get hashCode => playlist.hashCode ^ seriesId.hashCode;
}

final mobileSeriesInfoByPlaylistProvider = FutureProvider.family<SeriesInfo, SeriesInfoRequest>((ref, request) async {
  final service = await ref.watch(mobileXtreamServiceProvider(request.playlist).future);
  return service.getSeriesInfo(request.seriesId);
});
