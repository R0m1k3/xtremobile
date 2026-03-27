import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Video player selection and wrapper pattern
/// Abstracts between MediaKit and other video players
/// Handles fallback logic and player initialization
/// Enum for supported players
enum PlayerType { mediakit, native }

/// Video player selection and wrapper pattern
/// Abstracts between MediaKit and other video players
/// Handles fallback logic and player initialization
class VideoPlayerWrapper {
  static const _availablePlayers = ['mediakit'];

  /// Get the preferred player type based on stream and platform
  static PlayerType getPreferredPlayer({
    required String streamUrl,
    required String? codec,
    bool preferLite = false,
  }) {
    // Priority: MediaKit for most cases
    // Could add fallback logic here based on codec, bitrate, etc.
    return PlayerType.mediakit;
  }

  /// Validate stream URL and get playable format
  static String? validateAndGetPlayableUrl(String streamUrl) {
    try {
      if (streamUrl.isEmpty) return null;

      // Check for common URL patterns
      if (streamUrl.startsWith('http://') || streamUrl.startsWith('https://')) {
        return streamUrl;
      }

      // Handle m3u playlist entries
      if (streamUrl.startsWith('#EXTINF')) {
        return null; // Invalid - should be extracted from m3u
      }

      return streamUrl;
    } catch (e) {
      debugPrint('❌ Error validating URL: $e');
      return null;
    }
  }

  /// Create media player with standard settings
  static Player createPlayer({
    bool enableLogs = false,
  }) {
    final player = Player(
      configuration: PlayerConfiguration(
        logLevel: enableLogs ? MPVLogLevel.debug : MPVLogLevel.error,
      ),
    );
    return player;
  }

  /// Validate codec support
  static bool isCodecSupported(String? codec) {
    if (codec == null) return true; // Unknown codecs are attempted anyway

    final supportedCodecs = {
      'h264',
      'hevc',
      'h265',
      'mpeg2video',
      'mpeg1video',
      'vp8',
      'vp9',
      'av1',
    };

    return supportedCodecs.contains(codec.toLowerCase());
  }

  /// Get player-specific error message
  static String getPlayerErrorMessage(String error, PlayerType playerType) {
    return switch (playerType) {
      PlayerType.mediakit => _getMediaKitError(error),
      PlayerType.native => _getNativePlayerError(error),
    };
  }

  static String _getMediaKitError(String error) {
    if (error.contains('Network')) return 'Stream connection failed';
    if (error.contains('Timeout')) return 'Stream took too long to load';
    if (error.contains('Codec')) return 'Video codec not supported';
    return 'Playback error: $error';
  }

  static String _getNativePlayerError(String error) {
    if (error.contains('Network')) return 'Connection lost';
    return 'Player error: $error';
  }
}
