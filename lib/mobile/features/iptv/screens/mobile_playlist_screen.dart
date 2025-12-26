import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/playlist_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../theme/mobile_theme.dart';
import '../../../../core/services/playlist_api_service.dart';
import 'mobile_dashboard_screen.dart';

/// Provider for local playlists
final localPlaylistsProvider =
    FutureProvider<List<PlaylistConfig>>((ref) async {
  final service = PlaylistApiService();
  return service.getPlaylists();
});

/// Mobile playlist selection screen - simplified without auth
class MobilePlaylistScreen extends ConsumerStatefulWidget {
  const MobilePlaylistScreen({super.key});

  @override
  ConsumerState<MobilePlaylistScreen> createState() =>
      _MobilePlaylistScreenState();
}

class _MobilePlaylistScreenState extends ConsumerState<MobilePlaylistScreen> {
  final PlaylistApiService _playlistService = PlaylistApiService();

  @override
  void initState() {
    super.initState();
    // _playlistService.init(); // PlaylistAPI service inits internally via HiveService

    // Auto-login: if playlists exist, navigate to first one automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoLogin();
    });
  }

  Future<void> _checkAutoLogin() async {
    try {
      final playlists = await _playlistService.getPlaylists();
      if (playlists.length == 1 && mounted) {
        // Navigate to first playlist automatically
        _navigateToDashboard(playlists.first);
      }
    } catch (e) {
      debugPrint('Auto-login check failed: $e');
    }
  }

  void _refreshPlaylists() {
    ref.invalidate(localPlaylistsProvider);
  }

  void _navigateToDashboard(PlaylistConfig playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MobileDashboardScreen(playlist: playlist),
      ),
    );
  }

  void _showPlaylistDialog({PlaylistConfig? playlist}) {
    final isEditing = playlist != null;
    final nameController = TextEditingController(text: playlist?.name ?? '');
    final dnsController = TextEditingController(text: playlist?.dns ?? '');
    final usernameController =
        TextEditingController(text: playlist?.username ?? '');
    final passwordController =
        TextEditingController(text: playlist?.password ?? '');

    // Focus nodes for TV navigation
    final nameFocus = FocusNode();
    final dnsFocus = FocusNode();
    final usernameFocus = FocusNode();
    final passwordFocus = FocusNode();
    final buttonFocus = FocusNode();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(), // Ensure logical order
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              // Ensure scrolling when keyboard/focus moves
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    isEditing ? 'Modifier la playlist' : 'Ajouter une playlist',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Form fields
                  _buildTextField(
                    controller: nameController,
                    label: 'Nom',
                    hint: 'Ma Playlist IPTV',
                    icon: Icons.label_outline,
                    textAction: TextInputAction.next,
                    onSubmitted: () =>
                        FocusScope.of(context).requestFocus(dnsFocus),
                    focusNode: nameFocus,
                  ),

                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: dnsController,
                    label: 'Serveur URL',
                    hint: 'http://example.com:8080',
                    icon: Icons.dns_outlined,
                    keyboardType: TextInputType.url,
                    textAction: TextInputAction.next,
                    onSubmitted: () =>
                        FocusScope.of(context).requestFocus(usernameFocus),
                    focusNode: dnsFocus,
                  ),

                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: usernameController,
                    label: 'Nom d\'utilisateur',
                    hint: 'username',
                    icon: Icons.person_outline,
                    textAction: TextInputAction.next,
                    onSubmitted: () =>
                        FocusScope.of(context).requestFocus(passwordFocus),
                    focusNode: usernameFocus,
                  ),

                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: passwordController,
                    label: 'Mot de passe',
                    hint: '••••••••',
                    icon: Icons.lock_outline,
                    obscureText: true,
                    textAction: TextInputAction.done,
                    onSubmitted: () =>
                        FocusScope.of(context).requestFocus(buttonFocus),
                    focusNode: passwordFocus,
                  ),

                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      focusNode: buttonFocus,
                      onPressed: () async {
                        if (nameController.text.isEmpty ||
                            dnsController.text.isEmpty ||
                            usernameController.text.isEmpty ||
                            passwordController.text.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Veuillez remplir tous les champs'),
                              backgroundColor: AppColors.error,
                            ),
                          );
                          return;
                        }

                        // Auto-fix URL scheme
                        String dns = dnsController.text.trim();
                        if (!dns.startsWith('http://') &&
                            !dns.startsWith('https://')) {
                          dns = 'http://$dns';
                        }

                        if (isEditing) {
                          await _playlistService.updatePlaylist(
                            id: playlist.id,
                            name: nameController.text.trim(),
                            dns: dns,
                            username: usernameController.text.trim(),
                            password: passwordController.text.trim(),
                          );
                        } else {
                          await _playlistService.createPlaylist(
                            name: nameController.text.trim(),
                            dns: dns,
                            username: usernameController.text.trim(),
                            password: passwordController.text.trim(),
                          );
                        }

                        if (mounted) {
                          Navigator.pop(context);
                          _refreshPlaylists();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isEditing
                                    ? 'Playlist modifiée'
                                    : 'Playlist ajoutée',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      icon: Icon(isEditing ? Icons.save : Icons.add),
                      label: Text(isEditing ? 'Enregistrer' : 'Ajouter'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textAction,
    VoidCallback? onSubmitted,
    FocusNode? focusNode, // This is now the "navigation" focus
  }) {
    // Create a dedicated internal focus node for the actual TextField
    // We don't expose this, allowing us to control when the keyboard opens

    // Since we are inside a stateless method but need state for focus nodes if we want to create them on the fly...
    // Actually, to avoid State complexity, we will trust the passed 'focusNode' is for NAVIGATION.
    // And we will use a LayoutBuilder + Stateful wrapper or just a customized Focus widget.

    return _TVTextField(
      controller: controller,
      label: label,
      hint: hint,
      icon: icon,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textAction: textAction,
      onSubmitted: onSubmitted,
      navigationFocus: focusNode,
    );
  }

  void _showOptionsSheet(PlaylistConfig playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit, color: AppColors.textPrimary),
                title: const Text(
                  'Modifier',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showPlaylistDialog(playlist: playlist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: AppColors.error),
                title: const Text(
                  'Supprimer',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(playlist);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(PlaylistConfig playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Supprimer la playlist ?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Voulez-vous supprimer "${playlist.name}" ?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              await _playlistService.deletePlaylist(playlist.id);
              if (mounted) {
                Navigator.pop(context);
                _refreshPlaylists();
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playlistsAsync = ref.watch(localPlaylistsProvider);

    return Theme(
      data: MobileTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('XtremFlow'),
          centerTitle: true,
          backgroundColor: AppColors.background,
          elevation: 0,
        ),
        body: playlistsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
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
                const Text(
                  'Erreur de chargement',
                  style: TextStyle(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _refreshPlaylists,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
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
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.playlist_add,
                        size: 40,
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Aucune playlist',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ajoutez votre première playlist IPTV',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: () => _showPlaylistDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une playlist'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
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
              padding: const EdgeInsets.all(16),
              itemCount: playlists.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                return _PlaylistCard(
                  playlist: playlist,
                  onTap: () => _navigateToDashboard(playlist),
                  onLongPress: () => _showOptionsSheet(playlist),
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showPlaylistDialog(),
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final PlaylistConfig playlist;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PlaylistCard({
    required this.playlist,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
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
                        style: const TextStyle(
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
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textTertiary,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: onLongPress, // Re-use the options sheet logic
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TVTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textAction;
  final VoidCallback? onSubmitted;
  final FocusNode? navigationFocus;

  const _TVTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.textAction,
    this.onSubmitted,
    this.navigationFocus,
  });

  @override
  State<_TVTextField> createState() => _TVTextFieldState();
}

class _TVTextFieldState extends State<_TVTextField> {
  late FocusNode _inputFocus;
  late FocusNode _navFocus;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode();
    _navFocus = widget.navigationFocus ?? FocusNode();

    // When input loses focus (keyboard closed), return to nav focus
    _inputFocus.addListener(() {
      if (!_inputFocus.hasFocus && _isEditing) {
        setState(() => _isEditing = false);
        _navFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    if (widget.navigationFocus == null) _navFocus.dispose();
    super.dispose();
  }

  void _activateInput() {
    setState(() => _isEditing = true);
    // Wait for the widget to rebuild with canRequestFocus: true
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _navFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.gameButtonA ||
              key == LogicalKeyboardKey.numpadEnter) {
            _activateInput();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: _activateInput,
            child: Container(
              decoration: BoxDecoration(
                border: isFocused
                    ? Border.all(color: AppColors.primary, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(4),
              ),
              // Ignore standard focus traversal to child, only allow programatic focus
              child: ExcludeFocus(
                excluding: !_isEditing,
                child: TextField(
                  controller: widget.controller,
                  focusNode: _inputFocus,
                  // Prevent keyboard if somehow focused while not editing
                  readOnly: !_isEditing,
                  showCursor: _isEditing,
                  obscureText: widget.obscureText,
                  keyboardType: widget.keyboardType,
                  textInputAction: widget.textAction,
                  onSubmitted: (_) {
                    setState(() => _isEditing = false);
                    // Give focus back to nav node first so we can move to next
                    _navFocus.requestFocus();
                    widget.onSubmitted?.call();
                  },
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: widget.label,
                    hintText: widget.hint,
                    prefixIcon: Icon(
                      widget.icon,
                      color: isFocused
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    labelStyle: TextStyle(
                      color: isFocused
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    hintStyle: const TextStyle(color: AppColors.textTertiary),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
