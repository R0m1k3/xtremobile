import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/components/hero_carousel.dart';
import '../../../../core/widgets/components/ui_components.dart';
import '../../../providers/mobile_settings_providers.dart';
import '../../../providers/mobile_xtream_providers.dart';
import '../../../../features/iptv/services/xtream_service_mobile.dart';
import '../screens/native_player_screen.dart';

class MobileMoviesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileMoviesTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileMoviesTab> createState() => _MobileMoviesTabState();
}

class _MobileMoviesTabState extends ConsumerState<MobileMoviesTab> with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final List<Movie> _movies = [];
  List<Movie>? _searchResults;
  String _searchQuery = '';
  bool _isLoading = false;
  bool _isSearching = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize = 50; 
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadMoreMovies();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    // Only trigger load when near bottom and not already loading
    if (!_isLoading && _hasMore &&
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreMovies();
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
      final results = await service.searchMovies(query);
      
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

  Future<void> _loadMoreMovies() async {
    // Prevent race conditions
    if (_isLoading || !_hasMore || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final service = await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      
      // Add timeout to prevent infinite loading state
      final newMovies = await service.getMoviesPaginated(
        offset: _currentOffset,
        limit: _pageSize,
      ).timeout(const Duration(seconds: 15));

      if (mounted) {
        setState(() {
          _movies.addAll(newMovies);
          _currentOffset += _pageSize;
          _hasMore = newMovies.length == _pageSize;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading movies: $e');
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
      _movies.clear();
      _currentOffset = 0;
      _hasMore = true;
      _searchResults = null;
      _searchQuery = '';
      _searchController.clear();
      _isLoading = false;
    });
    await _loadMoreMovies();
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

  void _playMovie(Movie movie) {
    // Watch progress is tracked in player at 80% completion
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NativePlayerScreen(
          streamId: movie.streamId,
          title: movie.name,
          playlist: widget.playlist,
          streamType: StreamType.vod,
          containerExtension: movie.containerExtension ?? 'mp4',
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
    final watchHistory = ref.watch(mobileWatchHistoryProvider);
    
    List<Movie> displayMovies;
    if (_searchQuery.isNotEmpty && _searchResults != null) {
      displayMovies = _searchResults!;
    } else {
      displayMovies = settings.moviesKeywords.isEmpty
          ? _movies
          : _movies.where((m) => settings.matchesMoviesFilter(m.categoryName)).toList();
    }

    // Hero Items (use filtered movies)
    final heroItems = displayMovies.take(3).map((m) => HeroItem(
      id: m.streamId,
      title: m.name,
      imageUrl: _getImageUrl(m.streamIcon),
      subtitle: m.rating != null ? '${_formatRating(m.rating)} ★' : null,
      onMoreInfo: () => _playMovie(m),
    )).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Header & Search
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          hintText: 'Search Movies',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.only(bottom: 11),
                        ),
                        onChanged: _onSearchChanged,
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

          // Hero Section
          if (_searchQuery.isEmpty && heroItems.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                   height: 250,
                   child: HeroCarousel(
                     items: heroItems,
                     onTap: (item) {
                       try {
                         final movie = _movies.firstWhere((element) => element.streamId == item.id);
                         _playMovie(movie);
                       } catch (e) {
                         // Fallback ignored
                       }
                     },
                   ),
                ),
              ),
            ),
          
          // Grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8, 
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.7,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= displayMovies.length) return null;
                  final movie = displayMovies[index];
                  final isWatched = watchHistory.isMovieWatched(movie.streamId);
                  
                  return MediaCard(
                    title: movie.name,
                    imageUrl: _getImageUrl(movie.streamIcon),

                    subtitle: movie.rating != null ? '${_formatRating(movie.rating)} ★' : null,
                    rating: _formatRating(movie.rating),
                    isWatched: isWatched,
                    onTap: () => _playMovie(movie),
                    onLongPress: () {
                      ref.read(mobileWatchHistoryProvider.notifier).toggleMovieWatched(movie.streamId);
                    },
                  );
                },
                childCount: displayMovies.length,
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
    );
  }
}
