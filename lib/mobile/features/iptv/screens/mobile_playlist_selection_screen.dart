import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/playlist_api_service.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../features/auth/providers/auth_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../theme/mobile_theme.dart';

final playlistsProvider = FutureProvider<List<PlaylistConfig>>((ref) async {
  final service = PlaylistApiService();
  return service.getPlaylists();
});

class MobilePlaylistSelectionScreen extends ConsumerStatefulWidget {
  final bool manageMode;
  const MobilePlaylistSelectionScreen({super.key, this.manageMode = false});

  @override
  ConsumerState<MobilePlaylistSelectionScreen> createState() => _MobilePlaylistSelectionScreenState();
}

class _MobilePlaylistSelectionScreenState extends ConsumerState<MobilePlaylistSelectionScreen> {
  @override
  void initState() {
    super.initState();
    if (!widget.manageMode) {
      // Check for auto-login after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAutoLogin();
      });
    }
  }

  Future<void> _checkAutoLogin() async {
    final playlists = await ref.read(playlistsProvider.future);
    if (playlists.isNotEmpty && mounted) {
      // Auto-login to the first playlist (or last used)
      // Ideally last used, but for now first is fine as per request "une playlist existe".
      context.go('/dashboard', extra: playlists.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).currentUser;
    final playlistsAsync = ref.watch(playlistsProvider);

    return Theme(
      data: MobileTheme.darkTheme,
      child: Scaffold(
        extendBodyBehindAppBar: true, // For gradient
        appBar: AppBar(
          title: Text(widget.manageMode ? 'Gérer les Playlists' : 'Playlists'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
             if (widget.manageMode)
               IconButton(
                 icon: const Icon(Icons.close),
                 onPressed: () => Navigator.pop(context),
               ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.appleTvGradient,
          ),
          child: playlistsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text('Erreur de chargement', style: GoogleFonts.inter(color: Colors.white)),
                  TextButton(
                    onPressed: () => ref.refresh(playlistsProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
            data: (playlists) {
              if (playlists.isEmpty) {
                 // Even in auto-mode, if empty we show this (or add button)
                 return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.playlist_add, size: 64, color: Colors.white54),
                        const SizedBox(height: 24),
                        Text(
                          'Aucune playlist configurée',
                          style: GoogleFonts.inter(fontSize: 18, color: Colors.white70),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () {
                             // Logic to add playlist (usually dialog or separate screen)
                             // specific logic for add playlist
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter une Playlist'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                 );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 100, 16, 16), // Top padding for AppBar
                itemCount: playlists.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return _MobilePlaylistCard(
                    playlist: playlist,
                    onTap: () {
                      if (widget.manageMode) {
                         // In manage mode, maybe we want to edit or delete? 
                         // For now, just switch to it.
                         context.go('/dashboard', extra: playlist);
                      } else {
                         context.go('/dashboard', extra: playlist);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobilePlaylistCard extends StatelessWidget {
  final PlaylistConfig playlist;
  final VoidCallback onTap;

  const _MobilePlaylistCard({
    required this.playlist,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.playlist_play, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist.name,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Uri.tryParse(playlist.dns)?.host ?? playlist.dns,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
