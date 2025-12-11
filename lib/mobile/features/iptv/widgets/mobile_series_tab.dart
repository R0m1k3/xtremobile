import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xtremflow/mobile/widgets/tv_focusable.dart';
import 'package:xtremflow/mobile/widgets/mobile_poster_card.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/components/hero_carousel.dart';
import '../../../../core/widgets/components/ui_components.dart';
import '../../../providers/mobile_settings_providers.dart';
import '../../../providers/mobile_xtream_providers.dart';
import '../../../../features/iptv/services/xtream_service_mobile.dart';
import '../screens/mobile_series_detail_screen.dart';

class MobileSeriesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileSeriesTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileSeriesTab> createState() => _MobileSeriesTabState();
}

class _MobileSeriesTabState extends ConsumerState<MobileSeriesTab> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final List<Series> _series = [];
  List<Series>? _searchResults;
  String _searchQuery = '';
  bool _isSearchEditing = false;
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 50; 
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadMoreSeries();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    // Only trigger load when near bottom and not already loading
    if (!_isLoading && _hasMore &&
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreSeries();
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _searchResults = null;
        _isSearching = false;
      }
    });
    
    if (query.length >= 2) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        _performSearch(query);
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    setState(() => _isSearching = true);
    
    try {
      final service = await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      final results = await service.searchSeries(query);
      
      if (mounted && _searchQuery == query) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _loadMoreSeries() async {
    // Prevent race conditions
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final service = await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      
      // Add timeout to prevent infinite loading state
      final newSeries = await service.getSeriesPaginated(
        offset: _currentOffset,
        limit: _pageSize,
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          _series.addAll(newSeries);
          _currentOffset += _pageSize;
          _hasMore = newSeries.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading series: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Do NOT set _hasMore to false on error
        });
      }
    }
  }

  Future<void> _refresh() async {
    // Clear service cache to force fresh data
    try {
      final service = await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      service.clearCache();
    } catch (_) {}
    
    setState(() {
      _series.clear();
      _currentOffset = 0;
      _hasMore = true;
      _searchResults = null;
      _searchQuery = '';
      _searchController.clear();
      _isLoading = false;
    });
    await _loadMoreSeries();
  }

  String? _formatRating(String? rating) {
    if (rating == null || rating.isEmpty) return null;
    final value = double.tryParse(rating);
    if (value != null) {
      return value.toStringAsFixed(1);
    }
    return rating;
  }

  /// On mobile, use direct URLs (no proxy needed)
  String _getImageUrl(String? originalUrl) {
    if (originalUrl == null || originalUrl.isEmpty) return '';
    return originalUrl;
  }

  void _openSeries(Series series) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MobileSeriesDetailScreen(
          series: series,
          playlist: widget.playlist,
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final settings = ref.watch(mobileSettingsProvider);
    
    List<Series> displaySeries;
    if (_searchQuery.isNotEmpty && _searchResults != null) {
      displaySeries = _searchResults!;
    } else {
      displaySeries = settings.seriesKeywords.isEmpty
          ? _series
          : _series.where((s) => settings.matchesSeriesFilter(s.categoryName)).toList();
    }

    // Hero Items (use filtered series)
    final heroItems = displaySeries.take(3).map((s) => HeroItem(
      id: s.seriesId.toString(),
      title: s.name,
      imageUrl: _getImageUrl(s.cover),
      subtitle: s.rating != null ? '${_formatRating(s.rating)} ★' : null,
      onMoreInfo: () => _openSeries(s),
    )).toList();

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.appleTvGradient),
      child: SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Hero Section (reduced height, moved above search)
          if (_searchQuery.isEmpty && heroItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: SizedBox(
                   height: 180, // Reduced from 250
                   child: HeroCarousel(
                     items: heroItems,
                     onTap: (item) {
                       try {
                         final series = _series.firstWhere((s) => s.seriesId.toString() == item.id);
                         _openSeries(series);
                       } catch (e) {
                         // Fallback logic not critical
                       }
                     },
                   ),
                ),
              ),
            ),

          // Search Bar (moved below carousel)
          SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TVFocusable(
                  onPressed: () {
                    setState(() => _isSearchEditing = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _searchFocusNode.requestFocus();
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: _isSearchEditing 
                          ? Border.all(color: AppColors.primary)
                          : Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ExcludeFocus(
                            excluding: !_isSearchEditing,
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              readOnly: !_isSearchEditing,
                              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                              decoration: const InputDecoration(
                                hintText: 'Rechercher une série...',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.only(bottom: 11),
                              ),
                              onChanged: _onSearchChanged,
                              onSubmitted: (_) => setState(() => _isSearchEditing = false),
                            ),
                          ),
                        ),
                        if (_isSearching)
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                               _searchController.clear();
                               _onSearchChanged('');
                            },
                            child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ),
          
          // Grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8, // Reduced size further (was 4)
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.7,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= displaySeries.length) return null;
                  final series = displaySeries[index];
                  
                  return MobilePosterCard(
                    title: series.name,
                    imageUrl: _getImageUrl(series.cover),
                    rating: _formatRating(series.rating),
                    placeholderIcon: Icons.tv,
                    onTap: () => _openSeries(series),
                  );
                },
                childCount: displaySeries.length,
              ),
            ),
          ),
          
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
      ),
      ),
    );
  }
}
