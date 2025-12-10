import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../providers/mobile_settings_providers.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/theme/app_colors.dart';

/// Simplified mobile settings tab - no auth, local storage only
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
    final themeState = ref.watch(themeProvider);
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
            padding: const EdgeInsets.only(bottom: 24),
            child: Text(
              'Paramètres',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),

          // App Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
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
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'XtremFlow Mobile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Version 1.1.4',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Appearance
          const _SectionHeader(title: 'Apparence'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              title: const Text('Mode Sombre', 
                style: TextStyle(color: AppColors.textPrimary)),
              secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, 
                color: AppColors.primary),
              value: isDark,
              onChanged: (_) => themeNotifier.toggleTheme(),
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              title: const Text('Afficher l\'heure', 
                style: TextStyle(color: AppColors.textPrimary)),
              secondary: const Icon(Icons.access_time, 
                color: AppColors.primary),
              value: settings.showClock,
              onChanged: (val) => ref.read(mobileSettingsProvider.notifier).toggleShowClock(val),
              activeColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),

          // Playback Settings
          const _SectionHeader(title: 'Lecture Vidéo'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.speed, color: AppColors.primary),
                  title: const Text('Mise en mémoire tampon (Cache)', 
                    style: TextStyle(color: AppColors.textPrimary)),
                  subtitle: Text(
                    settings.bufferDuration == 0 
                      ? 'Auto (Défaut)' 
                      : '${settings.bufferDuration} secondes',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  trailing: DropdownButton<int>(
                    value: settings.bufferDuration,
                    dropdownColor: AppColors.surface,
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Auto', style: TextStyle(color: AppColors.textPrimary))),
                      DropdownMenuItem(value: 15, child: Text('15s', style: TextStyle(color: AppColors.textPrimary))),
                      DropdownMenuItem(value: 30, child: Text('30s', style: TextStyle(color: AppColors.textPrimary))),
                      DropdownMenuItem(value: 60, child: Text('60s', style: TextStyle(color: AppColors.textPrimary))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(mobileSettingsProvider.notifier).setBufferDuration(val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Content Filters
          const _SectionHeader(title: 'Filtres de Contenu'),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Utilisez des mots-clés pour filtrer les catégories (séparés par des virgules)',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                _FilterInput(
                  label: 'TV en Direct',
                  hint: 'Ex: FR, HD, SPORT',
                  icon: Icons.live_tv,
                  controller: _liveTvController,
                  onChanged: (val) {
                    ref.read(mobileSettingsProvider.notifier)
                        .setLiveTvKeywords(_parseKeywords(val));
                  },
                ),
                const SizedBox(height: 16),
                _FilterInput(
                  label: 'Films',
                  hint: 'Ex: FR, VF, 4K',
                  icon: Icons.movie,
                  controller: _moviesController,
                  onChanged: (val) {
                    ref.read(mobileSettingsProvider.notifier)
                        .setMoviesKeywords(_parseKeywords(val));
                  },
                ),
                const SizedBox(height: 16),
                _FilterInput(
                  label: 'Séries',
                  hint: 'Ex: FR, VF',
                  icon: Icons.tv,
                  controller: _seriesController,
                  onChanged: (val) {
                    ref.read(mobileSettingsProvider.notifier)
                        .setSeriesKeywords(_parseKeywords(val));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Change Playlist
          InkWell(
            onTap: () {
              // Navigate back to playlist selection
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.playlist_play, color: AppColors.textPrimary),
                  SizedBox(width: 16),
                  Text(
                    'Changer de Playlist',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Spacer(),
                  Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _FilterInput extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _FilterInput({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(label, 
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500, 
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textTertiary),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
