import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../core/models/playlist_config.dart';

/// Local playlist storage service for mobile
/// Uses Hive for persistent local storage
class LocalPlaylistService {
  static const String _boxName = 'playlists_mobile';
  Box<PlaylistConfig>? _box;

  /// Initialize the service and open the Hive box
  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    
    // Register adapter if not already registered
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(PlaylistConfigAdapter());
    }
    
    _box = await Hive.openBox<PlaylistConfig>(_boxName);
  }

  /// Get all playlists
  Future<List<PlaylistConfig>> getPlaylists() async {
    await init();
    return _box!.values.toList();
  }

  /// Add a new playlist
  Future<PlaylistConfig> addPlaylist({
    required String name,
    required String dns,
    required String username,
    required String password,
  }) async {
    await init();
    
    final playlist = PlaylistConfig(
      id: const Uuid().v4(),
      name: name,
      dns: dns.endsWith('/') ? dns.substring(0, dns.length - 1) : dns,
      username: username,
      password: password,
      createdAt: DateTime.now(),
    );
    
    await _box!.put(playlist.id, playlist);
    return playlist;
  }

  /// Update an existing playlist
  Future<PlaylistConfig?> updatePlaylist({
    required String id,
    required String name,
    required String dns,
    required String username,
    required String password,
  }) async {
    await init();
    
    final existing = _box!.get(id);
    if (existing == null) return null;
    
    final updated = existing.copyWith(
      name: name,
      dns: dns.endsWith('/') ? dns.substring(0, dns.length - 1) : dns,
      username: username,
      password: password,
    );
    
    await _box!.put(id, updated);
    return updated;
  }

  /// Delete a playlist
  Future<bool> deletePlaylist(String id) async {
    await init();
    await _box!.delete(id);
    return true;
  }

  /// Get a single playlist by ID
  Future<PlaylistConfig?> getPlaylist(String id) async {
    await init();
    return _box!.get(id);
  }

  /// Close the box when done
  Future<void> dispose() async {
    await _box?.close();
  }
}
