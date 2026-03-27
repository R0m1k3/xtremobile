import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/playlist_config.dart';
import '../../core/models/iptv_models.dart' as model;
import '../../features/iptv/services/xtream_service_mobile.dart';

/// Mobile-specific Xtream service provider
import 'package:path_provider/path_provider.dart';

final mobileXtreamServiceProvider =
    FutureProvider.family<XtreamServiceMobile, PlaylistConfig>(
        (ref, playlist) async {
  final dir = await getApplicationDocumentsDirectory();
  final service = XtreamServiceMobile(dir.path);
  await service
      .setPlaylistAsync(playlist); // Async to resolve DNS before API calls
  return service;
});

/// Mobile-specific live channels provider
final mobileLiveChannelsProvider =
    FutureProvider.family<List<model.Channel>, PlaylistConfig>(
        (ref, playlist) async {
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  // Correction: getLiveChannels returns List<Channel>, and we now need a selected category
  // If no category is selected, we might want to load all or first category.
  // For now, let's assume it should return all channels or handle category selection elsewhere.
  return service.getLiveChannels(""); 
});

/// Mobile-specific movies provider
final mobileMoviesProvider =
    FutureProvider.family<List<model.VodItem>, PlaylistConfig>((ref, playlist) async {
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  return service.getMoviesByCategory(""); // Fetch all or default
});

/// Mobile-specific series pagination provider
final mobileSeriesProvider =
    FutureProvider.family<List<model.Series>, PlaylistConfig>((ref, playlist) async {
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  return service.getSeriesPaginated();
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

final mobileSeriesInfoByPlaylistProvider =
    FutureProvider.family<model.SeriesInfo?, SeriesInfoRequest>((ref, request) async {
  final service =
      await ref.watch(mobileXtreamServiceProvider(request.playlist).future);
  return service.getSeriesInfo(request.seriesId);
});

// UI State Provider for persistent navigation
final mobileLiveTvUiStateProvider =
    StateProvider<LiveTvUiState>((ref) => LiveTvUiState());

class LiveTvUiState {
  final String? selectedCategory;
  final bool isCategoryView;

  LiveTvUiState({this.selectedCategory, this.isCategoryView = true});

  LiveTvUiState copyWith({String? selectedCategory, bool? isCategoryView}) {
    return LiveTvUiState(
      selectedCategory: selectedCategory ?? this.selectedCategory,
      isCategoryView: isCategoryView ?? this.isCategoryView,
    );
  }
}

/// Persistent index for mobile dashboard navigation
final mobileDashboardIndexProvider = StateProvider<int>((ref) => 0);

/// Batch EPG provider
class BatchEpgRequest {
  final PlaylistConfig playlist;
  final List<String> streamIds;

  BatchEpgRequest({required this.playlist, required this.streamIds});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchEpgRequest &&
          runtimeType == other.runtimeType &&
          playlist == other.playlist &&
          streamIds.toSet().toString() == other.streamIds.toSet().toString();

  @override
  int get hashCode => playlist.hashCode ^ streamIds.toSet().toString().hashCode;
}

/// Load EPG data for multiple streams in one batch request
final mobileBatchEpgProvider =
    FutureProvider.family<Map<String, model.ShortEPG>, BatchEpgRequest>(
        (ref, request) async {
  if (request.streamIds.isEmpty) return {};

  final service =
      await ref.watch(mobileXtreamServiceProvider(request.playlist).future);
  return service.getBatchEPG(request.streamIds);
});
