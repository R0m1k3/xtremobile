import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import '../../../providers/mobile_settings_providers.dart';
import '../../../widgets/tv_focusable.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../screens/mobile_playlist_selection_screen.dart';

/// Simplified mobile settings tab - optimized for TV remote control
class MobileSettingsTab extends ConsumerStatefulWidget {
  const MobileSettingsTab({super.key});

  @override
  ConsumerState<MobileSettingsTab> createState() => _MobileSettingsTabState();
}

class _MobileSettingsTabState extends ConsumerState<MobileSettingsTab> {
  late TextEditingController _liveTvController;
  late TextEditingController _moviesController;
  late TextEditingController _seriesController;
  bool _initialized = false;
  bool _isRefreshingCache = false;

  @override
  void initState() {
    super.initState();
    _liveTvController = TextEditingController();
    _moviesController = TextEditingController();
    _seriesController = TextEditingController();
  }

  @override
  void dispose() {
    _liveTvController.dispose();
    _moviesController.dispose();
    _seriesController.dispose();
    super.dispose();
  }

  void _syncControllers(MobileSettings settings) {
    if (!_initialized) {
      _liveTvController.text = settings.liveTvKeywords.join(', ');
      _moviesController.text = settings.moviesKeywords.join(', ');
      _seriesController.text = settings.seriesKeywords.join(', ');
      _initialized = true;
    }
  }

