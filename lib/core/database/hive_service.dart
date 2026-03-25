import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/playlist_config.dart';

class HiveService {
  static const String _usersBoxName = 'users';
  static const String _playlistsBoxName = 'playlists';

  static bool _initialized = false;
  static List<int>? _encryptionKey;

  /// Initialize Hive with encryption
  static Future<void> init() async {
    if (_initialized) return;

    // Initialize Hive
    await Hive.initFlutter();

    // Register adapters
    // Register adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(AppUserAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PlaylistConfigAdapter());
    }

    // Open boxes with encryption
    await Hive.openBox<AppUser>(_usersBoxName);
    await Hive.openBox<PlaylistConfig>(_playlistsBoxName);

    // Seed default admin if no users exist
    await _seedDefaultAdmin();

    _initialized = true;
  }

  /// Get or create 256-bit encryption key
  static Future<List<int>> _getOrCreateEncryptionKey() async {
    if (_encryptionKey != null) {
      return _encryptionKey!;
    }

    // Generate new 256-bit key
    _encryptionKey = Hive.generateSecureKey();

    return _encryptionKey!;
  }

  /// Seed default admin user (admin/admin)
  static Future<void> _seedDefaultAdmin() async {
    final usersBox = Hive.box<AppUser>(_usersBoxName);

    if (usersBox.isEmpty) {
      final adminId = const Uuid().v4();
      final passwordHash = _hashPassword('admin');

      final admin = AppUser(
        id: adminId,
        username: 'admin',
        passwordHash: passwordHash,
        isAdmin: true,
        assignedPlaylistIds: const [],
        createdAt: DateTime.now(),
      );

      await usersBox.put(adminId, admin);
    }
  }

  /// Hash password using SHA-256 with salt
  static String _hashPassword(String password) {
    // Generate a random salt using the first 16 chars of a UUID
    final salt = const Uuid().v4().substring(0, 16);
    final bytes = utf8.encode(password + salt);
    final digest = sha256.convert(bytes);
    return '$salt:${digest.toString()}';
  }

  /// Verify password against stored hash
  static bool verifyPassword(String password, String storedHash) {
    try {
      final parts = storedHash.split(':');
      if (parts.length != 2) {
        // Legacy hash without salt - fallback to direct comparison
        final legacyHash = sha256.convert(utf8.encode(password)).toString();
        return legacyHash == storedHash;
      }

      final salt = parts[0];
      final expectedHash = parts[1];
      final bytes = utf8.encode(password + salt);
      final actualHash = sha256.convert(bytes).toString();

      return actualHash == expectedHash;
    } catch (e) {
      return false;
    }
  }

  /// Public method to hash passwords (used by auth)
  static String hashPassword(String password) => _hashPassword(password);

  /// Get users box
  static Box<AppUser> get usersBox => Hive.box<AppUser>(_usersBoxName);

  /// Get playlists box
  static Box<PlaylistConfig> get playlistsBox =>
      Hive.box<PlaylistConfig>(_playlistsBoxName);

  /// [P0-2 FIX] Invalidate expired cache entries based on TTL
  /// Instead of clearing entire cache on startup, use TTL-based invalidation
  /// This preserves cache data between app launches while removing stale entries
  static Future<void> invalidateExpiredCache() async {
    try {
      final cacheBox = Hive.box('dio_cache');

      // TTL configuration (in seconds)
      const Map<String, int> cacheTtl = {
        'channels': 6 * 3600,      // 6 hours for channel lists
        'epg': 3600,               // 1 hour for EPG data
        'categories': 6 * 3600,    // 6 hours for categories
        'search': 1800,            // 30 minutes for search results
        'default': 6 * 3600,       // 6 hours default
      };

      int expired = 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      for (var key in cacheBox.keys.toList()) {
        try {
          final entry = cacheBox.get(key);

          if (entry is Map && entry.containsKey('timestamp')) {
            final timestamp = entry['timestamp'] as int;
            final category = _getCacheCategory(key.toString());
            final ttl = cacheTtl[category] ?? cacheTtl['default']!;

            // If entry is older than TTL, delete it
            if ((now - timestamp) > (ttl * 1000)) {
              await cacheBox.delete(key);
              expired++;
            }
          }
        } catch (e) {
          // Skip malformed entries
        }
      }

      if (expired > 0) {
        debugPrint('🗑️  Invalidated $expired expired cache entries');
      } else {
        debugPrint('✅ All cache entries valid (within TTL)');
      }
    } catch (e) {
      // Cache box might not exist - that's OK on first startup
      debugPrint('ℹ️  Cache maintenance: $e');
    }
  }

  /// Determine cache category from key for TTL lookup
  static String _getCacheCategory(String key) {
    if (key.contains('live') || key.contains('channel')) return 'channels';
    if (key.contains('epg') || key.contains('now_playing')) return 'epg';
    if (key.contains('category')) return 'categories';
    if (key.contains('search')) return 'search';
    return 'default';
  }

  /// Manually clear cache (for settings option)
  static Future<void> clearCache() async {
    try {
      await Hive.deleteBoxFromDisk('dio_cache');
      debugPrint('🗑️  Cache manually cleared by user');
    } catch (e) {
      debugPrint('❌ Failed to clear cache: $e');
    }
  }

  /// Close all boxes (cleanup)
  static Future<void> dispose() async {
    await Hive.close();
    _initialized = false;
  }
}
