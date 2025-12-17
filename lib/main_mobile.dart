import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'mobile/features/iptv/screens/mobile_playlist_screen.dart';
import 'mobile/features/iptv/screens/mobile_dashboard_screen.dart';
import 'core/models/playlist_config.dart';

/// Mobile-optimized entry point for XtremFlow IPTV
/// No authentication - direct access to playlist selection
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize MediaKit (required for video playback)
  MediaKit.ensureInitialized();

  // Initialize Hive for local storage
  await Hive.initFlutter();

  // CLEAR CACHE ON STARTUP (Requested by User)
  try {
    // Clear API/EPG Cache (using default box name 'dio_cache')
    await Hive.deleteBoxFromDisk('dio_cache');
    debugPrint('XtremFlow: API Cache cleared');

    // Clear Image Cache (if using cached_network_image)
    // Note: flutter_cache_manager needs to be imported if used explicitly,
    // but typically it manages itself. If we want to force clear:
    // await DefaultCacheManager().emptyCache();
    // Since we didn't add the import yet, we'll stick to Hive for now as that handles EPG/API.
  } catch (e) {
    debugPrint('XtremFlow: Failed to clear cache: $e');
  }

  // Register adapters for Hive
  if (!Hive.isAdapterRegistered(1)) {
    Hive.registerAdapter(PlaylistConfigAdapter());
  }

  runApp(const ProviderScope(child: MobileApp()));
}

class MobileApp extends ConsumerWidget {
  const MobileApp({super.key});

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
