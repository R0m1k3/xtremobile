import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import '../../../providers/mobile_xtream_providers.dart';
import '../../../providers/mobile_settings_providers.dart';
import '../screens/native_player_screen.dart';
import '../../../../core/models/iptv_models.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/api/dns_resolver.dart';
import '../../../theme/mobile_theme.dart';

class MobileLiveTVTab extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;
  const MobileLiveTVTab({super.key, required this.playlist});

  @override
  ConsumerState<MobileLiveTVTab> createState() => _MobileLiveTVTabState();
}

class _MobileLiveTVTabState extends ConsumerState<MobileLiveTVTab> {
  String? _selectedCategory;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showFavoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isCategoryView = true;

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(mobileLiveChannelsProvider(widget.playlist));
    final favorites = ref.watch(mobileFavoritesProvider);
    final settings = ref.watch(mobileSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: channelsAsync.when(
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
            categories = categories.where((cat) => settings.matchesLiveTvFilter(cat)).toList();
          }
          categories.sort();

          // Prepare channels
          List<Channel> displayedChannels = [];
          
          // Determine mode based on search/favorites/selection
          bool showGrid = _isCategoryView && _searchQuery.isEmpty && !_showFavoritesOnly;

          if (!showGrid) {
            if (_searchQuery.isNotEmpty) {
              displayedChannels = groupedChannels.values.expand((l) => l)
                  .where((c) => c.name.toLowerCase().contains(_searchQuery))
                  .toList();
            } else if (_showFavoritesOnly) {
              displayedChannels = groupedChannels.values.expand((l) => l)
                  .where((c) => favorites.contains(c.streamId))
                  .toList();
            } else if (_selectedCategory != null) {
              displayedChannels = groupedChannels[_selectedCategory] ?? [];
            }
          }

          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Header (Search + Title/Back)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      // Search Bar
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                style: const TextStyle(color: AppColors.textPrimary),
                                decoration: const InputDecoration(
                                  hintText: 'Rechercher une chaîne...',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () => _searchController.clear(),
                                child: const Icon(Icons.close, color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Title / Navigation Row
                      Row(
                        children: [
                          if (!showGrid || _showFavoritesOnly || _searchQuery.isNotEmpty) ...[
                            IconButton(
                              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                              onPressed: () {
                                if (_searchQuery.isNotEmpty) {
                                  _searchController.clear();
                                } else if (_showFavoritesOnly) {
                                  setState(() => _showFavoritesOnly = false);
                                } else {
                                  setState(() => _isCategoryView = true);
                                }
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Text(
                              _searchQuery.isNotEmpty ? 'Résultats de recherche' : 
                              _showFavoritesOnly ? 'Favoris' : 
                              showGrid ? 'Catégories' : 
                              _selectedCategory ?? 'Chaînes',
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
                              _showFavoritesOnly ? Icons.favorite : Icons.favorite_border,
                              color: _showFavoritesOnly ? AppColors.error : AppColors.textSecondary,
                            ),
                            onPressed: () => setState(() {
                              _showFavoritesOnly = !_showFavoritesOnly;
                              // Reset category view if entering favorites
                              if (_showFavoritesOnly) _isCategoryView = false;
                              // If exiting favorites, default depends on logic (here back to category grid if was previously)
                              if (!_showFavoritesOnly) _isCategoryView = true;
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
        crossAxisCount: 8, // Drastically reduced size as requested
        childAspectRatio: 1.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        return InkWell(
          onTap: () {
            setState(() {
              _selectedCategory = category;
              _isCategoryView = false;
            });
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.surface,
                  AppColors.surface.withOpacity(0.8),
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: channels.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final channel = channels[index];
        return _MobileChannelTile(
          channel: channel,
          playlist: widget.playlist,
          onTap: () => _playChannel(context, channel, channels),
        );
      },
    );
  }

  void _playChannel(BuildContext context, Channel channel, List<Channel> channels) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NativePlayerScreen(
          streamId: channel.streamId,
          title: channel.name,
          playlist: widget.playlist,
          streamType: StreamType.live,
          channels: channels,
          initialIndex: channels.indexOf(channel),
        ),
      ),
    );
  }
}

class _MobileChannelTile extends ConsumerStatefulWidget {
  final Channel channel;
  final VoidCallback onTap;
  final PlaylistConfig playlist;

  const _MobileChannelTile({
    required this.channel, 
    required this.onTap,
    required this.playlist,
  });

  @override
  ConsumerState<_MobileChannelTile> createState() => _MobileChannelTileState();
}

class _MobileChannelTileState extends ConsumerState<_MobileChannelTile> {
  String? _epgTitle;
  
  @override
  void initState() {
    super.initState();
    _loadEpg();
  }
  
  Future<void> _loadEpg() async {
    try {
      final service = await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      // Fetch current program
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
    // On mobile, use direct URL (no proxy needed)
    final iconUrl = widget.channel.streamIcon.isNotEmpty && widget.channel.streamIcon.startsWith('http') 
        ? widget.channel.streamIcon 
        : null;

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: iconUrl != null
                  ? Image.network(
                      iconUrl, 
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.white24),
                    )
                  : const Icon(Icons.tv, color: Colors.white24),
            ),
            const SizedBox(width: 12),
            // Name and EPG
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.channel.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_epgTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _epgTitle!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            // Play Icon
            const Icon(Icons.play_circle_outline, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
