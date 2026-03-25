import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'features/iptv/screens/mobile_playlist_screen.dart';
import 'features/iptv/screens/mobile_dashboard_screen.dart';
import 'core/models/playlist_config.dart';
import 'core/database/hive_service.dart';
import 'core/utils/startup_profiler.dart';

/// Android-optimized entry point for XtremFlow IPTV
/// No authentication - direct access to playlist selection
void main() async {
  StartupProfiler.start('app_init');

  WidgetsFlutterBinding.ensureInitialized();
  StartupProfiler.mark('flutter_binding_init');

  // Initialize MediaKit (required for video playback)
  MediaKit.ensureInitialized();
  StartupProfiler.mark('media_kit_init');

  // Initialize Hive (Centralized)
  await HiveService.init();
  StartupProfiler.mark('hive_init');

  // [P0-2 FIX] Implement TTL-based cache instead of destructive clearing
  // Cache is now persistent with TTL:
  // - Channel/category lists: 6 hours
  // - EPG data: 1 hour
  // - Search results: 30 minutes
  // Manual cache refresh is available in settings if needed
  try {
    await HiveService.invalidateExpiredCache();
    debugPrint('XtremFlow: Expired cache entries invalidated (TTL-based)');
  } catch (e) {
    debugPrint('XtremFlow: Cache maintenance skipped: $e');
  }
  StartupProfiler.mark('cache_check');

  await StartupProfiler.reportAll();

  runApp(const ProviderScope(child: XtremFlowApp()));
}

class XtremFlowApp extends ConsumerWidget {
  const XtremFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeProvider);

    return MaterialApp(
      title: 'XtremFlow IPTV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeState.themeMode,
      // Start directly at playlist selection (no auth)
      home: const MobilePlaylistScreen(),
      onGenerateRoute: (settings) {
        // Handle navigation to dashboard with playlist
        if (settings.name == '/dashboard') {
          final playlist = settings.arguments as PlaylistConfig?;
          if (playlist != null) {
            return MaterialPageRoute(
              builder: (context) => MobileDashboardScreen(playlist: playlist),
            );
          }
        }
        return null;
      },
    );
  }
}

