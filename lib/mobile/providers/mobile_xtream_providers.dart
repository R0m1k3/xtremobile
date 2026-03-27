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

/// Mobile-specific live categories provider (for Live TV category grid)
final mobileLiveCategoriesProvider =
    FutureProvider.family<List<model.Category>, PlaylistConfig>(
        (ref, playlist) async {
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  return service.getLiveCategories();
});

/// Mobile-specific live channels provider (loads channels for a specific category)
final mobileLiveChannelsByCategoryProvider = FutureProvider.family<
    List<model.Channel>,
    (PlaylistConfig, String)>((ref, params) async {
  final (playlist, categoryId) = params;
  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);
  return service.getLiveChannels(categoryId);
});

/// Load ALL live channels efficiently
/// Strategy: Load categories, then load channels in SMALL BATCHES (5 at a time)
/// This balances speed with robustness - not too slow, not too many parallel requests
final mobileLiveChannelsProvider =
    FutureProvider.family<List<model.Channel>, PlaylistConfig>(
        (ref, playlist) async {
  print('📺 [LiveTV] Starting to load ALL channels...');

  final service = await ref.watch(mobileXtreamServiceProvider(playlist).future);

  // Step 1: Load categories
  print('🔄 [LiveTV] Loading categories...');
  final categories = await service.getLiveCategories();
  print('✅ [LiveTV] Loaded ${categories.length} categories');

  if (categories.isEmpty) {
    print('❌ [LiveTV] No categories found!');
    return [];
  }

  // Step 2: Load channels in SMALL BATCHES (5 at a time for balance)
  final allChannels = <model.Channel>[];
  const batchSize = 5;
  int loaded = 0;
  int totalBatches = (categories.length / batchSize).ceil();

  for (int batchNum = 0; batchNum < totalBatches; batchNum++) {
    int startIdx = batchNum * batchSize;
    int endIdx =
        (startIdx + batchSize < categories.length) ? startIdx + batchSize : categories.length;
    final batch = categories.sublist(startIdx, endIdx);

    print(
      '🔄 [LiveTV] Batch ${batchNum + 1}/$totalBatches (${batch.length} categories)...',
    );

    // Load this batch in parallel
    final futures = batch
        .map(
          (cat) => service
              .getLiveChannels(cat.categoryId)
              .timeout(const Duration(seconds: 15))
              .catchError((_) => <model.Channel>[]),
        )
        .toList();

    final batchResults = await Future.wait(futures);

    // Combine results from this batch
    for (final channels in batchResults) {
      allChannels.addAll(channels);
    }

    loaded += batch.length;
    print(
      '✅ [LiveTV] Batch complete: $loaded/${categories.length} categories, '
      '${allChannels.length} total channels',
    );
  }

  print(
    '🎉 [LiveTV] ALL DONE! ${categories.length} categories, '
    '${allChannels.length} total channels',
  );
  return allChannels;
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
  final String? selectedCategory; // category NAME (for display)
  final String? selectedCategoryId; // category ID (for API calls)
  final bool isCategoryView;

  LiveTvUiState({
    this.selectedCategory,
    this.selectedCategoryId,
    this.isCategoryView = true,
  });

  LiveTvUiState copyWith({
    String? selectedCategory,
    String? selectedCategoryId,
    bool? isCategoryView,
  }) {
    return LiveTvUiState(
      selectedCategory: selectedCategory ?? this.selectedCategory,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
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
