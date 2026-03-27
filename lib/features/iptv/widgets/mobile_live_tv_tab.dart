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

    // Determine if we should show the category grid
    final bool showGrid = uiState.isCategoryView &&
        _searchQuery.isEmpty &&
        !_showFavoritesOnly;

    return Container(
      decoration: AppDecorations.background(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: PopScope(
          // Only allow full pop if we're at category view with no filters AND not just returned from player
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;

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
                        (cat) => settings.matchesLiveTvFilter(cat.categoryName),)
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
                child: Column(
                  children: [
                    // Header (Search + Title/Back)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          // Search Bar - Wrapped in TVFocusable for remote access
                          TVFocusable(
                            scale: 1.0, // Disable scaling to prevent overflow
                            focusColor:
                                Colors.white, // Solid white selection frame
                            onPressed: () {
                              setState(() => _isSearchEditing = true);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _searchFocusNode.requestFocus();
                                SystemChannels.textInput
                                    .invokeMethod('TextInput.show');
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 48,
                              decoration: AppDecorations.searchBar(context),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    color: AppDecorations.textSecondary(context),
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
                                          color: AppDecorations.textPrimary(context),
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: 'Rechercher une chaîne...',
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
                                      onTap: () => _searchController.clear(),
                                      child: Icon(
                                        Icons.close,
                                        color: AppDecorations.textSecondary(context),
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
                                    color: AppDecorations.textPrimary(context),
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
                                    color: AppDecorations.textPrimary(context),
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
                                      : AppDecorations.textSecondary(context),
                                ),
                                onPressed: () => setState(() {
                                  _showFavoritesOnly = !_showFavoritesOnly;
                                  // Reset category view if entering favorites
                                  if (_showFavoritesOnly) {
                                    uiNotifier.state =
                                        uiState.copyWith(isCategoryView: false);
                                  }
                                  // If exiting favorites, default back to category grid
                                  if (!_showFavoritesOnly) {
                                    uiNotifier.state =
                                        uiState.copyWith(isCategoryView: true);
                                  }
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Main Content
                    Expanded(
                      child: showGrid
                          ? _buildCategoryGrid(categories, uiNotifier, uiState)
                          : _ChannelListView(
                              playlist: widget.playlist,
                              uiState: uiState,
                              searchQuery: _searchQuery,
                              showFavoritesOnly: _showFavoritesOnly,
                              onPlay: (channel, channels, index) =>
                                  _playChannel(
                                context,
                                channel,
                                channels,
                                widget.playlist,
                                index,
                              ),
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

  Widget _buildCategoryGrid(
    List<model.Category> categories,
    StateController<LiveTvUiState> uiNotifier,
    LiveTvUiState uiState,
  ) {
    if (categories.isEmpty) {
      return Center(
        child: Text(
          'Aucune catégorie trouvée',
          style: GoogleFonts.inter(color: AppDecorations.textSecondary(context)),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6, // Adjusted to 6 columns as requested
        childAspectRatio: 1.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return TVFocusable(
          onPressed: () {
            uiNotifier.state = LiveTvUiState(
              selectedCategory: category.categoryName,
              selectedCategoryId: category.categoryId,
              isCategoryView: false,
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Base gradient (theme-aware)
              Container(decoration: AppDecorations.glossyCard(context)),
              // Glossy highlight overlay (top shimmer)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 60,
                child: Container(
                  decoration: AppDecorations.glossShimmer(context),
                ),
              ),
              // Content (icon + text) — Positioned.fill ensures Column fills the card
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.live_tv_rounded,
                        color: Color(0xFF0A84FF),
                        size: 36,
                      ),
                    const SizedBox(height: 10),
                    Text(
                      category.categoryName,
                      style: TextStyle(
                        color: AppDecorations.textPrimary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ), // closes Positioned.fill
            ],
          ),
        );
      },
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
          builder: (context) => NativePlayerScreen(
            streamId: channel.streamId,
            title: channel.name,
            playlist: playlist,
            streamType: StreamType.live,
            channels: channels, // Pass full channel list for zapping
            initialIndex: index,
            forceDeinterlace: true,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => LitePlayerScreen(
            streamId: channel.streamId,
            title: channel.name,
            playlist: playlist,
            streamType: StreamType.live,
            channels: channels, // Pass full channel list for zapping
            initialIndex: index,
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
      // No category selected and no filter → go back to categories
      return Center(
        child: Text(
          'Aucune catégorie sélectionnée',
          style: GoogleFonts.inter(color: AppDecorations.textSecondary(context)),
        ),
      );
    }

    // Phase 2: load channels for selected category
    final channelsAsync = categoryId != null
        ? ref.watch(
            mobileLiveChannelsByCategoryProvider((playlist, categoryId)),)
        : null;

    if (channelsAsync == null) {
      // Favorites or search without category: need channels — show loading
      // For favorites/search without a category, we can't load without a categoryId.
      // Show a message directing user to select a category first.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            showFavoritesOnly
                ? 'Sélectionnez une catégorie pour voir vos favoris'
                : 'Sélectionnez une catégorie pour rechercher',
            style: GoogleFonts.inter(color: AppDecorations.textSecondary(context)),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return channelsAsync.when(
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
      data: (channels) {
        // Apply search or favorites filter
        List<Channel> displayedChannels;
        if (searchQuery.isNotEmpty) {
          displayedChannels = channels
              .where((c) => c.name.toLowerCase().contains(searchQuery))
              .toList();
        } else if (showFavoritesOnly) {
          displayedChannels = channels
              .where((c) => favorites.contains(c.streamId))
              .toList();
        } else {
          displayedChannels = channels;
        }

        if (displayedChannels.isEmpty) {
          return Center(
            child: Text(
              'Aucune chaîne trouvée',
              style: GoogleFonts.inter(color: AppDecorations.textSecondary(context)),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
            childAspectRatio: 0.85,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: displayedChannels.length,
          itemBuilder: (context, index) {
            final channel = displayedChannels[index];
            return _MobileChannelCard(
              channel: channel,
              playlist: playlist,
              onTap: () => onPlay(channel, displayedChannels, index),
            );
          },
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            // Base card (theme-aware)
            Container(
              decoration: AppDecorations.glossyCard(context, radius: 12),
            ),
            // Glossy highlight overlay (top shimmer)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 50,
              child: Container(
                decoration: AppDecorations.glossShimmer(context, radius: 12),
              ),
            ),
            // Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Channel Logo
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    decoration: AppDecorations.channelCardBase(context),
                    child: Stack(
                      children: [
                        // Logo
                        // [P1-2 FIX] Optimize channel icon cache (40x40 display)
                        Center(
                          child: iconUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: iconUrl,
                                  fit: BoxFit.contain,
                                  memCacheWidth: 50,
                                  memCacheHeight: 50,
                                  maxWidthDiskCache: 50,
                                  maxHeightDiskCache: 50,
                                  cacheManager: AppCacheManager.instance,
                                  errorWidget: (_, __, ___) => Icon(
                                    Icons.tv,
                                    color: AppDecorations.iconMuted(context),
                                    size: 40,
                                  ),
                                  placeholder: (_, __) => Icon(
                                    Icons.tv,
                                    color: AppDecorations.iconMuted(context),
                                    size: 40,
                                  ),
                                )
                              : Icon(
                                  Icons.tv,
                                  color: AppDecorations.iconMuted(context),
                                  size: 40,
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
                                size: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Channel Name
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.channel.name,
                          style: TextStyle(
                            color: AppDecorations.textPrimary(context),
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_epgTitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _epgTitle!,
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 9,
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
            ),   // end channel card content
          ],
        ),       // end Stack
      ),         // end ClipRRect
    );           // end TVFocusable
  }
}
