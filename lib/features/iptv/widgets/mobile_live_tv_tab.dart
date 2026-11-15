import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:xtremobile/core/models/iptv_models.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/core/services/ip_service.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/utils/category_sort.dart';
import 'package:xtremobile/core/utils/form_factor.dart';
import 'package:xtremobile/core/utils/group_label.dart';
import 'package:xtremobile/features/iptv/screens/lite_player_screen.dart';
import 'package:xtremobile/features/iptv/screens/native_player_screen.dart';
import 'package:xtremobile/features/iptv/widgets/channel_preview.dart';
import 'package:xtremobile/features/iptv/widgets/live_widgets.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremobile/mobile/widgets/mobile_scaffold.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';

/// How the Live tab is laid out.
enum _Layout {
  /// Remote control: favourites shelf + group grid, then list + now panel.
  tv,

  /// Wide touch screen: groups and the selected group's channels side by side.
  split,

  /// Phone, or a tablet in portrait: one column at a time.
  stack,
}

class MobileLiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileLiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileLiveTVTab> createState() => _MobileLiveTVTabState();
}

class _MobileLiveTVTabState extends ConsumerState<MobileLiveTVTab>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  /// Coming back to the foreground after this long refetches the channel list,
  /// so an app left running for days on a TV box picks up provider changes.
  static const _autoRefreshAfter = Duration(hours: 4);

  /// Below this width a touch screen shows one column at a time.
  static const _splitMinWidth = 840.0;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showFavoritesOnly = false;

  /// TV channel list: the live preview, released before full-screen playback.
  final _previewKey = GlobalKey<ChannelPreviewState>();
  bool _isSearchEditing = false;

  /// TV only: search is a destination, the field shows once asked for.
  bool _searchOpen = false;
  bool _justReturnedFromPlayer =
      false; // Flag to prevent PopScope interception after player
  bool _isRefreshing = false;

  /// TV: the channel whose programme the panel shows.
  model.Channel? _focusedChannel;

  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Anchor the auto-refresh clock to this first load.
    ref.read(liveCatalogRefreshedAtProvider);
    // Debounce search input to prevent per-keystroke rebuilds.
    _searchController.addListener(() {
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _searchQuery = _searchController.text.trim().toLowerCase();
          });
        }
      });
    });
    // Trigger IP fetch for smart sorting
    IpService().fetchIpDetails().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final lastRefresh = ref.read(liveCatalogRefreshedAtProvider);
    if (DateTime.now().difference(lastRefresh) >= _autoRefreshAfter) {
      _refreshChannels();
    }
  }

  /// Refetch categories and the open category's channels. The current lists
  /// stay on screen until the new ones arrive.
  Future<void> _refreshChannels() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    refreshLiveCatalog(ref);
    final categoryId = ref.read(mobileLiveTvUiStateProvider).selectedCategoryId;
    try {
      await Future.wait<Object>([
        ref.read(mobileLiveCategoriesProvider(widget.playlist).future),
        if (categoryId != null)
          ref.read(
            mobileLiveChannelsByCategoryProvider((widget.playlist, categoryId))
                .future,
          ),
      ]);
    } catch (_) {
      // Errors surface through the providers' own error states.
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  _Layout _layoutOf(BuildContext context) {
    switch (FormFactors.of(context)) {
      case FormFactor.tv:
        return _Layout.tv;
      case FormFactor.tablet:
        return MediaQuery.sizeOf(context).width >= _splitMinWidth
            ? _Layout.split
            : _Layout.stack;
      case FormFactor.phone:
        return _Layout.stack;
    }
  }

  void _openSearch() {
    setState(() {
      _searchOpen = true;
      _isSearchEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _searchOpen = false;
      _isSearchEditing = false;
    });
  }

  void _openGroup(model.Category category) {
    _focusedChannel = null;
    ref.read(mobileLiveTvUiStateProvider.notifier).state = LiveTvUiState(
      selectedCategory: category.categoryName,
      selectedCategoryId: category.categoryId,
      isCategoryView: false,
    );
    if (_searchQuery.isNotEmpty) _clearSearch();
  }

  void _backToGroups() {
    final uiNotifier = ref.read(mobileLiveTvUiStateProvider.notifier);
    uiNotifier.state = uiNotifier.state.copyWith(isCategoryView: true);
    setState(() => _showFavoritesOnly = false);
  }

  Future<void> _handleBack(_Layout layout) async {
    // Only handle back if this tab is currently active (tab index 0)
    if (ref.read(mobileDashboardIndexProvider) != 0) return;

    // Just returned from the player: stay on the channel list.
    if (_justReturnedFromPlayer) {
      _justReturnedFromPlayer = false;
      return;
    }

    final uiState = ref.read(mobileLiveTvUiStateProvider);
    if (_searchQuery.isNotEmpty || _searchOpen) {
      _clearSearch();
    } else if (_showFavoritesOnly) {
      setState(() => _showFavoritesOnly = false);
    } else if (layout != _Layout.split && !uiState.isCategoryView) {
      _backToGroups();
    } else {
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
      if (shouldExit == true) SystemNavigator.pop();
    }
  }

  /// Keyword filter or smart geo-sort (the user's country first).
  List<model.Category> _sortedCategories(
    List<model.Category> all,
    MobileSettings settings,
  ) {
    List<model.Category> categories;
    if (settings.liveTvKeywords.isNotEmpty) {
      categories = all
          .where((cat) => settings.matchesLiveTvFilter(cat.categoryName))
          .toList()
        ..sort((a, b) => a.categoryName.compareTo(b.categoryName));
    } else {
      final userCountry = IpService().country?.toLowerCase();
      categories = List.of(all)
        ..sort((a, b) {
          if (userCountry != null) {
            final aMatches = a.categoryName.toLowerCase().contains(userCountry);
            final bMatches = b.categoryName.toLowerCase().contains(userCountry);
            if (aMatches && !bMatches) return -1;
            if (!aMatches && bMatches) return 1;
          }
          return a.categoryName.compareTo(b.categoryName);
        });
    }
    return categories;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final categoriesAsync =
        ref.watch(mobileLiveCategoriesProvider(widget.playlist));
    final settings = ref.watch(mobileSettingsProvider);
    final layout = _layoutOf(context);

    // Back to the groups: start at the top so the first row is visible.
    ref.listen(mobileLiveTvUiStateProvider, (previous, next) {
      if (previous?.isCategoryView == false && next.isCategoryView) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) _scrollController.jumpTo(0);
        });
      }
    });

    // "Rechercher" chosen in the TV rail while this tab is visible.
    ref.listen(tabSearchRequestProvider, (_, __) {
      if (ref.read(mobileDashboardIndexProvider) == 0) _openSearch();
    });

    return ColoredBox(
      color: AppColors.background,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack(layout);
        },
        child: categoriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => _Message('Erreur : $e', error: true),
          data: (all) {
            final categories = _sortedCategories(all, settings);
            final favoriteKeys = ref.watch(mobileFavoriteCategoriesProvider);
            final split = splitFavorites(
              categories,
              (c) => favoriteKeys.contains(
                MobileFavoriteCategoriesNotifier.keyFor(
                  widget.playlist.id,
                  c.categoryId,
                ),
              ),
            );
            final groups = _GroupLists(
              favorites: _matching(split.favorites),
              others: _matching(split.others),
              total: categories.length,
            );
            switch (layout) {
              case _Layout.tv:
                return _buildTv(groups);
              case _Layout.split:
                return _buildSplit(groups);
              case _Layout.stack:
                return _buildStack(groups);
            }
          },
        ),
      ),
    );
  }

  /// At group level, the search filters groups by name.
  List<model.Category> _matching(List<model.Category> items) {
    if (_searchQuery.isEmpty) return items;
    return items
        .where((c) => c.categoryName.toLowerCase().contains(_searchQuery))
        .toList();
  }

  // ─── Channel data shared by every layout ──────────────────────────────────

  /// Loads the selected group's channels and applies the search and the
  /// favourites filter. Messages (loading, error, empty) go through
  /// [message].
  Widget _withChannels({
    required String? categoryId,
    required Widget Function(List<Channel> channels) builder,
    required Widget Function(Widget child) message,
  }) {
    if (categoryId == null) {
      return message(const _Message('Choisissez un groupe'));
    }
    final channelsAsync = ref.watch(
      mobileLiveChannelsByCategoryProvider((widget.playlist, categoryId)),
    );
    final favorites = ref.watch(mobileFavoritesProvider);
    return channelsAsync.when(
      loading: () => message(const Center(child: CircularProgressIndicator())),
      error: (e, s) => message(_Message('Erreur : $e', error: true)),
      data: (channels) {
        var shown = channels;
        if (_searchQuery.isNotEmpty) {
          shown = shown
              .where((c) => c.name.toLowerCase().contains(_searchQuery))
              .toList();
        }
        if (_showFavoritesOnly) {
          shown = shown.where((c) => favorites.contains(c.streamId)).toList();
        }
        if (shown.isEmpty) {
          return message(
            _Message(
              _showFavoritesOnly
                  ? 'Aucune chaîne favorite dans ce groupe'
                  : 'Aucune chaîne trouvée',
            ),
          );
        }
        return builder(shown);
      },
    );
  }

  int? _channelCount(String? categoryId) {
    if (categoryId == null) return null;
    return ref
        .watch(
          mobileLiveChannelsByCategoryProvider((widget.playlist, categoryId)),
        )
        .valueOrNull
        ?.length;
  }

  void _toggleChannelFavorite(Channel channel) {
    ref.read(mobileFavoritesProvider.notifier).toggle(channel.streamId);
  }

  // ─── TV ────────────────────────────────────────────────────────────────────

  static const _tvPadding = EdgeInsets.fromLTRB(24, 28, 48, 28);

  Widget _buildTv(_GroupLists groups) {
    final uiState = ref.watch(mobileLiveTvUiStateProvider);
    if (!uiState.isCategoryView && uiState.selectedCategoryId != null) {
      return _buildTvChannels(uiState);
    }

    return CustomScrollView(
      controller: _scrollController,
      clipBehavior: Clip.none,
      slivers: [
        SliverPadding(
          padding: _tvPadding.copyWith(bottom: 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Direct', style: AppTheme.display(fontSize: 28)),
                    const SizedBox(width: 16),
                    _TvIconButton(
                      icon: Icons.refresh,
                      busy: _isRefreshing,
                      onPressed: _refreshChannels,
                    ),
                    const Spacer(),
                    const RemoteHint(
                      before: 'Maintenir',
                      after: 'pour épingler un groupe',
                    ),
                  ],
                ),
                if (_searchOpen || _searchQuery.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _searchField('Rechercher un groupe', tv: true),
                ],
              ],
            ),
          ),
        ),
        if (groups.favorites.isNotEmpty) ...[
          _tvSection(
            SectionTitle('Favoris', count: groups.favorites.length),
          ),
          // A wrapping grid rather than a horizontal shelf: every favourite is
          // reachable with up/down on the remote, nothing hides off-screen.
          SliverPadding(
            padding: _tvPadding.copyWith(top: 12, bottom: 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisExtent: 140,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final category = groups.favorites[i];
                  return FavoriteGroupCard(
                    key: ValueKey('fav-${category.categoryId}'),
                    playlist: widget.playlist,
                    category: category,
                    width: double.infinity,
                    height: double.infinity,
                    nameLines: 2,
                    autofocus: i == 0 && !_searchOpen,
                    onPressed: () => _openGroup(category),
                    onLongPress: () => _toggleFavoriteCategory(category),
                  );
                },
                childCount: groups.favorites.length,
              ),
            ),
          ),
        ],
        _tvSection(
          SectionTitle('Tous les groupes', count: groups.others.length),
          top: groups.favorites.isEmpty ? 24 : 32,
        ),
        if (groups.others.isEmpty)
          const SliverToBoxAdapter(child: _Message('Aucun groupe trouvé'))
        else
          SliverPadding(
            padding: _tvPadding.copyWith(top: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                // 3 columns: long names ("FRANCE HEVC 4K CINÉMA") stay whole.
                crossAxisCount: 3,
                mainAxisExtent: 80,
                mainAxisSpacing: 12,
                crossAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final category = groups.others[i];
                  return TvGroupCard(
                    key: ValueKey('live-cat-${category.categoryId}'),
                    label: GroupLabel.parse(category.categoryName),
                    autofocus:
                        i == 0 && groups.favorites.isEmpty && !_searchOpen,
                    onPressed: () => _openGroup(category),
                    onLongPress: () => _toggleFavoriteCategory(category),
                  );
                },
                childCount: groups.others.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _tvSection(Widget child, {double top = 24}) => SliverPadding(
        padding: EdgeInsets.fromLTRB(_tvPadding.left, top, _tvPadding.right, 0),
        sliver: SliverToBoxAdapter(child: child),
      );

  Widget _buildTvChannels(LiveTvUiState uiState) {
    final label = GroupLabel.parse(uiState.selectedCategory ?? '');
    final count = _channelCount(uiState.selectedCategoryId);
    return Padding(
      padding: _tvPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '‹ Direct',
            style: AppTheme.body(fontSize: 14, color: AppColors.textMuted),
          ),
          const SizedBox(height: 4),
          // Name on its own line, full width: long group names stay whole.
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.display(fontSize: 28),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label.meta(channelCount: count),
                      style: AppTheme.body(
                        fontSize: 15,
                        color: AppColors.textMuted,
                        fontFeatures: AppTheme.tabular,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _TvIconButton(
                icon: _showFavoritesOnly
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                onPressed: () =>
                    setState(() => _showFavoritesOnly = !_showFavoritesOnly),
              ),
            ],
          ),
          if (_searchOpen || _searchQuery.isNotEmpty) ...[
            const SizedBox(height: 16),
            _searchField('Rechercher dans le groupe', tv: true),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: _withChannels(
              categoryId: uiState.selectedCategoryId,
              message: (child) => child,
              builder: (channels) {
                final favorites = ref.watch(mobileFavoritesProvider);
                final focused = channels.contains(_focusedChannel)
                    ? _focusedChannel
                    : channels.first;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 400,
                      child: ListView.separated(
                        clipBehavior: Clip.none,
                        itemCount: channels.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (context, i) {
                          final channel = channels[i];
                          return ChannelRow(
                            key: ValueKey('ch-${channel.streamId}'),
                            playlist: widget.playlist,
                            channel: channel,
                            dense: true,
                            autofocus: i == 0 && !_searchOpen,
                            isFavorite: favorites.contains(channel.streamId),
                            onFocus: () =>
                                setState(() => _focusedChannel = channel),
                            onPressed: () =>
                                _playChannel(context, channel, channels, i),
                            onLongPress: () => _toggleChannelFavorite(channel),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: NowPanel(
                        playlist: widget.playlist,
                        channel: focused,
                        preview: focused == null
                            ? null
                            : ChannelPreview(
                                key: _previewKey,
                                playlist: widget.playlist,
                                channel: focused,
                                // Hidden tabs stay mounted (IndexedStack).
                                active:
                                    ref.watch(mobileDashboardIndexProvider) ==
                                        0,
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Phone (and portrait tablet) ───────────────────────────────────────────

  Widget _buildStack(_GroupLists groups) {
    final uiState = ref.watch(mobileLiveTvUiStateProvider);
    final inGroup =
        !uiState.isCategoryView && uiState.selectedCategoryId != null;
    return inGroup ? _buildStackChannels(uiState) : _buildStackGroups(groups);
  }

  Widget _largeTitleBar(
    String title, {
    List<Widget> actions = const [],
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          headlineMedium: AppTheme.display(
            fontSize: 34,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: AppTheme.display(fontSize: 20),
        ),
      ),
      child: SliverAppBar.large(
        pinned: true,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: leading,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [...actions, const SizedBox(width: 4)],
      ),
    );
  }

  Widget _refreshButton() => IconButton(
        tooltip: 'Actualiser les chaînes',
        onPressed: _isRefreshing ? null : _refreshChannels,
        icon: _isRefreshing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, color: AppColors.textSecondary),
      );

  Widget _buildStackGroups(_GroupLists groups) {
    return RefreshIndicator(
      onRefresh: _refreshChannels,
      color: AppColors.textPrimary,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _largeTitleBar('Direct', actions: [_refreshButton()]),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _searchField('Rechercher un groupe'),
            ),
          ),
          if (groups.favorites.isNotEmpty) ...[
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 28, 16, 12),
              sliver: SliverToBoxAdapter(
                child: SectionTitle('Favoris', fontSize: 20),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: groups.favorites.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final category = groups.favorites[i];
                    return FavoriteGroupCard(
                      key: ValueKey('fav-${category.categoryId}'),
                      playlist: widget.playlist,
                      category: category,
                      width: 236,
                      height: 120,
                      onPressed: () => _openGroup(category),
                      onLongPress: () => _toggleFavoriteCategory(category),
                    );
                  },
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 4),
            sliver: SliverToBoxAdapter(
              child: SectionTitle(
                'Tous les groupes',
                count: groups.others.length,
                fontSize: 20,
              ),
            ),
          ),
          if (groups.favorites.isEmpty && _searchQuery.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Appui long sur un groupe pour l’épingler en haut',
                  style:
                      AppTheme.body(fontSize: 14, color: AppColors.textMuted),
                ),
              ),
            ),
          if (groups.others.isEmpty)
            const SliverToBoxAdapter(child: _Message('Aucun groupe trouvé'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
              sliver: SliverList.separated(
                itemCount: groups.others.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                ),
                itemBuilder: (context, i) {
                  final category = groups.others[i];
                  return GroupRow(
                    key: ValueKey('live-cat-${category.categoryId}'),
                    label: GroupLabel.parse(category.categoryName),
                    onTap: () => _openGroup(category),
                    onLongPress: () => _toggleFavoriteCategory(category),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _favoritesFilterButton() => IconButton(
        tooltip: _showFavoritesOnly
            ? 'Toutes les chaînes'
            : 'Chaînes favorites seulement',
        onPressed: () =>
            setState(() => _showFavoritesOnly = !_showFavoritesOnly),
        icon: Icon(
          _showFavoritesOnly ? Icons.star_rounded : Icons.star_outline_rounded,
          color: _showFavoritesOnly
              ? AppColors.textPrimary
              : AppColors.textSecondary,
        ),
      );

  Widget _buildStackChannels(LiveTvUiState uiState) {
    final label = GroupLabel.parse(uiState.selectedCategory ?? '');
    final count = _channelCount(uiState.selectedCategoryId);
    final meta = label.meta(channelCount: count);
    return RefreshIndicator(
      onRefresh: _refreshChannels,
      color: AppColors.textPrimary,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _largeTitleBar(
            label.name,
            leading: IconButton(
              tooltip: 'Retour',
              icon: const Icon(Icons.arrow_back),
              onPressed: _backToGroups,
            ),
            actions: [_favoritesFilterButton()],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (meta.isNotEmpty) ...[
                    Text(
                      meta,
                      style: AppTheme.body(
                        fontSize: 14,
                        color: AppColors.textMuted,
                        fontFeatures: AppTheme.tabular,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _searchField('Rechercher dans le groupe'),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          _withChannels(
            categoryId: uiState.selectedCategoryId,
            message: (child) =>
                SliverFillRemaining(hasScrollBody: false, child: child),
            builder: (channels) {
              final favorites = ref.watch(mobileFavoritesProvider);
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 24),
                sliver: SliverList.separated(
                  itemCount: channels.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 12,
                    endIndent: 12,
                  ),
                  itemBuilder: (context, i) {
                    final channel = channels[i];
                    return ChannelRow(
                      key: ValueKey('ch-${channel.streamId}'),
                      playlist: widget.playlist,
                      channel: channel,
                      isFavorite: favorites.contains(channel.streamId),
                      onPressed: () =>
                          _playChannel(context, channel, channels, i),
                      onLongPress: () => _toggleChannelFavorite(channel),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Tablet, landscape: groups | channels ──────────────────────────────────

  Widget _buildSplit(_GroupLists groups) {
    final uiState = ref.watch(mobileLiveTvUiStateProvider);
    // Nothing chosen yet: open the first favourite, else the first group.
    model.Category? fallback;
    if (uiState.selectedCategoryId == null) {
      fallback = groups.favorites.isNotEmpty
          ? groups.favorites.first
          : (groups.others.isNotEmpty ? groups.others.first : null);
    }
    final selectedId = uiState.selectedCategoryId ?? fallback?.categoryId;
    final selectedName = uiState.selectedCategory ?? fallback?.categoryName;

    Widget row(model.Category category, {required bool favorite}) => GroupRow(
          key: ValueKey('live-cat-${category.categoryId}'),
          label: GroupLabel.parse(category.categoryName),
          height: 56,
          showChevron: false,
          isFavorite: favorite,
          selected: category.categoryId == selectedId,
          onTap: () => _openGroup(category),
          onLongPress: () => _toggleFavoriteCategory(category),
        );

    Widget sectionLabel(String text, {int? count}) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
          child: Text.rich(
            TextSpan(
              text: text,
              children: [
                if (count != null)
                  TextSpan(
                    text: '  $count',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
              ],
            ),
            style: AppTheme.body(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              fontFeatures: AppTheme.tabular,
            ),
          ),
        );

    final label = GroupLabel.parse(selectedName ?? '');
    final meta = label.meta(channelCount: _channelCount(selectedId));

    return SafeArea(
      left: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 360,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 8, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Direct',
                                style: AppTheme.display(fontSize: 32),
                              ),
                            ),
                            _refreshButton(),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _searchField('Rechercher'),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 8, 24),
                  sliver: SliverList.list(
                    children: [
                      if (groups.favorites.isNotEmpty) ...[
                        sectionLabel('Favoris'),
                        for (final c in groups.favorites)
                          row(c, favorite: true),
                      ],
                      sectionLabel(
                        'Tous les groupes',
                        count: groups.others.length,
                      ),
                      if (groups.favorites.isEmpty && _searchQuery.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: Text(
                            'Appui long sur un groupe pour l’épingler en haut',
                            style: AppTheme.body(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      for (final c in groups.others) row(c, favorite: false),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.display(fontSize: 28),
                            ),
                            if (meta.isNotEmpty)
                              Text(
                                meta,
                                style: AppTheme.body(
                                  fontSize: 14,
                                  color: AppColors.textMuted,
                                  fontFeatures: AppTheme.tabular,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _favoritesFilterButton(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _withChannels(
                      categoryId: selectedId,
                      message: (child) => child,
                      builder: (channels) {
                        final favorites = ref.watch(mobileFavoritesProvider);
                        return GridView.builder(
                          padding: const EdgeInsets.only(bottom: 24),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 320,
                            mainAxisExtent: 196,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                          itemCount: channels.length,
                          itemBuilder: (context, i) {
                            final channel = channels[i];
                            return ChannelTile(
                              key: ValueKey('ch-${channel.streamId}'),
                              playlist: widget.playlist,
                              channel: channel,
                              isFavorite: favorites.contains(channel.streamId),
                              onPressed: () =>
                                  _playChannel(context, channel, channels, i),
                              onLongPress: () =>
                                  _toggleChannelFavorite(channel),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Search field ──────────────────────────────────────────────────────────

  /// 48 dp field. On TV it is a focusable box that only becomes editable once
  /// pressed, so the D-pad never gets trapped in a text field.
  Widget _searchField(String hint, {bool tv = false}) {
    final editable = !tv || _isSearchEditing;
    final field = Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, size: 22, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: ExcludeFocus(
              excluding: !editable,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                readOnly: !editable,
                cursorColor: AppColors.textPrimary,
                style: AppTheme.body(fontSize: 16),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      AppTheme.body(fontSize: 16, color: AppColors.textMuted),
                  filled: false,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) {
                  if (tv) setState(() => _isSearchEditing = false);
                },
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty || (tv && _searchOpen))
            IconButton(
              tooltip: 'Effacer',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 20),
              color: AppColors.textMuted,
              onPressed: _clearSearch,
            ),
        ],
      ),
    );
    if (!tv) return field;
    return TVFocusable(
      scale: 1.0,
      borderRadius: BorderRadius.circular(12),
      onPressed: _openSearch,
      child: field,
    );
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  void _toggleFavoriteCategory(model.Category category) {
    final added = ref
        .read(mobileFavoriteCategoriesProvider.notifier)
        .toggle(widget.playlist.id, category.categoryId);
    final name = GroupLabel.parse(category.categoryName).name;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            added
                ? '« $name » épinglé en haut'
                : '« $name » retiré des favoris',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _playChannel(
    BuildContext context,
    Channel channel,
    List<Channel> channels,
    int index,
  ) async {
    final settings = ref.read(mobileSettingsProvider);
    final playlist = widget.playlist;

    // Channels with forced deinterlacing use the lite player.
    final forceDeinterlace =
        settings.deinterlacedChannels.contains(channel.streamId);

    // Free the preview's connection first: many subscriptions allow only one.
    await _previewKey.currentState?.release();
    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => forceDeinterlace
            ? LitePlayerScreen(
                streamId: channel.streamId,
                title: channel.name,
                playlist: playlist,
                streamType: StreamType.live,
                channels: channels,
                initialIndex: index,
              )
            : NativePlayerScreen(
                streamId: channel.streamId,
                title: channel.name,
                playlist: playlist,
                streamType: StreamType.live,
                channels: channels,
                initialIndex: index,
                forceDeinterlace: false,
              ),
      ),
    );

    // Back from the player: keep PopScope from leaving the channel list.
    if (mounted) setState(() => _justReturnedFromPlayer = true);
    _previewKey.currentState?.resume();
  }
}

class _GroupLists {
  const _GroupLists({
    required this.favorites,
    required this.others,
    required this.total,
  });
  final List<model.Category> favorites;
  final List<model.Category> others;
  final int total;
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTheme.body(
            fontSize: 15,
            color: error ? AppColors.error : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Round TV icon button, lit when focused.
class _TvIconButton extends StatelessWidget {
  const _TvIconButton({
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return TVFocusable(
      paintsOwnFocus: true,
      scale: 1.08,
      borderRadius: BorderRadius.circular(20),
      onPressed: busy ? null : onPressed,
      child: Builder(
        builder: (context) {
          final lit = TVFocusable.isFocused(context);
          return AnimatedContainer(
            duration: AppTheme.durationFocus,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: lit ? AppColors.focus : AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    icon,
                    size: 22,
                    color: lit ? AppColors.onFocus : AppColors.textSecondary,
                  ),
          );
        },
      ),
    );
  }
}
