import 'package:uuid/uuid.dart';
import '../database/hive_service.dart';
import '../models/playlist_config.dart';

/// Service for managing playlists via local storage (Hive)
class PlaylistApiService {
  /// Get all playlists for current user
  Future<List<PlaylistConfig>> getPlaylists() async {
    try {
      if (!HiveService.playlistsBox.isOpen) {
        await HiveService.init();
      }
      return HiveService.playlistsBox.values.toList();
    } catch (e) {
      print('Error fetching playlists from Hive: $e');
      return [];
    }
  }

  /// Create a new playlist
  Future<PlaylistConfig?> createPlaylist({
    required String name,
    required String dns,
    required String username,
    required String password,
  }) async {
    try {
      final id = const Uuid().v4();
      final playlist = PlaylistConfig(
        id: id,
        name: name,
        dns: dns,
        username: username,
        password: password,
        createdAt: DateTime.now(),
      );

      await HiveService.playlistsBox.put(id, playlist);
      return playlist;
    } catch (e) {
      print('Error creating playlist in Hive: $e');
      return null;
    }
  }

  /// Update a playlist
  Future<PlaylistConfig?> updatePlaylist({
    required String id,
    required String name,
    required String dns,
    required String username,
    required String password,
  }) async {
    try {
      if (!HiveService.playlistsBox.containsKey(id)) {
        return null;
      }

      final existing = HiveService.playlistsBox.get(id);
      if (existing == null) return null;

      final updated = PlaylistConfig(
        id: id,
        name: name,
        dns: dns,
        username: username,
        password: password,
        createdAt: existing.createdAt,
      );

      await HiveService.playlistsBox.put(id, updated);
      return updated;
    } catch (e) {
      print('Error updating playlist in Hive: $e');
      return null;
    }
  }

  /// Delete a playlist
  Future<bool> deletePlaylist(String id) async {
    try {
      await HiveService.playlistsBox.delete(id);
      return true;
    } catch (e) {
      print('Error deleting playlist from Hive: $e');
      return false;
    }
  }
}
