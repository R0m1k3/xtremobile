import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:xtremobile/core/utils/image_cache_config.dart';
import 'dart:async';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremobile/features/iptv/screens/native_player_screen.dart';
import 'package:xtremobile/core/models/iptv_models.dart';
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/core/theme/app_decorations.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';
import 'package:xtremobile/mobile/widgets/mobile_category_card.dart';
import 'package:xtremobile/features/iptv/screens/lite_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:xtremobile/core/services/ip_service.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;

class MobileLiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileLiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileLiveTVTab> createState() => _MobileLiveTVTabState();
}

class _MobileLiveTVTabState extends ConsumerState<MobileLiveTVTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _showFavoritesOnly = false;
  bool _isSearchEditing = false;
  bool _justReturnedFromPlayer =
      false; // Flag to prevent PopScope interception after player

  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    // [P1-1 FIX] Debounce search input to prevent per-keystroke rebuilds
    _searchTimer = null;
    _searchController.addListener(() {
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _searchQuery = _searchController.text.toLowerCase();
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
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Phase 1: always watch categories (fast, ~1 second)
    final categoriesAsync =
        ref.watch(mobileLiveCategoriesProvider(widget.playlist));
    final settings = ref.watch(mobileSettingsProvider);
    final uiState = ref.watch(mobileLiveTvUiStateProvider);
    final uiNotifier = ref.read(mobileLiveTvUiStateProvider.notifier);

    // Scroll to top when entering a category so first row is fully visible
    ref.listen(mobileLiveTvUiStateProvider, (previous, next) {
      if (previous?.isCategoryView == true && !next.isCategoryView) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0);
          }
        });
      }
    });

    // Determine if we should show the category grid
    final bool showGrid =
        uiState.isCategoryView && _searchQuery.isEmpty && !_showFavoritesOnly;

    return Container(
      color: const Color(0xFF000000),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: PopScope(
          // Only allow full pop if we're at category view with no filters AND not just returned from player
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;

            // Only handle back if this tab is currently active (tab index 0)
            if (ref.read(mobileDashboardIndexProvider) != 0) return;

            // If just returned from player, reset the flag and do nothing (stay on channel list)
            if (_justReturnedFromPlayer) {
              _justReturnedFromPlayer = false;
              return;
            }

            if (_searchQuery.isNotEmpty) {
              setState(() {
                _searchController.clear();
                _searchQuery = '';
              });
            } else if (_showFavoritesOnly) {
              setState(() => _showFavoritesOnly = false);
            } else if (!uiState.isCategoryView) {
              uiNotifier.state = uiState.copyWith(isCategoryView: true);
            } else {
              // Root View (Categories) -> Show Exit Dialog
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
            }
          },
          child: categoriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Erreur: $e',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (allCategories) {
              // Apply keyword filter and smart geo-sort on categories
              List<model.Category> categories;
              if (settings.liveTvKeywords.isNotEmpty) {
                categories = allCategories
                    .where(
                      (cat) => settings.matchesLiveTvFilter(cat.categoryName),
                    )
                    .toList();
                categories.sort(
                  (a, b) => a.categoryName.compareTo(b.categoryName),
                );
              } else {
                // Smart Sort (GeoIP)
                final userCountry = IpService().country;
                categories = List.of(allCategories);
                categories.sort((a, b) {
                  if (userCountry != null) {
                    final aMatches = a.categoryName
                        .toLowerCase()
                        .contains(userCountry.toLowerCase());
                    final bMatches = b.categoryName
                        .toLowerCase()
                        .contains(userCountry.toLowerCase());
                    if (aMatches && !bMatches) return -1;
                    if (!aMatches && bMatches) return 1;
                  }
                  return a.categoryName.compareTo(b.categoryName);
                });
              }

              return SafeArea(
                bottom: false,
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    // Floating Header (Search + Navigation)
                    SliverAppBar(
                      floating: false,
                      pinned: true,
                      snap: false,
                      backgroundColor: const Color(0xFF000000), // Opaque black
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      automaticallyImplyLeading: false,
                      toolbarHeight: _searchQuery.isNotEmpty ||
                              _showFavoritesOnly ||
                              !uiState.isCategoryView
                          ? 120.0
                          : 110.0,
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Search Bar
                              TVFocusable(
                                scale: 1.0,
                                focusColor: Colors.white,
                                onPressed: () {
                                  setState(() => _isSearchEditing = true);
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _searchFocusNode.requestFocus();
                                    SystemChannels.textInput
                                        .invokeMethod('TextInput.show');
                                  });
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  height: 48,
                                  decoration: AppDecorations.searchBar(context),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.search,
                                        color: AppDecorations.textSecondary(
                                            context),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ExcludeFocus(
                                          excluding: !_isSearchEditing,
                                          child: TextField(
                                            cursorColor: Colors.white,
                                            controller: _searchController,
                                            focusNode: _searchFocusNode,
                                            readOnly: !_isSearchEditing,
                                            style: TextStyle(
                                              color: AppDecorations.textPrimary(
                                                  context),
                                            ),
                                            decoration: const InputDecoration(
                                              hintText:
                                                  'Rechercher une chaîne...',
                                              border: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              isDense: true,
                                            ),
                                            onSubmitted: (_) => setState(
                                              () => _isSearchEditing = false,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_searchQuery.isNotEmpty)
                                        GestureDetector(
                                          onTap: () =>
                                              _searchController.clear(),
                                          child: Icon(
                                            Icons.close,
                                            color: AppDecorations.textSecondary(
                                                context),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Title / Navigation Row
                              Row(
                                children: [
                                  if (!showGrid ||
                                      _showFavoritesOnly ||
                                      _searchQuery.isNotEmpty) ...[
                                    IconButton(
                                      icon: Icon(
                                        Icons.arrow_back,
                                        color:
                                            AppDecorations.textPrimary(context),
                                      ),
                                      onPressed: () {
                                        if (_searchQuery.isNotEmpty) {
                                          _searchController.clear();
                                        } else if (_showFavoritesOnly) {
                                          setState(
                                            () => _showFavoritesOnly = false,
                                          );
                                        } else {
                                          uiNotifier.state = uiState.copyWith(
                                            isCategoryView: true,
                                          );
                                        }
                                      },
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Text(
                                      _searchQuery.isNotEmpty
                                          ? 'Résultats de recherche'
                                          : _showFavoritesOnly
                                              ? 'Favoris'
                                              : showGrid
                                                  ? 'Catégories'
                                                  : uiState.selectedCategory ??
                                                      'Chaînes',
                                      style: TextStyle(
                                        color:
                                            AppDecorations.textPrimary(context),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _showFavoritesOnly
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: _showFavoritesOnly
                                          ? const Color(0xFFFF453A)
                                          : AppDecorations.textSecondary(
                                              context),
                                    ),
                                    onPressed: () => setState(() {
                                      _showFavoritesOnly = !_showFavoritesOnly;
                                      if (_showFavoritesOnly) {
                                        uiNotifier.state = uiState.copyWith(
                                          isCategoryView: false,
                                        );
                                      }
                                      if (!_showFavoritesOnly) {
                                        uiNotifier.state = uiState.copyWith(
                                            isCategoryView: true);
                                      }
                                    }),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Main Content Sliver
                    if (showGrid)
                      _buildCategorySliver(categories, uiNotifier, uiState)
                    else
                      _ChannelListView(
                        playlist: widget.playlist,
                        uiState: uiState,
                        searchQuery: _searchQuery,
                        showFavoritesOnly: _showFavoritesOnly,
                        onPlay: (channel, channels, index) => _playChannel(
                          context,
                          channel,
                          channels,
                          widget.playlist,
                          index,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySliver(
    List<model.Category> categories,
    StateController<LiveTvUiState> uiNotifier,
    LiveTvUiState uiState,
  ) {
    if (categories.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Text(
            'Aucune catégorie trouvée',
            style:
                GoogleFonts.inter(color: AppDecorations.textSecondary(context)),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 80),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          childAspectRatio: 1.0,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final category = categories[index];
            return MobileCategoryCard(
              title: category.categoryName,
              icon: Icons.live_tv_rounded,
              onTap: () {
                uiNotifier.state = LiveTvUiState(
                  selectedCategory: category.categoryName,
                  selectedCategoryId: category.categoryId,
                  isCategoryView: false,
                );
              },
            );
          },
          childCount: categories.length,
        ),
      ),
    );
  }

  void _playChannel(
    BuildContext context,
    Channel channel,
    List<Channel> channels,
    PlaylistConfig playlist,
    int index,
  ) async {
    final settings = ref.read(mobileSettingsProvider);

    // Check if channel has forced deinterlacing enabled
    final forceDeinterlace =
        settings.deinterlacedChannels.contains(channel.streamId);

    if (forceDeinterlace) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LitePlayerScreen(
            streamId: channel.streamId,
            title: channel.name,
            playlist: playlist,
            streamType: StreamType.live,
            channels: channels,
            initialIndex: index,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NativePlayerScreen(
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
    }

    // When returning from player, set flag to prevent PopScope from going back to categories
    if (mounted) {
      setState(() => _justReturnedFromPlayer = true);
    }
  }
}

/// Phase 2 widget: loads channels for the selected category (or handles search/favorites)
class _ChannelListView extends ConsumerWidget {
  final PlaylistConfig playlist;
  final LiveTvUiState uiState;
  final String searchQuery;
  final bool showFavoritesOnly;
  final void Function(Channel, List<Channel>, int) onPlay;

  const _ChannelListView({
    required this.playlist,
    required this.uiState,
    required this.searchQuery,
    required this.showFavoritesOnly,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(mobileFavoritesProvider);

    // Determine which category to fetch channels for
    final categoryId = uiState.selectedCategoryId;

    if (categoryId == null && !showFavoritesOnly && searchQuery.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text(
            'Aucune catégorie sélectionnée',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    // Phase 2: load channels for selected category
    final channelsAsync = categoryId != null
        ? ref.watch(
            mobileLiveChannelsByCategoryProvider((playlist, categoryId)),
          )
        : null;

    if (channelsAsync == null) {
      return SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              showFavoritesOnly
                  ? 'Sélectionnez une catégorie pour voir vos favoris'
                  : 'Sélectionnez une catégorie pour rechercher',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return channelsAsync.when(
      loading: () => const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, s) => SliverFillRemaining(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Erreur: $e',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
      data: (channels) {
        // Apply search or favorites filter
        List<Channel> displayedChannels;
        if (searchQuery.isNotEmpty) {
          displayedChannels = channels
              .where((c) => c.name.toLowerCase().contains(searchQuery))
              .toList();
        } else if (showFavoritesOnly) {
          displayedChannels =
              channels.where((c) => favorites.contains(c.streamId)).toList();
        } else {
          displayedChannels = channels;
        }

        if (displayedChannels.isEmpty) {
          return const SliverFillRemaining(
            child: Center(
              child: Text(
                'Aucune chaîne trouvée',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              childAspectRatio: 1.0,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final channel = displayedChannels[index];
                return _MobileChannelCard(
                  channel: channel,
                  playlist: playlist,
                  onTap: () => onPlay(channel, displayedChannels, index),
                );
              },
              childCount: displayedChannels.length,
            ),
          ),
        );
      },
    );
  }
}

class _MobileChannelCard extends ConsumerStatefulWidget {
  final Channel channel;
  final VoidCallback onTap;
  final PlaylistConfig playlist;

  const _MobileChannelCard({
    required this.channel,
    required this.onTap,
    required this.playlist,
  });

  @override
  ConsumerState<_MobileChannelCard> createState() => _MobileChannelCardState();
}

class _MobileChannelCardState extends ConsumerState<_MobileChannelCard> {
  String? _epgTitle;

  @override
  void initState() {
    super.initState();
    _loadEpg();
  }

  Future<void> _loadEpg() async {
    try {
      final service =
          await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      final epg = await service.getShortEPG(widget.channel.streamId);
      if (mounted && epg.nowPlaying.isNotEmpty) {
        setState(() {
          _epgTitle = epg.nowPlaying;
        });
      }
    } catch (e) {
      // Ignore EPG errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconUrl = widget.channel.streamIcon.isNotEmpty &&
            widget.channel.streamIcon.startsWith('http')
        ? widget.channel.streamIcon
        : null;

    final favorites = ref.watch(mobileFavoritesProvider);
    final isFavorite = favorites.contains(widget.channel.streamId);

    return TVFocusable(
      onPressed: widget.onTap,
      onLongPress: () {
        ref
            .read(mobileFavoritesProvider.notifier)
            .toggle(widget.channel.streamId);
      },
      child: Container(
        decoration: AppDecorations.glossyCard(context, radius: 12),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Glossy highlight overlay (top shimmer)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 40,
              child: Container(
                decoration: AppDecorations.glossShimmer(context, radius: 12),
              ),
            ),
            // Content
            Positioned.fill(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Channel Logo
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: AppDecorations.channelCardBase(context),
                      child: Stack(
                        children: [
                          // Logo
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: iconUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: iconUrl,
                                      fit: BoxFit.contain,
                                      memCacheHeight: 120,
                                      cacheManager: AppCacheManager.instance,
                                      errorWidget: (_, __, ___) => Icon(
                                        Icons.tv,
                                        color:
                                            AppDecorations.iconMuted(context),
                                        size: 30,
                                      ),
                                      placeholder: (_, __) => Icon(
                                        Icons.tv,
                                        color:
                                            AppDecorations.iconMuted(context),
                                        size: 30,
                                      ),
                                    )
                                  : Icon(
                                      Icons.tv,
                                      color: AppDecorations.iconMuted(context),
                                      size: 30,
                                    ),
                            ),
                          ),
                          // Favorite badge
                          if (isFavorite)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.favorite,
                                  color: Colors.white,
                                  size: 10,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Channel Info
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.channel.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_epgTitle != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              _epgTitle!,
                              style: const TextStyle(
                                color: Colors.yellow,
                                fontSize: 8,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
