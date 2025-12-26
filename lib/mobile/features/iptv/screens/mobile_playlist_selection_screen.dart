import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/playlist_api_service.dart';
import '../../../../core/models/playlist_config.dart';

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
  ConsumerState<MobilePlaylistSelectionScreen> createState() =>
      _MobilePlaylistSelectionScreenState();
}

class _MobilePlaylistSelectionScreenState
    extends ConsumerState<MobilePlaylistSelectionScreen> {
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
    // Only auto-login if there is exactly ONE playlist
    if (playlists.length == 1 && mounted) {
      context.go('/dashboard', extra: playlists.first);
    }
  }

  Future<void> _showPlaylistDialog({PlaylistConfig? playlist}) async {
    final isEditing = playlist != null;
    final nameController = TextEditingController(text: playlist?.name ?? '');
    final dnsController = TextEditingController(text: playlist?.dns ?? '');
    final userController =
        TextEditingController(text: playlist?.username ?? '');
    final passController =
        TextEditingController(text: playlist?.password ?? '');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          isEditing ? 'Modifier la Playlist' : 'Ajouter une Playlist',
          style: GoogleFonts.inter(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nom',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: dnsController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'URL (DNS)',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: userController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Utilisateur',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Mot de passe',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (isEditing)
            TextButton(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text(
                      'Confirmer',
                      style: TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'Supprimer cette playlist ?',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await PlaylistApiService().deletePlaylist(playlist.id);

                  if (context.mounted) {
                    Navigator.pop(context);
                    ref.invalidate(playlistsProvider);
                  }
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Supprimer'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || dnsController.text.isEmpty) {
                return;
              }

              final service = PlaylistApiService();
              if (isEditing) {
                await service.updatePlaylist(
                  id: playlist.id,
                  name: nameController.text,
                  dns: dnsController.text,
                  username: userController.text,
                  password: passController.text,
                );
              } else {
                await service.createPlaylist(
                  name: nameController.text,
                  dns: dnsController.text,
                  username: userController.text,
                  password: passController.text,
                );
              }

              if (context.mounted) {
                Navigator.pop(context);
                ref.invalidate(playlistsProvider);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            if (widget.manageMode) ...[
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _showPlaylistDialog(),
                tooltip: 'Ajouter une playlist',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
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
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: AppColors.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Erreur de chargement',
                    style: GoogleFonts.inter(color: Colors.white),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(playlistsProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
            data: (playlists) {
              if (playlists.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.playlist_add,
                        size: 64,
                        color: Colors.white54,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Aucune playlist configurée',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () => _showPlaylistDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Ajouter une Playlist'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  16,
                  100,
                  16,
                  16,
                ), // Top padding for AppBar
                itemCount: playlists.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return _MobilePlaylistCard(
                    playlist: playlist,
                    manageMode: widget.manageMode,
                    onTap: () {
                      if (widget.manageMode) {
                        _showPlaylistDialog(playlist: playlist);
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
  final bool manageMode;

  const _MobilePlaylistCard({
    required this.playlist,
    required this.onTap,
    this.manageMode = false,
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
                  child: const Icon(
                    Icons.playlist_play,
                    color: AppColors.primary,
                    size: 28,
                  ),
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
                if (manageMode)
                  const Icon(Icons.edit, color: AppColors.primary)
                else
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