  List<String> _parseKeywords(String text) {
    return text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(mobileSettingsProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) _syncControllers(settings);
    });

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_circle_filled, 
                    color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'XtremFlow Mobile',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Version 1.2.5',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),

          // === APPARENCE ===
          _buildSectionHeader('Apparence'),
          
          _buildSettingItem(
            icon: isDark ? Icons.dark_mode : Icons.light_mode,
            title: 'Mode Sombre',
            value: isDark ? 'Activé' : 'Désactivé',
            onTap: () => themeNotifier.toggleTheme(),
          ),
          
          _buildSettingItem(
            icon: Icons.access_time,
            title: 'Afficher l\'heure',
            value: settings.showClock ? 'Activé' : 'Désactivé',
            onTap: () => ref.read(mobileSettingsProvider.notifier).toggleShowClock(!settings.showClock),
          ),
          
          const SizedBox(height: 24),

          // === LECTURE VIDEO ===
          _buildSectionHeader('Lecture Vidéo'),
          
          _buildSettingItem(
            icon: Icons.rocket_launch,
            title: 'Moteur Vidéo',
            subtitle: settings.playerEngine == 'ultra' ? 'Ultra (MPV) - Puissant' : 'Lite (ExoPlayer) - Léger',
            value: settings.playerEngine == 'ultra' ? 'Ultra' : 'Lite',
            onTap: () {
              final newValue = settings.playerEngine == 'ultra' ? 'lite' : 'ultra';
              ref.read(mobileSettingsProvider.notifier).setPlayerEngine(newValue);
            },
          ),
          
          _buildSettingItem(
            icon: Icons.bug_report,
            title: 'Stats pour Nerds',
            subtitle: 'Affiche FPS, Buffer, Bitrate',
            value: settings.showDebugStats ? 'Activé' : 'Désactivé',
            onTap: () => ref.read(mobileSettingsProvider.notifier).toggleShowDebugStats(!settings.showDebugStats),
          ),
          
          _buildSettingItem(
            icon: Icons.memory,
            title: 'Décodeur Vidéo',
            subtitle: _getDecoderSubtitle(settings.decoderMode),
            value: _getDecoderValue(settings.decoderMode),
            onTap: () {
              final modes = ['auto', 'mediacodec', 'no'];
              final currentIndex = modes.indexOf(settings.decoderMode);
              final nextIndex = (currentIndex + 1) % modes.length;
              ref.read(mobileSettingsProvider.notifier).setDecoderMode(modes[nextIndex]);
            },
          ),
          
          _buildSettingItem(
            icon: Icons.speed,
            title: 'Buffer (Cache)',
            subtitle: settings.bufferDuration == 0 ? 'Automatique' : '${settings.bufferDuration} secondes',
            value: settings.bufferDuration == 0 ? 'Auto' : '${settings.bufferDuration}s',
            onTap: () {
              final buffers = [0, 15, 30, 60];
              final currentIndex = buffers.indexOf(settings.bufferDuration);
              final nextIndex = (currentIndex + 1) % buffers.length;
              ref.read(mobileSettingsProvider.notifier).setBufferDuration(buffers[nextIndex]);
            },
          ),
          
          const SizedBox(height: 24),

          // === FILTRES ===
          _buildSectionHeader('Filtres de Contenu'),
          
          _buildFilterInput(
            label: 'TV en Direct',
            hint: 'Ex: FR, HD, SPORT',
            icon: Icons.live_tv,
            controller: _liveTvController,
            onChanged: (val) {
              ref.read(mobileSettingsProvider.notifier).setLiveTvKeywords(_parseKeywords(val));
            },
          ),
          
          _buildFilterInput(
            label: 'Films',
            hint: 'Ex: FR, VF, 4K',
            icon: Icons.movie,
            controller: _moviesController,
            onChanged: (val) {
              ref.read(mobileSettingsProvider.notifier).setMoviesKeywords(_parseKeywords(val));
            },
          ),
          
          _buildFilterInput(
            label: 'Séries',
            hint: 'Ex: FR, VF',
            icon: Icons.tv,
            controller: _seriesController,
            onChanged: (val) {
              ref.read(mobileSettingsProvider.notifier).setSeriesKeywords(_parseKeywords(val));
            },
          ),
          
          const SizedBox(height: 24),

          // === CACHE ===
          _buildSectionHeader('Cache'),
          
          _buildSettingItem(
            icon: _isRefreshingCache ? Icons.hourglass_empty : Icons.refresh,
            title: 'Actualiser le cache',
            subtitle: 'Recharge films, séries et EPG',
            value: _isRefreshingCache ? '...' : 'Appuyer',
            onTap: _isRefreshingCache ? null : _refreshCache,
          ),
          
          const SizedBox(height: 24),

          // === PLAYLIST ===
          _buildSectionHeader('Playlist'),
          
          _buildSettingItem(
            icon: Icons.playlist_play,
            title: 'Gérer les Playlists',
            subtitle: 'Ajouter, modifier, supprimer',
            value: '→',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MobilePlaylistSelectionScreen(manageMode: true),
                ),
              );
            },
          ),
          
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // === HELPER METHODS ===
  
  String _getDecoderSubtitle(String mode) {
    switch (mode) {
      case 'auto': return 'Automatique (Recommandé)';
      case 'mediacodec': return 'Matériel (Hardware)';
      case 'no': return 'Logiciel (Software)';
      default: return 'Automatique';
    }
  }
  
  String _getDecoderValue(String mode) {
    switch (mode) {
      case 'auto': return 'Auto';
      case 'mediacodec': return 'HW';
      case 'no': return 'SW';
      default: return 'Auto';
    }
  }

  Future<void> _refreshCache() async {
    setState(() => _isRefreshingCache = true);
    
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheStore = HiveCacheStore(dir.path);
      await cacheStore.clean();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cache actualisé ! Relancez l\'app pour recharger.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshingCache = false);
    }
  }

  // === UI BUILDERS ===
  
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required String value,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TVFocusable(
        onPressed: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterInput({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TVFocusable(
        onPressed: () {
          // Open keyboard dialog for text input
          _showKeyboardDialog(label, controller, onChanged);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      controller.text.isEmpty ? hint : controller.text,
                      style: TextStyle(
                        color: controller.text.isEmpty 
                            ? AppColors.textSecondary 
                            : AppColors.textPrimary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.edit, color: AppColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showKeyboardDialog(String label, TextEditingController controller, ValueChanged<String> onChanged) {
    final tempController = TextEditingController(text: controller.text);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Filtres $label', style: const TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: tempController,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Séparez par des virgules',
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              controller.text = tempController.text;
              onChanged(tempController.text);
              Navigator.pop(ctx);
            },
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
  }
}
