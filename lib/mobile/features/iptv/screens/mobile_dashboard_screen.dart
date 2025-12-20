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

    // Determine which tab to show
    Widget currentTab;
    switch (currentIndex) {
      case 0:
        currentTab = MobileLiveTVTab(playlist: widget.playlist);
        break;
      case 1:
        currentTab = MobileMoviesTab(playlist: widget.playlist);
        break;
      case 2:
        currentTab = MobileSeriesTab(playlist: widget.playlist);
        break;
      case 3:
        currentTab = const MobileSettingsTab();
        break;
      default:
        currentTab = MobileLiveTVTab(playlist: widget.playlist);
    }

    return Theme(
      data: MobileTheme.darkTheme,
      child: PopScope(
        canPop: false, // Prevent accidental exit to playlist selection
        child: MobileScaffold(
          currentIndex: currentIndex,
          onIndexChanged: (index) {
            ref.read(mobileDashboardIndexProvider.notifier).state = index;
          },
          child: currentTab,
        ),
      ),
    );
  }
}
