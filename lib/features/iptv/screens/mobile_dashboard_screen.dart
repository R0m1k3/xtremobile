import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/playlist_config.dart';
import '../../../widgets/mobile_scaffold.dart';
import '../../../theme/mobile_theme.dart';
import '../widgets/mobile_live_tv_tab.dart';
import '../widgets/mobile_movies_tab.dart';
import '../widgets/mobile_series_tab.dart';
import '../widgets/mobile_settings_tab.dart';
import '../../../providers/mobile_xtream_providers.dart';

class MobileDashboardScreen extends ConsumerStatefulWidget {
  final PlaylistConfig playlist;

  const MobileDashboardScreen({
    super.key,
    required this.playlist,
  });

  @override
  ConsumerState<MobileDashboardScreen> createState() =>
      _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends ConsumerState<MobileDashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(mobileDashboardIndexProvider);

    // [P0-3 FIX] Use IndexedStack to preserve tab state and scroll position
    // Instead of destroying/recreating tabs on each switch, keep all tabs alive in memory
    // This enables instant tab switching and preserves user scroll position, search state, etc.
    // The AutomaticKeepAliveClientMixin in each tab will keep them in the widget tree
    return Theme(
      data: MobileTheme.darkTheme,
      child: MobileScaffold(
        currentIndex: currentIndex,
        onIndexChanged: (index) {
          ref.read(mobileDashboardIndexProvider.notifier).state = index;
        },
        child: IndexedStack(
          index: currentIndex,
          children: [
            // Tab 0: Live TV - stays alive to preserve channel list scroll position
            MobileLiveTVTab(
              key: const PageStorageKey('live_tv_tab'),
              playlist: widget.playlist,
            ),
            // Tab 1: Movies - stays alive to preserve search and filter state
            MobileMoviesTab(
              key: const PageStorageKey('movies_tab'),
              playlist: widget.playlist,
            ),
            // Tab 2: Series - stays alive to preserve series browsing state
            MobileSeriesTab(
              key: const PageStorageKey('series_tab'),
              playlist: widget.playlist,
            ),
            // Tab 3: Settings - stays alive to preserve settings scroll position
            const MobileSettingsTab(
              key: PageStorageKey('settings_tab'),
            ),
          ],
        ),
      ),
    );
  }
}
