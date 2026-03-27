import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';
import 'package:xtremobile/mobile/widgets/mobile_poster_card.dart';
import 'package:xtremobile/mobile/widgets/mobile_category_card.dart';
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/features/iptv/screens/native_player_screen.dart';

class MobileMoviesTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileMoviesTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileMoviesTab> createState() => _MobileMoviesTabState();
}

class _MobileMoviesTabState extends ConsumerState<MobileMoviesTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Data
  List<MapEntry<String, String>> _categories = [];
  List<model.VodItem> _categoryMovies = [];
  String? _selectedCategoryId;
  String? _selectedCategoryName;

  // Search
  List<model.VodItem>? _searchResults;
  String _searchQuery = '';
  bool _isSearchEditing = false;
  bool _isSearching = false;
  Timer? _searchDebounce;

  // State
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Defer initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _categories.isEmpty) {
        _loadCategories();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
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
      final service =
          await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      final movies = await service.getMovies();
      final results = movies
          .where((m) => m.name.toLowerCase().contains(query.toLowerCase()))
          .toList();

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

  Future<void> _loadCategories() async {
    if (_isLoading || !mounted) return;
    setState(() => _isLoading = true);

    try {
      final service =
          await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      final categories = await service.getVodCategories();

      if (mounted) {
        setState(() {
          _categories = categories
              .map((c) => MapEntry(c.categoryId, c.categoryName))
              .toList()
            ..sort((a, b) => a.value.compareTo(b.value));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectCategory(String id, String name) async {
    setState(() {
      _selectedCategoryId = id;
      _selectedCategoryName = name;
      _categoryMovies = [];
      _isLoading = true;
    });

    try {
      final service =
          await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      final movies = await service.getMoviesByCategory(id);

      if (mounted) {
        setState(() {
          _categoryMovies = movies;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onBack() {
    if (_searchQuery.isNotEmpty) {
      _onSearchChanged('');
      _searchController.clear();
      setState(() => _isSearchEditing = false);
      return;
    }

    if (_selectedCategoryId != null) {
      setState(() {
        _selectedCategoryId = null;
        _selectedCategoryName = null;
        _categoryMovies = [];
      });
      return;
    }
  }

  Future<void> _refresh() async {
    // Clear service cache to force fresh data
    try {
      final service =
          await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      service.clearCache();
    } catch (_) {}

    setState(() {
      _categories.clear();
      _selectedCategoryId = null;
      _selectedCategoryName = null;
      _categoryMovies.clear();
      _searchResults = null;
      _searchQuery = '';
      _searchController.clear();
      _isLoading = false;
    });
    await _loadCategories();
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

  void _playMovie(BuildContext context, model.VodItem movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NativePlayerScreen(
          streamId: movie.streamId,
          title: movie.name,
          playlist: widget.playlist,
          streamType: model.StreamType.vod,
          containerExtension: movie.containerExtension,
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

    // Initial load retry
    if (_categories.isEmpty && !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _categories.isEmpty) {
          _loadCategories();
        }
      });
    }

    // Determine what to display
    final bool showingCategories =
        _searchQuery.isEmpty && _selectedCategoryId == null;
    final bool showingMovies =
        _searchQuery.isEmpty && _selectedCategoryId != null;
    final bool showingSearch = _searchQuery.isNotEmpty;

    // Filter categories based on settings
    final filteredCategories = _categories
        .where((entry) => settings.matchesMoviesFilter(entry.value))
        .toList();

    int itemCount = 0;
    if (showingCategories) {
      itemCount = filteredCategories.length;
    } else if (showingMovies) {
      itemCount = _categoryMovies.length;
    } else if (showingSearch) {
      itemCount = _searchResults?.length ?? 0;
    }

    return Container(
      decoration: AppDecorations.background(context),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;

          // Handle Search Exit
          if (_searchQuery.isNotEmpty || _isSearching) {
            _onSearchChanged(''); // clear search
            _searchController.clear();
            setState(() => _isSearchEditing = false);
            return;
          }

          // Handle Category Back
          if (_selectedCategoryId != null) {
            _onBack();
            return;
          }

          // Root View -> Show Exit Dialog
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text(
                "Quitter l'application",
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                "Voulez-vous vraiment quitter l'application ?",
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  autofocus: true,
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.blueAccent),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Quitter',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          );

          if (shouldExit == true) {
            SystemNavigator.pop();
          }
        },
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(context).colorScheme.surface,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Pinned Header
                SliverAppBar(
                  pinned: true,
                  floating: true,
                  backgroundColor: AppDecorations.background(context).gradient is LinearGradient 
                      ? (AppDecorations.background(context).gradient as LinearGradient).colors.first
                      : Theme.of(context).scaffoldBackgroundColor,
                  elevation: 4,
                  automaticallyImplyLeading: false,
                  expandedHeight: showingMovies ? 110 : 110,
                  collapsedHeight: showingMovies ? 110 : 110,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(
                        children: [
                          if (showingMovies)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                                    onPressed: _onBack,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _selectedCategoryName ?? 'Films',
                                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            const SizedBox(height: 10),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: TVFocusable(
                              scale: 1.0,
                              focusColor: Colors.white,
                              onPressed: () {
                                setState(() => _isSearchEditing = true);
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _searchFocusNode.requestFocus();
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 40,
                                decoration: AppDecorations.searchBar(context),
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, size: 20, color: AppDecorations.textSecondary(context)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ExcludeFocus(
                                        excluding: !_isSearchEditing,
                                        child: TextField(
                                          cursorColor: AppDecorations.textPrimary(context),
                                          controller: _searchController,
                                          focusNode: _searchFocusNode,
                                          readOnly: !_isSearchEditing,
                                          style: TextStyle(fontSize: 14, color: AppDecorations.textPrimary(context)),
                                          decoration: InputDecoration(
                                            hintText: _selectedCategoryId != null ? 'Rechercher...' : 'Rechercher un film...',
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: const EdgeInsets.only(bottom: 11),
                                          ),
                                          onChanged: _onSearchChanged,
                                          onSubmitted: (_) => setState(() => _isSearchEditing = false),
                                        ),
                                      ),
                                    ),
                                    if (_isSearching) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                                    if (_searchQuery.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          _searchController.clear();
                                          _onSearchChanged('');
                                        },
                                        child: Icon(Icons.close, size: 16, color: AppDecorations.textSecondary(context)),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Grid
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: showingCategories ? 3 : 4,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: showingCategories ? 2.0 : 0.67,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (showingCategories) {
                          if (index >= filteredCategories.length) return null;
                          final cat = filteredCategories[index];
                          return MobileCategoryCard(
                            title: cat.value,
                            icon: Icons.movie_filter_rounded,
                            onTap: () => _selectCategory(cat.key, cat.value),
                          );
                        } else if (showingMovies) {
                          if (index >= _categoryMovies.length) return null;
                          final movie = _categoryMovies[index];
                          final isWatched =
                              watchHistory.isMovieWatched(movie.streamId);
                          return MobilePosterCard(
                            title: movie.name,
                            imageUrl: _getImageUrl(movie.streamIcon),
                            rating: _formatRating(movie.rating),
                            isWatched: isWatched,
                            onTap: () => _playMovie(context, movie),
                            onLongPress: () {
                              ref
                                  .read(mobileWatchHistoryProvider.notifier)
                                  .toggleMovieWatched(movie.streamId);
                            },
                          );
                        } else if (showingSearch) {
                          if (_searchResults == null ||
                              index >= _searchResults!.length) {
                            return null;
                          }
                          final movie = _searchResults![index];
                          final isWatched =
                              watchHistory.isMovieWatched(movie.streamId);
                          return MobilePosterCard(
                            title: movie.name,
                            imageUrl: _getImageUrl(movie.streamIcon),
                            rating: _formatRating(movie.rating),
                            isWatched: isWatched,
                            onTap: () => _playMovie(context, movie),
                            onLongPress: () {
                              ref
                                  .read(mobileWatchHistoryProvider.notifier)
                                  .toggleMovieWatched(movie.streamId);
                            },
                          );
                        }
                        return null;
                      },
                      childCount: itemCount,
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
      ),
    );
  }
}
