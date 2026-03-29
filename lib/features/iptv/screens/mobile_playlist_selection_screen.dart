import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/services/playlist_api_service.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../mobile/widgets/tv_focusable.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../mobile/theme/mobile_theme.dart';

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
    await showDialog(
      context: context,
      builder: (context) => _PlaylistEditDialog(
        isEditing: isEditing,
        playlist: playlist,
        onSave: (name, dns, username, password) async {
          final service = PlaylistApiService();
          if (isEditing) {
            await service.updatePlaylist(
              id: playlist.id,
              name: name,
              dns: dns,
              username: username,
              password: password,
            );
          } else {
            await service.createPlaylist(
              name: name,
              dns: dns,
              username: username,
              password: password,
            );
          }
          ref.invalidate(playlistsProvider);
        },
        onDelete: isEditing
            ? () async {
                await PlaylistApiService().deletePlaylist(playlist.id);
                ref.invalidate(playlistsProvider);
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return Theme(
      data: MobileTheme.themeOf(context),
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
                      TVFocusable(
                        onPressed: () => _showPlaylistDialog(),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0A84FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'Ajouter une Playlist',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
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

/// TV-friendly playlist edit dialog.
/// Each field is a focusable row; pressing select opens a single-field input dialog.
class _PlaylistEditDialog extends StatefulWidget {
  final bool isEditing;
  final PlaylistConfig? playlist;
  final Future<void> Function(String name, String dns, String username, String password) onSave;
  final Future<void> Function()? onDelete;

  const _PlaylistEditDialog({
    required this.isEditing,
    required this.playlist,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_PlaylistEditDialog> createState() => _PlaylistEditDialogState();
}

class _PlaylistEditDialogState extends State<_PlaylistEditDialog> {
  late String _name;
  late String _dns;
  late String _username;
  late String _password;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _name = widget.playlist?.name ?? '';
    _dns = widget.playlist?.dns ?? '';
    _username = widget.playlist?.username ?? '';
    _password = widget.playlist?.password ?? '';
  }

  Future<void> _editField({
    required String label,
    required String currentValue,
    required void Function(String) onSaved,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(label, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          keyboardType: keyboardType,
          textInputAction: TextInputAction.done,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white),
            ),
          ),
          onSubmitted: (val) => Navigator.pop(ctx, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            autofocus: false,
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      onSaved(result);
    }
  }

  Widget _buildFieldRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    bool obscure = false,
  }) {
    final displayValue = obscure && value.isNotEmpty
        ? '•' * value.length.clamp(1, 12)
        : value.isEmpty
            ? '—'
            : value;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TVFocusable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayValue,
                      style: TextStyle(
                        color: value.isEmpty ? Colors.white38 : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit, color: Colors.white38, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        widget.isEditing ? 'Modifier la Playlist' : 'Ajouter une Playlist',
        style: GoogleFonts.inter(color: Colors.white),
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFieldRow(
              icon: Icons.label_outline,
              label: 'Nom',
              value: _name,
              onTap: () => _editField(
                label: 'Nom',
                currentValue: _name,
                onSaved: (v) => setState(() => _name = v),
              ),
            ),
            _buildFieldRow(
              icon: Icons.link,
              label: 'URL (DNS)',
              value: _dns,
              onTap: () => _editField(
                label: 'URL (DNS)',
                currentValue: _dns,
                keyboardType: TextInputType.url,
                onSaved: (v) => setState(() => _dns = v),
              ),
            ),
            _buildFieldRow(
              icon: Icons.person_outline,
              label: 'Utilisateur',
              value: _username,
              onTap: () => _editField(
                label: 'Utilisateur',
                currentValue: _username,
                onSaved: (v) => setState(() => _username = v),
              ),
            ),
            _buildFieldRow(
              icon: Icons.lock_outline,
              label: 'Mot de passe',
              value: _password,
              obscure: true,
              onTap: () => _editField(
                label: 'Mot de passe',
                currentValue: _password,
                obscure: true,
                onSaved: (v) => setState(() => _password = v),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TVFocusable(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: const Text('Confirmer', style: TextStyle(color: Colors.white)),
                  content: const Text('Supprimer cette playlist ?', style: TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Annuler'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Supprimer'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await widget.onDelete!();
                if (context.mounted) Navigator.pop(context);
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ),
        TVFocusable(
          onPressed: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('Annuler', style: TextStyle(color: Colors.white70)),
          ),
        ),
        TVFocusable(
          onPressed: _isSaving || _name.isEmpty || _dns.isEmpty
              ? null
              : () async {
                  setState(() => _isSaving = true);
                  await widget.onSave(_name, _dns, _username, _password);
                  if (context.mounted) Navigator.pop(context);
                },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _name.isEmpty || _dns.isEmpty
                  ? Colors.white12
                  : AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _isSaving ? '...' : 'Enregistrer',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
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
