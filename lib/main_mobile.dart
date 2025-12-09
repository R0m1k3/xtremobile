import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'mobile/features/iptv/screens/mobile_playlist_screen.dart';
import 'mobile/features/iptv/screens/mobile_dashboard_screen.dart';
import 'core/models/playlist_config.dart';

/// Mobile-optimized entry point for XtremFlow IPTV
/// No authentication - direct access to playlist selection
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive for local storage
  await Hive.initFlutter();
  
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

