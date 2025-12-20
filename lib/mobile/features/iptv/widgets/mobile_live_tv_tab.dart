import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../../../providers/mobile_xtream_providers.dart';
import '../../../providers/mobile_settings_providers.dart';
import '../screens/native_player_screen.dart';
import '../../../../core/models/iptv_models.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/api/dns_resolver.dart';
import '../../../theme/mobile_theme.dart';
import 'package:xtremflow/mobile/widgets/tv_focusable.dart';
import 'package:xtremflow/mobile/features/iptv/screens/lite_player_screen.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/ip_service.dart';

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

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
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
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final channelsAsync =
        ref.watch(mobileLiveChannelsProvider(widget.playlist));
    final favorites = ref.watch(mobileFavoritesProvider);
    final settings = ref.watch(mobileSettingsProvider);
    final uiState = ref.watch(mobileLiveTvUiStateProvider);
    final uiNotifier = ref.read(mobileLiveTvUiStateProvider.notifier);

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.appleTvGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: PopScope(
          // Only allow full pop if we're at category view with no filters AND not just returned from player
          canPop: uiState.isCategoryView &&
              _searchQuery.isEmpty &&
              !_showFavoritesOnly,
          onPopInvokedWithResult: (didPop, _) {
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
            }
          },
          child: channelsAsync.when(
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
            data: (groupedChannels) {
              // Prepare categories
              var categories = groupedChannels.keys.toList();
              if (settings.liveTvKeywords.isNotEmpty) {
                categories = categories
                    .where((cat) => settings.matchesLiveTvFilter(cat))
                    .toList();
                categories.sort();
              } else {
                // Smart Sort (GeoIP)
                final userCountry = IpService().country;
                categories.sort((a, b) {
                  if (userCountry != null) {
                    final aMatches =
                        a.toLowerCase().contains(userCountry.toLowerCase());
                    final bMatches =
                        b.toLowerCase().contains(userCountry.toLowerCase());
                    if (aMatches && !bMatches) return -1;
                    if (!aMatches && bMatches) return 1;
                  }
                  return a.compareTo(b);
                });
              }

              // Prepare channels
              List<Channel> displayedChannels = [];

              // Determine mode based on search/favorites/selection
              bool showGrid = uiState.isCategoryView &&
                  _searchQuery.isEmpty &&
                  !_showFavoritesOnly;

              if (!showGrid) {
                if (_searchQuery.isNotEmpty) {
                  displayedChannels = groupedChannels.values
                      .expand((l) => l)
                      .where((c) => c.name.toLowerCase().contains(_searchQuery))
                      .toList();
                } else if (_showFavoritesOnly) {
                  displayedChannels = groupedChannels.values
                      .expand((l) => l)
                      .where((c) => favorites.contains(c.streamId))
                      .toList();
                } else if (uiState.selectedCategory != null) {
                  displayedChannels =
                      groupedChannels[uiState.selectedCategory] ?? [];
                }
              }

              return SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    // Header (Search + Title/Back)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(12),
                                // Removed internal editing border here to prevent conflict and "inside frame" look
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.search,
                                      color: AppColors.textSecondary),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ExcludeFocus(
                                      excluding: !_isSearchEditing,
                                      child: TextField(
                                        cursorColor:
                                            Colors.white, // Extra safety
                                        controller: _searchController,
                                        focusNode: _searchFocusNode,
                                        readOnly: !_isSearchEditing,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary),
                                        decoration: const InputDecoration(
                                          hintText: 'Rechercher une chaîne...',
                                          border: InputBorder.none,
                                          focusedBorder: InputBorder
                                              .none, // Explicitly remove focus border
                                          enabledBorder: InputBorder.none,
                                          isDense: true,
                                        ),
                                        onSubmitted: (_) => setState(
                                            () => _isSearchEditing = false),
                                      ),
                                    ),
                                  ),
                                  if (_searchQuery.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => _searchController.clear(),
                                      child: const Icon(Icons.close,
                                          color: AppColors.textSecondary),
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
                                  icon: const Icon(Icons.arrow_back,
                                      color: AppColors.textPrimary),
                                  onPressed: () {
                                    if (_searchQuery.isNotEmpty) {
                                      _searchController.clear();
                                    } else if (_showFavoritesOnly) {
                                      setState(
                                          () => _showFavoritesOnly = false);
                                    } else {
                                      uiNotifier.state = uiState.copyWith(
                                          isCategoryView: true);
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
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
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
                                      ? AppColors.error
                                      : AppColors.textSecondary,
                                ),
                                onPressed: () => setState(() {
                                  _showFavoritesOnly = !_showFavoritesOnly;
                                  // Reset category view if entering favorites
                                  if (_showFavoritesOnly)
                                    uiNotifier.state =
                                        uiState.copyWith(isCategoryView: false);
                                  // If exiting favorites, default depends on logic (here back to category grid if was previously)
                                  if (!_showFavoritesOnly)
                                    uiNotifier.state =
                                        uiState.copyWith(isCategoryView: true);
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
                          ? _buildCategoryGrid(categories)
                          : _buildChannelList(displayedChannels),
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

  Widget _buildCategoryGrid(List<String> categories) {
    if (categories.isEmpty) {
      return Center(
        child: Text(
          'Aucune catégorie trouvée',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
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
            ref.read(mobileLiveTvUiStateProvider.notifier).state =
                LiveTvUiState(
              selectedCategory: category,
              isCategoryView: false,
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF4A4A4C), // Lighter grey top
                  const Color(0xFF2C2C2E), // Medium grey bottom
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.tv,
                  color: AppColors.primary,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  category,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChannelList(List<Channel> channels) {
    if (channels.isEmpty) {
      return Center(
        child: Text(
          'Aucune chaîne trouvée',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
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
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return _MobileChannelCard(
          channel: channel,
          playlist: widget.playlist,
          onTap: () =>
              _playChannel(context, channel, channels, widget.playlist, index),
        );
      },
    );
  }

  void _playChannel(BuildContext context, Channel channel,
      List<Channel> channels, PlaylistConfig playlist, int index) async {
    final settings = ref.read(mobileSettingsProvider);
    final useNative = settings.playerEngine == 'ultra';

    if (useNative) {
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
      if (mounted && epg.nowPlaying != null && epg.nowPlaying!.isNotEmpty) {
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF4A4A4C), // Lighter grey top
              const Color(0xFF2C2C2E), // Medium grey bottom
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Channel Logo
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Stack(
                  children: [
                    // Logo
                    Center(
                      child: iconUrl != null
                          ? CachedNetworkImage(
                              imageUrl: iconUrl,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => const Icon(Icons.tv,
                                  color: Colors.white38, size: 40),
                              placeholder: (_, __) => const Icon(Icons.tv,
                                  color: Colors.white24, size: 40),
                            )
                          : const Icon(Icons.tv,
                              color: Colors.white38, size: 40),
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
                          child: const Icon(Icons.favorite,
                              color: Colors.white, size: 12),
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.channel.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
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
        ),
      ),
    );
  }
}
