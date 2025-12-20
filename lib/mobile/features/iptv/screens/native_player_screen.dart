import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xtremflow/mobile/widgets/tv_focusable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xtremflow/core/models/iptv_models.dart';
import 'package:xtremflow/core/models/playlist_config.dart';
import 'package:xtremflow/features/iptv/services/xtream_service_mobile.dart';
import 'package:xtremflow/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/mobile/providers/mobile_xtream_providers.dart';

/// Stream type enum for player
enum StreamType { live, vod, series }

/// Native video player screen for Android/iOS
/// Uses media_kit (FFmpeg) for full codec support (AC3, EAC3, DTS, etc.)
class NativePlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final StreamType streamType;
  final String? containerExtension;
  final PlaylistConfig playlist;
  final List<Channel>? channels;
  final int initialIndex;

  // For series episodes (to track watch history)
  final dynamic seriesId;
  final int? season;
  final int? episodeNum;

  const NativePlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    required this.streamType,
    this.containerExtension,
    this.channels,
    this.initialIndex = 0,
    this.initialPosition,
    this.seriesId,
    this.season,
    this.episodeNum,
  });

  final Duration? initialPosition;

  @override
  ConsumerState<NativePlayerScreen> createState() => _NativePlayerScreenState();
}

class _NativePlayerScreenState extends ConsumerState<NativePlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;

  // Focus Nodes
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _prevFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();
  final FocusNode _backFocusNode = FocusNode();
  final FocusNode _audioFocusNode = FocusNode();

  bool _isLoading = true;
  String? _errorMessage;
  late int _currentIndex;
  XtreamServiceMobile? _xtreamService;
  bool _showControls = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSeeking = false;
  bool _useSoftwareDecoder = false;

  Timer? _clockTimer;
  Timer? _controlsTimer; // Auto-hide timer
  Timer? _liveWatchdog; // Watchdog for live stream reconnection
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  String _currentTime = '';
  bool _hasMarkedAsWatched = false; // Flag to mark watched only once at 80%
  DateTime? _lastSaveTime; // For throttling position saves

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    _startClock(); // Ensure clock runs when controls are shown
    if (_showControls && _isPlaying) {
      _controlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _showControls = false);
          _stopClock(); // Save CPU when hidden
        }
      });
    }
  }

  void _onUserInteraction() {
    setState(() => _showControls = true);
    _resetControlsTimer();
  }

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Register keyboard handler for remote control
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    // Enable wakelock to prevent screen from turning off during playback
    WakelockPlus.enable();

    // Only start clock if setting is enabled (will check in build too, but timer can run)
    _startClock();
    _currentIndex = widget.initialIndex;

    // Initialize media_kit player with potential software decoding fallback
    // 'hwdec': 'auto' tries hardware first, then software.
    // 'vo': 'gpu' is standard.
    const config = PlayerConfiguration(
      vo: 'gpu',
      // msgLevel removed as it might be deprecated or invalid
    );
    // Create the player instance
    _player = Player(configuration: config);

    // Enable software decoding fallback if hardware fails (handled by mpv usually, but ensuring 'auto' helps)
    final decoderMode = ref.read(mobileSettingsProvider).decoderMode;
    final deinterlace = ref.read(mobileSettingsProvider).deinterlace;
    (_player.platform as dynamic)?.setProperty('hwdec', decoderMode);
    (_player.platform as dynamic)
        ?.setProperty('deinterlace', deinterlace ? 'yes' : 'no');

    // Performance & Scaling Fixes for Android
    (_player.platform as dynamic)?.setProperty('opengl-pbo', 'yes');
    (_player.platform as dynamic)?.setProperty('video-unscaled', 'no');
    debugPrint(
        'MediaKitPlayer: Decoder Mode set to $decoderMode, Deinterlace: $deinterlace');

    // ============ PERFORMANCE 3.0 (ANTI MICRO-COUPURE PROFILE) ============
    // Tuned to eliminate micro-stuttering during live TV playback
    // Increased buffers for smoother playback at cost of ~100MB RAM

    // Unified Buffering Logic (Live vs VOD)
    (_player.platform as dynamic)?.setProperty('cache', 'yes');

    if (widget.streamType == StreamType.live) {
      // LIVE PROFILE: Faster startup, lower latency, smaller buffer
      debugPrint('MediaKitPlayer: Applying LIVE optimization profile');
      (_player.platform as dynamic)?.setProperty('cache-secs', '30');
      (_player.platform as dynamic)
          ?.setProperty('demuxer-max-bytes', '32000000'); // 32MB
      (_player.platform as dynamic)
          ?.setProperty('demuxer-readahead-secs', '20');
      (_player.platform as dynamic)
          ?.setProperty('demuxer-max-back-bytes', '10000000'); // 10MB back

      // Start playing as soon as possible, don't wait for cache fill
      (_player.platform as dynamic)?.setProperty('cache-pause-initial', 'no');
    } else {
      // VOD PROFILE: Max stability, large buffer
      debugPrint('MediaKitPlayer: Applying VOD optimization profile');
      (_player.platform as dynamic)?.setProperty('cache-secs', '120');
      (_player.platform as dynamic)
          ?.setProperty('demuxer-max-bytes', '100000000'); // 100MB
      (_player.platform as dynamic)
          ?.setProperty('demuxer-readahead-secs', '120');
      (_player.platform as dynamic)
          ?.setProperty('demuxer-max-back-bytes', '20000000'); // 20MB back

      // Wait a bit to fill buffer for smooth playback
      (_player.platform as dynamic)?.setProperty('cache-pause-initial', 'yes');
      (_player.platform as dynamic)?.setProperty('cache-pause-wait', '5');
    }

    // Audio/Video Sync - critical for smooth playback
    (_player.platform as dynamic)
        ?.setProperty('video-sync', 'display-resample'); // Better A/V sync
    (_player.platform as dynamic)
        ?.setProperty('interpolation', 'no'); // Keep off for safety
    (_player.platform as dynamic)
        ?.setProperty('audio-buffer', '1.0'); // Larger audio buffer (1 second)
    (_player.platform as dynamic)
        ?.setProperty('audio-samplerate', '48000'); // Standard high quality

    // Network resilience - more aggressive settings
    (_player.platform as dynamic)?.setProperty('network-timeout', '120');
    (_player.platform as dynamic)?.setProperty('stream-timeout', '120');
    (_player.platform as dynamic)?.setProperty('tls-verify', 'no');
    (_player.platform as dynamic)
        ?.setProperty('http-header-fields', 'User-Agent: XtremFlow/1.0');

    // Live Stream optimizations - aggressive reconnection
    (_player.platform as dynamic)?.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=10,reconnect_on_http_error=4xx,5xx',
    );
    (_player.platform as dynamic)?.setProperty('force-seekable', 'yes');
    (_player.platform as dynamic)?.setProperty(
      'demuxer-lavf-o',
      'live_start_index=-1,analyzeduration=10000000,probesize=5000000',
    );

    // Prevent stalls (readahead already set above)
    (_player.platform as dynamic)?.setProperty('hr-seek', 'yes');
    (_player.platform as dynamic)?.setProperty('hr-seek-framedrop', 'yes');
    (_player.platform as dynamic)
        ?.setProperty('vd-lavc-dr', 'yes'); // Direct rendering
    (_player.platform as dynamic)
        ?.setProperty('vd-lavc-fast', 'yes'); // Fast decoding
    (_player.platform as dynamic)
        ?.setProperty('vd-lavc-threads', '4'); // Multithreading
    (_player.platform as dynamic)?.setProperty(
        'vd-lavc-skiploopfilter', 'all'); // Skip loop filter for performance

    // ============ AUDIO CODEC SUPPORT FOR VOD ============
    // V3: Explicit LAVC Downmix & Audiotrack

    // Ensure audio is NOT muted
    (_player.platform as dynamic)?.setProperty('mute', 'no');

    // Explicitly enable LAVC downmixing to stereo (Crucial for 5.1/7.1 on Stereo devices)
    (_player.platform as dynamic)?.setProperty('ad-lavc-downmix', 'yes');
    (_player.platform as dynamic)?.setProperty('audio-channels', 'stereo');
    (_player.platform as dynamic)
        ?.setProperty('audio-normalize-downmix', 'yes');

    // Force software decoding for audio tracks (Maximum compatibility)
    (_player.platform as dynamic)?.setProperty('ad', 'lavc:*');

    // Use audiotrack (standard Android)
    (_player.platform as dynamic)?.setProperty('ao', 'audiotrack');

    // Track Selection - Auto
    (_player.platform as dynamic)?.setProperty('aid', 'auto');
    (_player.platform as dynamic)?.setProperty('alang', 'fr,fra,fre,en,eng');

    // Volume & Sync
    (_player.platform as dynamic)?.setProperty('volume', '100');
    // Slightly larger buffer for software decoding
    (_player.platform as dynamic)?.setProperty('audio-buffer', '0.25');
    (_player.platform as dynamic)?.setProperty('video-sync', 'audio');

    debugPrint('MediaKitPlayer: Audio V3 (Downmix) configuration applied');

    _controller = VideoController(_player);

    // Listen to player state
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
        if (playing) {
          // Smooth Loading: Hide loading screen 1s AFTER playback actually starts
          // This masks initial glitches/re-buffering
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted && _isPlaying) {
              setState(() => _isLoading = false);
            }
          });
          _resetControlsTimer(); // Start auto-hide timer
        }
      }
    });

    _player.stream.position.listen((position) {
      if (mounted && !_isSeeking) {
        setState(() => _position = position);

        // Check if 80% of content watched (for VOD/Series only)
        _checkAndMarkWatched(position);

        // Auto-save position every 10 seconds (resilience against app kill/crash)
        if (widget.streamType != StreamType.live && !_hasMarkedAsWatched) {
          final now = DateTime.now();
          if (_lastSaveTime == null ||
              now.difference(_lastSaveTime!) > const Duration(seconds: 10)) {
            _lastSaveTime = now;
            // Don't save if < 30s or > 95%
            if (position.inSeconds > 30 &&
                _duration.inSeconds > 0 &&
                position.inSeconds / _duration.inSeconds < 0.95) {
              ref
                  .read(mobileWatchHistoryProvider.notifier)
                  .saveResumePosition(_contentId, position.inSeconds);
            }
          }
        }
      }
    });

    _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });

    _player.stream.error.listen((error) async {
      if (!mounted) return;

      // Filter out non-errors or non-fatal messages if necessary
      if (error.isEmpty) return;

      debugPrint('MediaKitPlayer Error Stream: $error');

      // Smart Retry for Codec/Decoder errors
      // If we haven't tried SW decoding yet, retry with it enabled.
      if (!_useSoftwareDecoder) {
        debugPrint(
          'MediaKitPlayer: Error encountered. Auto-retrying with Software Decoding...',
        );
        setState(() => _useSoftwareDecoder = true);

        // Short delay to allow player cleanup
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) _loadStream(); // Retry connection
        return;
      }

      // If SW decoding was already on or failed too, show error
      setState(() {
        _errorMessage = error;
        _isLoading = false;
      });
    });

    // Listen for stream completion (live streams shouldn't complete - means it stopped)
    _player.stream.completed.listen((completed) {
      if (completed && mounted && widget.streamType == StreamType.live) {
        debugPrint(
          'MediaKitPlayer: Live stream completed unexpectedly, attempting reconnect...',
        );
        _attemptReconnect();
      }
    });

    // Lock to landscape for video playback
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Initialize service and then player
    _initializeServiceAndPlayer();
  }

  void _startClock() {
    if (_clockTimer != null && _clockTimer!.isActive) return;
    _updateTime();
    _clockTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _stopClock() {
    _clockTimer?.cancel();
    _clockTimer = null;
  }

  void _updateTime() {
    if (mounted) {
      final now = DateTime.now();
      setState(() {
        _currentTime =
            "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      });
    }
  }

  @override
  void deactivate() {
    // Stop player when widget is being removed from tree
    _player.stop();
    super.deactivate();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Unregister keyboard handler
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);

    // Disable wakelock when leaving player
    WakelockPlus.disable();

    // Save resume position before cleanup (only for VOD/Series)
    _saveResumePositionOnExit();

    _clockTimer?.cancel();
    _controlsTimer?.cancel();
    _liveWatchdog?.cancel();

    // Stop playback first to prevent audio continuing in background
    _player.stop();
    _player.dispose();
    _xtreamService?.dispose();

    // Restore normal orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Dispose focus nodes
    _playPauseFocusNode.dispose();
    _prevFocusNode.dispose();
    _nextFocusNode.dispose();
    _backFocusNode.dispose();

    super.dispose();
  }

  /// Get content ID for resume position storage
  String get _contentId {
    if (widget.streamType == StreamType.series &&
        widget.seriesId != null &&
        widget.season != null &&
        widget.episodeNum != null) {
      return MobileWatchHistory.episodeKey(
        widget.seriesId,
        widget.season!,
        widget.episodeNum!,
      );
    }
    return widget.streamId;
  }

  /// Save resume position when exiting player
  void _saveResumePositionOnExit() {
    if (widget.streamType == StreamType.live) return;

    debugPrint(
      'MediaKitPlayer: Saving position - pos: ${_position.inSeconds}s, dur: ${_duration.inSeconds}s, contentId: $_contentId',
    );

    // If already marked as watched, clear any saved position
    if (_hasMarkedAsWatched) {
      ref
          .read(mobileWatchHistoryProvider.notifier)
          .clearResumePosition(_contentId);
      debugPrint('MediaKitPlayer: Already watched, clearing position');
      return;
    }

    // Check if almost finished (> 90%)
    if (_duration.inSeconds > 0) {
      final progress = _position.inSeconds / _duration.inSeconds;
      if (progress > 0.90) {
        ref
            .read(mobileWatchHistoryProvider.notifier)
            .clearResumePosition(_contentId);
        debugPrint(
          'MediaKitPlayer: Almost finished (${(progress * 100).toStringAsFixed(1)}%), clearing position',
        );
        return;
      }
    }

    // Save position (saveResumePosition handles the 30s minimum check)
    ref.read(mobileWatchHistoryProvider.notifier).saveResumePosition(
          _contentId,
          _position.inSeconds,
        );
  }

  /// Seek to resume position with retry logic
  void _seekToResume(int positionSeconds, [int attempt = 0]) {
    if (!mounted || attempt >= 10) return;

    Future.delayed(Duration(milliseconds: attempt == 0 ? 1500 : 500), () {
      if (!mounted) return;

      if (_isPlaying && _duration.inSeconds > 0) {
        debugPrint(
          'MediaKitPlayer: Seeking to resume position ${positionSeconds}s (attempt $attempt)',
        );
        _player.seek(Duration(seconds: positionSeconds));

        // Show visual notification
        final minutes = positionSeconds ~/ 60;
        final seconds = positionSeconds % 60;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reprise à ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green.shade700,
          ),
        );
      } else {
        debugPrint(
          'MediaKitPlayer: Player not ready, retrying resume seek (attempt $attempt)',
        );
        _seekToResume(positionSeconds, attempt + 1);
      }
    });
  }

  /// Attempt to reconnect a live stream that stopped
  void _attemptReconnect() {
    if (!mounted) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      setState(() {
        _errorMessage = 'Flux interrompu après plusieurs tentatives';
        _isLoading = false;
      });
      return;
    }

    _reconnectAttempts++;
    debugPrint(
      'MediaKitPlayer: Reconnect attempt $_reconnectAttempts/$_maxReconnectAttempts',
    );

    // Delay before reconnect to avoid hammering the server
    Future.delayed(Duration(seconds: 2 * _reconnectAttempts), () {
      if (mounted) {
        _loadStream();
      }
    });
  }

  /// Check if 80% of content watched and mark as watched
  void _checkAndMarkWatched(Duration position) {
    // Skip if already marked, live TV, or no duration
    if (_hasMarkedAsWatched) return;
    if (widget.streamType == StreamType.live) return;
    if (_duration.inSeconds <= 0) return;

    final progress = position.inSeconds / _duration.inSeconds;

    if (progress >= 0.80) {
      _hasMarkedAsWatched = true;
      debugPrint('MediaKitPlayer: 80% reached, marking as watched');

      if (widget.streamType == StreamType.vod) {
        // Mark movie as watched
        ref
            .read(mobileWatchHistoryProvider.notifier)
            .markMovieWatched(widget.streamId);
      } else if (widget.streamType == StreamType.series &&
          widget.seriesId != null &&
          widget.season != null &&
          widget.episodeNum != null) {
        // Mark episode as watched
        final episodeKey = MobileWatchHistory.episodeKey(
          widget.seriesId,
          widget.season!,
          widget.episodeNum!,
        );
        ref
            .read(mobileWatchHistoryProvider.notifier)
            .markEpisodeWatched(episodeKey);
      }
    }
  }

  /// Start watchdog timer for live streams
  void _startLiveWatchdog() {
    _liveWatchdog?.cancel();
    if (widget.streamType != StreamType.live) return;

    // Check every 30 seconds if stream is still playing
    _liveWatchdog = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;

      // If we're supposedly playing but position hasn't changed, reconnect
      if (!_isPlaying && !_isLoading && _errorMessage == null) {
        debugPrint(
          'MediaKitPlayer: Watchdog detected stalled stream, reconnecting...',
        );
        _attemptReconnect();
      }
    });
  }

  // Update build method to show clock in top bar
  // ...

  Future<void> _initializeServiceAndPlayer() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _xtreamService = XtreamServiceMobile(dir.path);
      await _xtreamService!.setPlaylistAsync(widget.playlist);

      await _loadStream();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Service Error: $e";
        });
      }
    }
  }

  ShortEPG? _epg;

  // ... (existing initState)

  Future<void> _loadStream() async {
    try {
      if (_xtreamService == null) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _epg = null; // Reset EPG
      });

      // Determine effective Stream ID
      final currentStreamId =
          widget.channels != null && widget.channels!.isNotEmpty
              ? widget.channels![_currentIndex].streamId
              : widget.streamId;

      // Load EPG if Live TV
      if (widget.streamType == StreamType.live) {
        _loadEpg(currentStreamId);
      }

      // ... (rest of _loadStream logic: get url, open player)
      // Build stream URL based on type
      String streamUrl;

      if (widget.streamType == StreamType.live) {
        streamUrl = _xtreamService!.getLiveStreamUrl(currentStreamId);
      } else if (widget.streamType == StreamType.vod) {
        streamUrl = _xtreamService!.getVodStreamUrl(
          currentStreamId,
          widget.containerExtension ?? 'mp4',
        );
      } else {
        streamUrl = _xtreamService!.getSeriesStreamUrl(
          currentStreamId,
          widget.containerExtension ?? 'mp4',
        );
      }

      debugPrint('MediaKitPlayer: Loading stream: $streamUrl');

      // Enable software decoding fallback if hardware fails (handled by mpv usually, but ensuring 'auto' helps)
      // If we are in fallback mode, force software ('no')
      String hwdecValue;
      if (_useSoftwareDecoder) {
        hwdecValue = 'no';
      } else {
        hwdecValue = ref.read(mobileSettingsProvider).decoderMode;
      }
      (_player.platform as dynamic)?.setProperty('hwdec', hwdecValue);

      await _player.open(
        Media(streamUrl, httpHeaders: {'User-Agent': 'XtremFlow/1.0'}),
        play: true,
      );

      setState(() {
        _isLoading = false;
        _reconnectAttempts = 0; // Reset reconnect counter on success
      });

      // Start watchdog for live streams
      if (widget.streamType == StreamType.live) {
        _startLiveWatchdog();
      }

      // Resume from saved position (VOD/Series only)
      if (widget.streamType != StreamType.live) {
        // Priority 1: Explicit initial position passed from caller verification
        if (widget.initialPosition != null &&
            widget.initialPosition!.inSeconds > 0) {
          debugPrint(
            'MediaKitPlayer: Using explicit initial position: ${widget.initialPosition!.inSeconds}s',
          );
          _seekToResume(widget.initialPosition!.inSeconds);
        } else {
          // Priority 2: Internal lookup (fallback)
          final resumePos = ref
              .read(mobileWatchHistoryProvider)
              .getResumePosition(_contentId);
          debugPrint(
            'MediaKitPlayer: Resume check - contentId: $_contentId, resumePos: $resumePos',
          );
          if (resumePos > 30) {
            _seekToResume(resumePos);
          }
        }
      }
    } catch (e) {
      debugPrint('MediaKitPlayer error: $e');

      // Automatic Retry with Software Decoding if it fails the first time
      if (!_useSoftwareDecoder) {
        debugPrint('MediaKitPlayer: Retrying with Software Decoding forced...');
        setState(() {
          _useSoftwareDecoder = true;
          // _isLoading remains true
        });
        // Delay slightly to let player reset state if needed
        await Future.delayed(const Duration(milliseconds: 500));
        _loadStream(); // Recursive retry
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadEpg(String streamId) async {
    try {
      final epg = await _xtreamService!.getShortEPG(streamId);
      if (mounted) {
        setState(() => _epg = epg);
      }
    } catch (e) {
      debugPrint('Error loading EPG: $e');
    }
  }

  void _playNext() {
    if (widget.channels == null || widget.channels!.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % widget.channels!.length;
    _switchChannel(nextIndex);
  }

  void _playPrevious() {
    if (widget.channels == null || widget.channels!.isEmpty) return;
    final prevIndex =
        (_currentIndex - 1 + widget.channels!.length) % widget.channels!.length;
    _switchChannel(prevIndex);
  }

  void _switchChannel(int index) {
    setState(() {
      _currentIndex = index;
    });
    _loadStream();
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
      // Save position on pause
      if (widget.streamType != StreamType.live) {
        ref
            .read(mobileWatchHistoryProvider.notifier)
            .saveResumePosition(_contentId, _position.inSeconds);
      }
    } else {
      _player.play();
    }
    _onUserInteraction();
  }

  void _toggleControls() {
    // Always show controls on tap, then start auto-hide timer
    if (!_showControls) {
      setState(() => _showControls = true);
      // Request focus on Play/Pause button when opening
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // If controls opened, default to Play/Pause
        _playPauseFocusNode.requestFocus();
      });
    }
    _resetControlsTimer();
  }

  /// Handle keyboard/remote control events
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final key = event.logicalKey;

    // Space / Enter / Select
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      // If controls are hidden, toggle them + play/pause
      if (!_showControls) {
        _togglePlayPause();
        _toggleControls();
        return true;
      }
      // If controls are visible, let Focus system handle button press
      return false;
    }

    // Debug Toggle: Long Press Key 'D' or 0 (if mapped) - Simplified to just a secret key combo?
    // Let's use a long-press logic on Select in _handleKeyEvent?
    // Actually, handling long press in key down is hard.
    // We'll add a 'Debug' button in the settings or just map Key '0' if remote has it.
    // Debug Toggle: Long Press Key 'D' or 0 (if mapped)
    if (key == LogicalKeyboardKey.digit0) {
      final current = ref.read(mobileSettingsProvider).showDebugStats;
      ref.read(mobileSettingsProvider.notifier).toggleShowDebugStats(!current);
      return true;
    }

    // Left Arrow - Seek back 10 seconds
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (_showControls) return false; // Let Focus handle navigation

      if (widget.streamType != StreamType.live) {
        final newPos = _position - const Duration(seconds: 5);
        _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
        _onUserInteraction();
      }
      return true;
    }

    // Right Arrow - Seek forward 10 seconds
    if (key == LogicalKeyboardKey.arrowRight) {
      if (_showControls) return false; // Let Focus handle navigation

      if (widget.streamType != StreamType.live) {
        final newPos = _position + const Duration(seconds: 5);
        if (newPos < _duration) {
          _player.seek(newPos);
        }
        _onUserInteraction();
      }
      return true;
    }

    // Up Arrow - Previous channel (Live only)
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.channelUp) {
      if (widget.streamType == StreamType.live && widget.channels != null) {
        if (key == LogicalKeyboardKey.channelUp || !_showControls) {
          _playPrevious();
          return true;
        }
      }
      return false; // Let focus handle navigation if controls shown
    }

    // Down Arrow - Next channel (Live) or Cycle Audio (VOD)
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.channelDown) {
      if (widget.streamType == StreamType.live && widget.channels != null) {
        if (key == LogicalKeyboardKey.channelDown || !_showControls) {
          _playNext();
          return true;
        }
      } else if (widget.streamType != StreamType.live &&
          key == LogicalKeyboardKey.arrowDown) {
        _cycleAudioTrack();
        return true;
      }
      return false; // Let focus handle navigation if controls shown
    }

    // Cycle Aspect Ratio - secret key 'A' or digit 1
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.digit1) {
      _cycleAspectRatio();
      return true;
    }

    // Escape / Back - Exit player
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      // If controls are visible, close them first
      if (_showControls) {
        setState(() => _showControls = false);
      } else {
        Navigator.of(context).pop();
      }
      return true;
    }

    return false;
  }

  Future<void> _cycleAudioTrack() async {
    final tracks = _player.state.tracks.audio;
    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucune piste audio détectée'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    final current = _player.state.track.audio;
    int currentIndex = tracks.indexOf(current);
    int nextIndex = (currentIndex + 1) % tracks.length;
    final nextTrack = tracks[nextIndex];

    await _player.setAudioTrack(nextTrack);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Audio: ${nextTrack.language ?? "inconnu"} (${nextTrack.title ?? nextTrack.id})',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.channels != null && widget.channels!.isNotEmpty
        ? widget.channels![_currentIndex].name
        : widget.title;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onPanDown: (_) => _onUserInteraction(),
        onPanUpdate: (_) => _onUserInteraction(),
        child: Stack(
          children: [
            // Video Player
            if (_errorMessage != null)
              _buildErrorView()
            else
              Center(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls, // We use our own custom controls
                  fit: _getBoxFit(
                      ref.watch(mobileSettingsProvider).aspectRatioMode),
                ),
              ),

            // Loading Overlay (Stays on top until smooth playback starts)
            // We moved _buildLoadingView out of the if/else chain above to overlay it
            if (_isLoading && _errorMessage == null)
              Container(
                color: Colors.black,
                child: _buildLoadingView(),
              ),

            // Custom controls overlay
            if (_showControls && _errorMessage == null && !_isLoading)
              _buildControlsOverlay(title),

            // Top bar (always visible when controls are shown)
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      color: Colors
                          .black54, // Flat color instead of Gradient for performance
                    ),
                    child: Row(
                      children: [
                        // Main Back Button
                        // Main Back Button
                        TVFocusable(
                          focusNode: _backFocusNode,
                          onPressed: () => Navigator.pop(context),
                          onFocus: _resetControlsTimer,
                          borderRadius: BorderRadius.circular(50),
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                        // Hidden Debug Trigger (Invisible InkWell next to back button)
                        InkWell(
                          onLongPress: () {
                            final current =
                                ref.read(mobileSettingsProvider).showDebugStats;
                            ref
                                .read(mobileSettingsProvider.notifier)
                                .toggleShowDebugStats(!current);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Debug Mode: ${!current ? "ON" : "OFF"}',
                                ),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const SizedBox(width: 20, height: 40),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.streamType == StreamType.live)
                                Text(
                                  _currentTime,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Removed top-right arrows as requested
                        const SizedBox(width: 48), // Spacer for balance
                      ],
                    ),
                  ),
                ),
              ),

            // Stats Overlay (Top Left) - Isolated to prevent main rebuilds
            Positioned(
              top: 80,
              left: 16,
              child: StatsOverlayWidget(player: _player),
            ),
          ],
        ),
      ),
    );
  }

  BoxFit _getBoxFit(String mode) {
    switch (mode) {
      case 'cover':
        return BoxFit.cover;
      case 'fill':
        return BoxFit.fill;
      case 'contain':
      default:
        return BoxFit.contain;
    }
  }

  void _cycleAspectRatio() {
    final current = ref.read(mobileSettingsProvider).aspectRatioMode;
    String next;
    String label;
    if (current == 'contain') {
      next = 'cover';
      label = 'Zoom (Cover)';
    } else if (current == 'cover') {
      next = 'fill';
      label = 'Étirer (Fill)';
    } else {
      next = 'contain';
      label = 'Original (Contain)';
    }

    ref.read(mobileSettingsProvider.notifier).setAspectRatioMode(next);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Format: $label'),
          duration: const Duration(seconds: 1),
          backgroundColor: Colors.black87,
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildControlsOverlay(String title) {
    final settings = ref.watch(mobileSettingsProvider);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: Stack(
          children: [
            // Removed Duplicate Back Button (Top Left) - handled by Top Bar now

            // Bottom Controls (Aligned with EPG)
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Prev Channel / Replay 10s
                    if (widget.streamType == StreamType.live &&
                        widget.channels != null &&
                        widget.channels!.isNotEmpty)
                      TVFocusable(
                        focusNode: _prevFocusNode,
                        onPressed: _playPrevious,
                        onFocus: _resetControlsTimer,
                        borderRadius: BorderRadius.circular(50),
                        child: IconButton(
                          icon: const Icon(
                            Icons.skip_previous,
                            color: Colors.white,
                            size: 48,
                          ),
                          onPressed: _playPrevious,
                        ),
                      )
                    else if (widget.streamType != StreamType.live)
                      TVFocusable(
                        focusNode: _prevFocusNode,
                        onPressed: () async {
                          final pos = await _player.stream.position.first;
                          _player.seek(pos - const Duration(seconds: 5));
                          _resetControlsTimer();
                        },
                        onFocus: _resetControlsTimer,
                        borderRadius: BorderRadius.circular(50),
                        child: IconButton(
                          icon: const Icon(
                            Icons.replay_10,
                            color: Colors.white,
                            size: 48,
                          ),
                          onPressed: () async {
                            final pos = await _player.stream.position.first;
                            _player.seek(pos - const Duration(seconds: 5));
                          },
                        ),
                      ),

                    const SizedBox(width: 32),

                    // Play/Pause
                    TVFocusable(
                      focusNode: _playPauseFocusNode,
                      onPressed: _togglePlayPause,
                      onFocus: _resetControlsTimer,
                      scale: 1.1, // Larger scale for main button
                      borderRadius: BorderRadius.circular(50),
                      child: IconButton(
                        iconSize: 72,
                        icon: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: Colors.white,
                        ),
                        onPressed: _togglePlayPause,
                      ),
                    ),

                    const SizedBox(width: 32),

                    // Next Channel / Forward 10s
                    if (widget.streamType == StreamType.live &&
                        widget.channels != null &&
                        widget.channels!.isNotEmpty)
                      TVFocusable(
                        focusNode: _nextFocusNode,
                        onPressed: _playNext,
                        onFocus: _resetControlsTimer,
                        borderRadius: BorderRadius.circular(50),
                        child: IconButton(
                          icon: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                            size: 48,
                          ),
                          onPressed: _playNext,
                        ),
                      )
                    else if (widget.streamType != StreamType.live)
                      TVFocusable(
                        focusNode: _nextFocusNode,
                        onPressed: () async {
                          final pos = await _player.stream.position.first;
                          _player.seek(pos + const Duration(seconds: 5));
                          _resetControlsTimer();
                        },
                        onFocus: _resetControlsTimer,
                        borderRadius: BorderRadius.circular(50),
                        child: IconButton(
                          icon: const Icon(
                            Icons.forward_10,
                            color: Colors.white,
                            size: 48,
                          ),
                          onPressed: () async {
                            final pos = await _player.stream.position.first;
                            _player.seek(pos + const Duration(seconds: 5));
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // EPG Box (Bottom Left) + LIVE Badge
            if (widget.streamType == StreamType.live &&
                _epg != null &&
                _epg!.nowPlaying != null)
              Positioned(
                bottom: 80, // Above progress/bottom bar
                left: 24,
                width: 350, // Increased width for badge
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _epg!.nowPlaying!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_epg!.nextPlaying != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        "A suivre: ${_epg!.nextPlaying}",
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // LIVE Badge inside the box, right side
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Progress Bar / Time (Bottom)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.streamType != StreamType.live)
                      Row(
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          Expanded(
                            child: Slider(
                              value: _position.inSeconds
                                  .toDouble()
                                  .clamp(0, _duration.inSeconds.toDouble()),
                              min: 0,
                              max: _duration.inSeconds.toDouble(),
                              // Add divisions for precise seeking (1 step = 10 seconds)
                              divisions: _duration.inSeconds > 0
                                  ? (_duration.inSeconds / 10).ceil()
                                  : null,
                              activeColor: AppColors.primary,
                              inactiveColor: Colors.white24,
                              onChangeStart: (_) => _isSeeking = true,
                              onChangeEnd: (value) async {
                                await _player
                                    .seek(Duration(seconds: value.toInt()));
                                _isSeeking = false;
                              },
                              onChanged: (value) {
                                setState(() {
                                  _position = Duration(seconds: value.toInt());
                                });
                              },
                            ),
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.streamType == StreamType.live &&
                                settings.showClock)
                              // Clock
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _currentTime,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            // LIVE Badge removed from here
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text(
            'Chargement...',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Erreur de lecture',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'Une erreur inconnue est survenue',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Retour'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _loadStream,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Isolated Stats Widget to prevent rebuilding the entire Video Player on every update
class StatsOverlayWidget extends ConsumerStatefulWidget {
  final Player player;
  const StatsOverlayWidget({super.key, required this.player});

  @override
  ConsumerState<StatsOverlayWidget> createState() => _StatsOverlayWidgetState();
}

class _StatsOverlayWidgetState extends ConsumerState<StatsOverlayWidget> {
  Duration _buffer = Duration.zero;
  String _decoder = 'Unknown';

  // Throttling updates
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // Use a periodic timer to poll/update stats instead of listening to every single frequent event
    // This reduces UI thread load significantly on low-end devices
    _updateTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (mounted) {
        setState(() {
          _buffer = widget.player.state.buffer;
          // Accessing nested prop safely just in case
          final track = widget.player.state.track.video;
          _decoder = track.decoder ?? 'Auto';
        });
      }
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(mobileSettingsProvider).showDebugStats) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'STATS FOR NERDS 🤓',
            style: TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Buffer: ${_buffer.inSeconds}s',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Text(
            'Decoder: $_decoder',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
