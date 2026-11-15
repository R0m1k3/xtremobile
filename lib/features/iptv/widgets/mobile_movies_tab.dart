import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xtremobile/mobile/widgets/mobile_poster_card.dart';
import 'package:xtremobile/mobile/widgets/mobile_category_card.dart';
import 'package:xtremobile/mobile/widgets/adaptive_grid.dart';
import 'package:xtremobile/mobile/widgets/tab_header_title.dart';
import 'package:xtremobile/mobile/widgets/mobile_scaffold.dart';
import 'package:xtremobile/core/utils/form_factor.dart';
import 'package:xtremobile/core/utils/group_label.dart';
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/features/iptv/screens/native_player_screen.dart';
import 'package:xtremobile/core/theme/app_colors.dart';

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

  /// TV only: the search field shows once « Rechercher » is chosen.
  bool _searchOpen = false;
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
    ref.listen<int>(fullCatalogRefreshTickProvider, (_, __) => _refresh());
    ref.listen<int>(tabSearchRequestProvider, (_, __) {
      if (ref.read(mobileDashboardIndexProvider) != 1) return;
      setState(() {
        _searchOpen = true;
        _isSearchEditing = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchFocusNode.requestFocus();
        SystemChannels.textInput.invokeMethod('TextInput.show');
      });
    });
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
      color: Colors.transparent,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;

          // Only handle back if this tab is currently active (tab index 1)
          if (ref.read(mobileDashboardIndexProvider) != 1) return;

          // Handle Search Exit
          if (_searchQuery.isNotEmpty || _isSearching) {
            _onSearchChanged(''); // clear search
            _searchController.clear();
            setState(() {
              _isSearchEditing = false;
              _searchOpen = false;
            });
            return;
          }

          if (_searchOpen) {
            setState(() {
              _isSearchEditing = false;
              _searchOpen = false;
            });
            return;
          }

          // Handle Category Back
          if (_selectedCategoryId != null) {
            _onBack();
            return;
          }

          // Root View -> Show Exit Dialog
          if (TvMenu.focusIfAway()) return; // TV: first up to the menu

          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Quitter l'application"),
              content: const Text("Voulez-vous vraiment quitter l'application ?"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  autofocus: true,
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Quitter',
                    style: TextStyle(color: AppColors.error),
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
                SliverToBoxAdapter(
                  child: CatalogHeader(
                    title: showingMovies
                        ? GroupLabel.parse(_selectedCategoryName ?? 'Films').name
                        : showingSearch
                            ? 'Résultats'
                            : 'Films',
                    count: _isLoading ? null : itemCount,
                    backLabel: showingMovies ? 'Films' : null,
                    onBack: _onBack,
                    searchController: _searchController,
                    searchFocusNode: _searchFocusNode,
                    searchHint: _selectedCategoryId != null
                        ? 'Rechercher dans le groupe'
                        : 'Rechercher un film',
                    isSearchEditing: _isSearchEditing,
                    isSearching: _isSearching,
                    showSearchOnTv: _searchOpen,
                    onSearchChanged: _onSearchChanged,
                    onStartEditing: () => setState(() => _isSearchEditing = true),
                    onStopEditing: () => setState(() => _isSearchEditing = false),
                    onClear: () {
                      _searchController.clear();
                      _onSearchChanged('');
                      setState(() {
                        _isSearchEditing = false;
                        _searchOpen = false;
                      });
                    },
                  ),
                ),

                // Grid
                SliverPadding(
                  padding: FormFactors.of(context) == FormFactor.tv
                      ? CatalogHeader.tvPadding.copyWith(top: 0, bottom: 48)
                      : const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverGrid(
                    gridDelegate: showingCategories
                        ? AdaptiveGrid.categoryTiles(context)
                        : AdaptiveGrid.posters(context),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        if (showingCategories) {
                          if (index >= filteredCategories.length) return null;
                          final cat = filteredCategories[index];
                          return MobileCategoryCard(
                            title: cat.value,
                            icon: Icons.movie_filter_rounded,
                            iconColor: AppColors.movies,
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
