import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/features/iptv/services/xtream_service_mobile.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/features/iptv/screens/lite_player_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';


/// Stream type enum for player
// (Moved to global or imported from iptv_models if available)

/// Native video player screen for Android/iOS
/// Uses media_kit (FFmpeg) for full codec support (AC3, EAC3, DTS, etc.)
class NativePlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final model.StreamType streamType;
  final String? containerExtension;
  final PlaylistConfig playlist;
  final List<model.Channel>? channels;
  final int initialIndex;

  // For series episodes (to track watch history)
  final dynamic seriesId;
  final int? season;
  final int? episodeNum;

  // Experimental
  final bool forceDeinterlace;

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
    this.forceDeinterlace = false,
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
  final FocusNode _sliderFocusNode = FocusNode();
  final FocusNode _backFocusNode = FocusNode();
  final FocusNode _audioFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isFirstLoad = true; // true = black overlay; false = silent spinner
  bool _isReconnecting = false; // silent reconnect spinner (no black overlay)
  String? _errorMessage;
  late int _currentIndex;
  XtreamServiceMobile? _xtreamService;
  bool _showControls = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  final bool _isSeeking = false;
  bool _useSoftwareDecoder = false;

  // [TiviMate] Zapping OSD — shown for 3s after each channel switch
  bool _showZappingOSD = false;
  Timer? _zappingOSDTimer;

  // [TiviMate] Channel List Sidebar
  bool _showChannelList = false;
  Timer? _channelListTimer;
  final ScrollController _channelListScrollController = ScrollController();

  Timer? _clockTimer;
  Timer? _controlsTimer; // Auto-hide timer
  Timer? _epgTimer; // Periodic EPG refresh for live TV
  Timer? _liveWatchdog; // Watchdog for live stream reconnection
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  String _currentTime = '';
  bool _hasMarkedAsWatched = false;
  DateTime? _lastSaveTime;

  // [v23.0] Position-based stall tracking for robust watchdog
  // Tracks the last time the player position actually advanced.
  // A freeze is only "real" if position hasn't changed for > 60 seconds.
  Duration _lastKnownPosition = Duration.zero;
  DateTime? _lastPositionChangeTime;

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
    // [V5.2 Fix] Force native Android Hardware decoding (Hardware-to-Surface)
    (_player.platform as dynamic)?.setProperty('hwdec', 'mediacodec');

    // Performance & Scaling Fixes for Android
    // 'opengl-pbo' removed to save VRAM on low-end devices preventing long-run crashes
    (_player.platform as dynamic)?.setProperty('video-unscaled', 'no');

    if (widget.forceDeinterlace) {
      debugPrint('MediaKitPlayer: Forcing Deinterlace ON');
      (_player.platform as dynamic)?.setProperty('deinterlace', 'yes');
    }

    debugPrint('MediaKitPlayer: Decoder Mode set to $decoderMode');

    // ============ PERFORMANCE 3.0 (ANTI MICRO-COUPURE PROFILE) ============
    // Tuned to eliminate micro-stuttering during live TV playback
    // Increased buffers for smoother playback at cost of ~100MB RAM

    // Unified Buffering Logic (Live vs VOD)
    (_player.platform as dynamic)?.setProperty('cache', 'yes');

    if (widget.streamType == model.StreamType.live) {
      // ===== LIVE PROFILE — Anti-Artefact v22.0 (TiviMate Flow) =====
      // Principe TiviMate : jouer à partir de là où on est, JAMAIS chasser le live edge.
      // ExoPlayer n'utilise pas les PTS du stream pour se recaler — on fait pareil.

      // --- Buffering stable (TiviMate Medium ~ 8-10s) ---
      (_player.platform as dynamic)?.setProperty('cache-secs', '8');
      (_player.platform as dynamic)?.setProperty('demuxer-max-bytes', '150000000'); // 150MB RAM max
      (_player.platform as dynamic)?.setProperty('demuxer-readahead-secs', '10');
      (_player.platform as dynamic)?.setProperty('demuxer-thread', 'yes');
      // Si le buffer se vide : courte pause (0.5s) puis reprise — freeze minimal, SANS rattrapage
      // 0.5s vs 1.5s : moins de gel visible, moins de PTS gap à rattraper
      (_player.platform as dynamic)?.setProperty('cache-pause', 'yes');
      (_player.platform as dynamic)?.setProperty('cache-pause-wait', '0.5');
      (_player.platform as dynamic)?.setProperty('cache-pause-initial', 'no');
      (_player.platform as dynamic)?.setProperty('cache-unlink-files', 'yes');

      // --- Décodage hardware — Direct Surface ---
      (_player.platform as dynamic)?.setProperty('hwdec', 'mediacodec');

      // --- Synchronisation A/V : mode desync (clé anti-rattrapage) ---
      // video-sync: desync = audio et vidéo jouent indépendamment, AUCUN ajustement de vitesse.
      // C'est le mode le plus stable pour les flux live IPTV :
      //   - pas de fast-forward pour rattraper l'audio
      //   - pas de slow-down pour attendre la vidéo
      //   - identique au comportement natif ExoPlayer de TiviMate
      // video-sync: audio (ancien) ajustait la vitesse lecture selon l'horloge audio
      // ⇒ si audio dérive ou est en avance après un rebuffer : fast-forward visible = RATTRAPAGE
      (_player.platform as dynamic)?.setProperty('correct-pts', 'no');
      (_player.platform as dynamic)?.setProperty('video-sync', 'desync');
      // autosync non applicable en mode desync, supprimé

      // --- Qualité image : JAMAIS de skip de frames sur du live TV ---
      (_player.platform as dynamic)?.setProperty('framedrop', 'no');

    } else {
      // VOD PROFILE: Radical Compatibility (Software Mode)
      // Pour VOD, on garde correct-pts:yes (précision de position nécessaire pour le seek)
      (_player.platform as dynamic)?.setProperty('hwdec', 'no');
      (_player.platform as dynamic)?.setProperty('correct-pts', 'yes');
      (_player.platform as dynamic)?.setProperty('video-sync', 'audio');
    }
    
    // [V11.0 Perfect Restoration] Recovering settings from working commit a1628a6b
    // Forced software re-sampling handles ANY stubborn 5.1/LATM/24-bit audio track.
    (_player.platform as dynamic)?.setProperty('ad', 'lavc:*');
    (_player.platform as dynamic)?.setProperty('af', 'lavrresample,format=channels=stereo:sample_fmts=s16');
    (_player.platform as dynamic)?.setProperty('audio-format', 's16');
    (_player.platform as dynamic)?.setProperty('ao', 'audiotrack');
    (_player.platform as dynamic)?.setProperty('audio-pitch-correction', 'no');
    (_player.platform as dynamic)?.setProperty('audio-buffer', '0.2'); // Live: buffer audio court (réduit le désync pendant les cache-pauses)
    (_player.platform as dynamic)?.setProperty('audio-samplerate', '48000');
    (_player.platform as dynamic)?.setProperty('aid', 'auto');
    
    // --- Seeking & Sync globaux ---
    (_player.platform as dynamic)?.setProperty('hr-seek', 'no');           // Seeking rapide (plus sûr pour IPTV)
    (_player.platform as dynamic)?.setProperty('hr-seek-framedrop', 'yes');
    (_player.platform as dynamic)?.setProperty('cache-unlink-files', 'yes');
    (_player.platform as dynamic)?.setProperty('interpolation', 'no');     // Pas d'interpolation (trop lourd sur Android)

    // --- Réseau & Timeouts ---
    (_player.platform as dynamic)?.setProperty('network-timeout', '120');
    (_player.platform as dynamic)?.setProperty('stream-timeout', '120');
    (_player.platform as dynamic)?.setProperty('tls-verify', 'no');
    (_player.platform as dynamic)
        ?.setProperty('http-header-fields', 'User-Agent: XtremFlow/1.0');

    // --- Reconnexion réseau FFmpeg (consolidée) ---
    // IMPORTANT : reconnect_at_eof SUPPRIMÉ
    // Les serveurs IPTV ferment souvent la connexion HTTP entre segments (comportement normal).
    // reconnect_at_eof=1 causait une reconnexion au live edge (position en avance) après chaque EOF
    // ⇒ freeze pendant la reconnexion + saut de position = RATTRAPAGE visible
    // Le watchdog applicatif (toutes les 15s) gère les vrais arrêts de stream.
    (_player.platform as dynamic)?.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
    );

    // --- Probing du flux (une seule entrée, consolidée) ---
    // Précédent : 2 setProperty('demuxer-lavf-o') en conflit
    // fflags=+discardcorrupt supprimé : peut causer des skips sur certains streams IPTV
    (_player.platform as dynamic)?.setProperty(
      'demuxer-lavf-o',
      'analyzeduration=2000000,probesize=1000000',
    );

    // --- Décodeur lavc : threads libres, sans fast-mode (qualité prioritaire) ---
    // vd-lavc-skiploopfilter SUPPRIMÉ (causait la pixelisation)
    // vd-lavc-fast SUPPRIMÉ (décodage imprécis = artefacts)
    (_player.platform as dynamic)?.setProperty('vd-lavc-threads', '0');    // Threads auto (0 = détection auto)

    // Low-latency intentionally removed for stability
    /*
    if (widget.streamType == model.StreamType.live) {
      (_player.platform as dynamic)?.setProperty('profile', 'low-latency');
    }
    */

    // Track Selection - Auto (Safe for all)
    (_player.platform as dynamic)?.setProperty('aid', 'auto');
    (_player.platform as dynamic)?.setProperty('alang', 'fr,fra,fre,en,eng');
    (_player.platform as dynamic)?.setProperty('volume', '100');
    (_player.platform as dynamic)?.setProperty('mute', 'no'); 

    debugPrint('MediaKitPlayer: Combined Live/VOD configuration applied');

    _controller = VideoController(_player);

    // Listen to player state
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() {
          _isPlaying = playing;
          if (playing) _errorMessage = null; // Clear error on successful play
        });
        if (playing) {
          // Smooth Loading: Hide loading screen AFTER playback actually starts
          // Faster hide for Live TV
          final hideDelay = widget.streamType == model.StreamType.live ? 300 : 1000;
          Future.delayed(Duration(milliseconds: hideDelay), () {
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

        // [v23.0] Track last position change time for time-based watchdog
        if (position != _lastKnownPosition) {
          _lastKnownPosition = position;
          _lastPositionChangeTime = DateTime.now();
        }

        // Check if 80% of content watched (for VOD/Series only)
        _checkAndMarkWatched(position);

        // Auto-save position every 10 seconds (resilience against app kill/crash)
        if (widget.streamType != model.StreamType.live &&
            !_hasMarkedAsWatched) {
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
        setState(() {
          _duration = duration;
          // [V5.1 UI Fix] Force loading off as soon as metadata/duration is known
          // backup to the 'playing' event for VOD visibility
          if (duration.inSeconds > 0 && _isLoading) {
            _isLoading = false;
          }
        });
      }
    });

    _player.stream.width.listen((width) {
      if (mounted && (width ?? 0) > 0 && _isLoading) {
        debugPrint('MediaKitPlayer: Video width detected ($width), clearing loading overlay');
        setState(() => _isLoading = false);
      }
    });

    _player.stream.error.listen((error) async {
      if (!mounted) return;
      if (error.isEmpty) return;

      debugPrint('MediaKitPlayer Error Stream: $error');

      // For LIVE TV: never reload the stream on errors — mpv handles recovery internally.
      // Only show fatal errors that truly stop playback (detected by watchdog after 2min).
      if (widget.streamType == model.StreamType.live) {
        debugPrint('MediaKitPlayer: Live — ignoring error (mpv handles internally): $error');
        return;
      }

      // For VOD/Series: retry with software decoding on first error
      if (!_useSoftwareDecoder) {
        debugPrint(
          'MediaKitPlayer: VOD error — retrying with Software Decoding...',
        );
        setState(() => _useSoftwareDecoder = true);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) _loadStream();
        return;
      }

      setState(() {
        _errorMessage = error;
        _isLoading = false;
      });
    });

    // Listen for stream completion
    _player.stream.completed.listen((completed) {
      if (completed && mounted) {
        // For Live TV: do NOT reconnect immediately — let mpv handle it internally.
        // Only reconnect after a long pause (handled by watchdog).
        if (widget.streamType == model.StreamType.live) {
          debugPrint(
            'MediaKitPlayer: Live stream completed signal — ignoring (mpv handles reconnect internally)',
          );
          return;
        }
        // Logic for VOD/Series: Check if really finished or cut off
        if (_duration.inSeconds > 0) {
          final progress = _position.inSeconds / _duration.inSeconds;
          if (progress < 0.95) {
            debugPrint(
              'MediaKitPlayer: VOD stopped prematurely at ${(progress * 100).toStringAsFixed(1)}%, attempting reconnect...',
            );
            _attemptReconnect();
          }
        }
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (widget.streamType == model.StreamType.live) {
        // Force stop for Live TV
        _player.stop();
      } else {
        _player.pause();
      }

      // Exit player screen so user returns to dashboard on resume
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
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
    _epgTimer?.cancel();
    _liveWatchdog?.cancel();
    _zappingOSDTimer?.cancel();
    _channelListTimer?.cancel();
    _channelListScrollController.dispose();

    // Stop playback first to prevent audio continuing in background
    _player.stop();
    _player.dispose();
    _xtreamService?.dispose();

    // [P1-3 FIX] Dispose all focus nodes ONCE (was being disposed twice, causing crash)
    _playPauseFocusNode.dispose();
    _prevFocusNode.dispose();
    _nextFocusNode.dispose();
    _sliderFocusNode.dispose();
    _backFocusNode.dispose();
    _audioFocusNode.dispose();

    // Restore normal orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  /// Get content ID for resume position storage
  String get _contentId {
    if (widget.streamType == model.StreamType.series &&
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
    if (widget.streamType == model.StreamType.live) return;

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
        // If VOD/Series, try to resume from current position
        if (widget.streamType != model.StreamType.live &&
            _position.inSeconds > 0) {
          _loadStream(startAt: _position);
        } else {
          _loadStream();
        }
      }
    });
  }

  /// Check if 80% of content watched and mark as watched
  void _checkAndMarkWatched(Duration position) {
    // Skip if already marked, live TV, or no duration
    if (_hasMarkedAsWatched) return;
    if (widget.streamType == model.StreamType.live) return;
    if (_duration.inSeconds <= 0) return;

    final progress = position.inSeconds / _duration.inSeconds;

    if (progress >= 0.80) {
      _hasMarkedAsWatched = true;
      debugPrint('MediaKitPlayer: 80% reached, marking as watched');

      if (widget.streamType == model.StreamType.vod) {
        // Mark movie as watched
        ref
            .read(mobileWatchHistoryProvider.notifier)
            .markMovieWatched(widget.streamId);
      } else if (widget.streamType == model.StreamType.series &&
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

  int _watchdogStallCount = 0;

  /// [v23.0] Watchdog revampé — Détection temporelle basée sur la POSITION réelle.
  ///
  /// Problème de l'ancienne version :
  /// Le watchdog vérifiait `!_isPlaying` toutes les 15s. Pendant un cache-pause de
  /// 0.5s (normal sur IPTV), si le tick de 15s tombait pendant la pause, il incrémentait
  /// le compteur. Après 2 tels événements (30s), il appelait `_loadStream()` → nouvelle
  /// requête HTTP au LIVE EDGE → saut de position = RATTRAPAGE.
  ///
  /// Nouvelle logique (style TiviMate) :
  /// - Suit la dernière fois que la POSITION a avancé (plus fiable que _isPlaying)
  /// - Ne reconnecte que si la position est gelée depuis > 60 secondes CONTINUES
  /// - Les cache-pauses courtes (< 60s) sont ignorées — mpv les gère via stream-lavf-o
  void _startLiveWatchdog() {
    _liveWatchdog?.cancel();
    _watchdogStallCount = 0;
    if (widget.streamType != model.StreamType.live) return;

    // Initialiser le timestamp de position
    _lastPositionChangeTime = DateTime.now();
    _lastKnownPosition = Duration.zero;

    // Vérifie toutes les 10s, mais seuil de reconnexion à 60s de position gelée
    _liveWatchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;

      // Si le player joue et la position avance : tout va bien, reset
      if (_isPlaying && _lastPositionChangeTime != null) {
        final stallSecs = DateTime.now().difference(_lastPositionChangeTime!).inSeconds;
        if (stallSecs < 5) return; // Position avance normalement
      }

      // Calculer la durée réelle de gel (basée sur la position, pas sur _isPlaying)
      final stallSecs = _lastPositionChangeTime != null
          ? DateTime.now().difference(_lastPositionChangeTime!).inSeconds
          : 9999;

      debugPrint('MediaKitPlayer: Watchdog — position gelée depuis ${stallSecs}s');

      // Ne reconnecte QUE si vraiment gelé depuis > 60s (les cache-pauses sont < 5s)
      // Cela laisse mpv's reconnect interne (stream-lavf-o) gérer les coupures courtes
      if (stallSecs > 60) {
        debugPrint('MediaKitPlayer: Watchdog — gel de 60s confirmé, reconnexion forcée');
        _lastPositionChangeTime = DateTime.now(); // Éviter re-déclenchement immédiat
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

  model.ShortEPG? _epg;

  // ... (existing initState)

  Future<void> _loadStream({Duration? startAt}) async {
    try {
      if (_xtreamService == null) return;

      setState(() {
        if (_isFirstLoad) {
          _isLoading = true; // Black overlay only on first load
        } else {
          _isReconnecting = true; // Silent spinner on subsequent loads
        }
        _errorMessage = null;
        _epg = null; // Reset EPG
      });

      // [V5.2 Fix] Absolute fail-safe Loading Timeout (5 seconds)
      // This ensures even if metadata/width is never reached, the UI opens
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _isLoading) {
          debugPrint('MediaKitPlayer: Loading Timeout reached, forcing Visibility');
          setState(() => _isLoading = false);
        }
      });

      // Determine effective Stream ID
      final currentStreamId =
          widget.channels != null && widget.channels!.isNotEmpty
              ? widget.channels![_currentIndex].streamId
              : widget.streamId;

      // Load EPG if Live TV (with periodic refresh every 5 min)
      if (widget.streamType == model.StreamType.live) {
        _loadEpg(currentStreamId);
        _epgTimer?.cancel();
        _epgTimer = Timer.periodic(const Duration(minutes: 5), (_) {
          _loadEpg(currentStreamId);
        });
      }

      // ... (rest of _loadStream logic: get url, open player)
      // Build stream URL based on type
      String streamUrl;

      if (widget.streamType == model.StreamType.live) {
        streamUrl = _xtreamService!.getLiveStreamUrl(currentStreamId);
      } else if (widget.streamType == model.StreamType.vod) {
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

      // [v23.0] Fix: Ne PAS overrider hwdec pour les streams live.
      // initState a déjà configuré 'mediacodec' pour le live.
      // Overrider ici avec mobileSettingsProvider.decoderMode annulerait ce réglage
      // (si l'utilisateur a 'auto' dans les settings → retour à mediacodec-copy).
      // Pour le VOD : on garde le fallback logiciel si nécessaire.
      if (widget.streamType != model.StreamType.live) {
        final hwdecValue = _useSoftwareDecoder
            ? 'no'
            : ref.read(mobileSettingsProvider).decoderMode;
        (_player.platform as dynamic)?.setProperty('hwdec', hwdecValue);
      } else if (_useSoftwareDecoder) {
        // Live fallback software uniquement si hardware a échoué
        (_player.platform as dynamic)?.setProperty('hwdec', 'no');
      }

      await _player.open(
        Media(streamUrl, httpHeaders: {'User-Agent': 'XtremFlow/1.0'}),
        play: true,
      );

      setState(() {
        // [TiviMate] For live: DON'T hide loading here — let the 'playing' / 'width'
        // stream listeners handle it for a glitch-free first-frame reveal.
        // For VOD: immediately hide since we need the controls visible for seek.
        if (widget.streamType != model.StreamType.live) {
          _isLoading = false;
        }
        _isReconnecting = false;
        _isFirstLoad = false;
        _reconnectAttempts = 0; // Reset reconnect counter on success
      });

      // Show watchdog for live streams
      if (widget.streamType == model.StreamType.live) {
        _startLiveWatchdog();
      }

      // Resume from saved position (VOD/Series only)
      if (widget.streamType != model.StreamType.live) {
        // Priority 0: Explicit reconnect position (passed from _attemptReconnect)
        if (startAt != null && startAt.inSeconds > 0) {
          debugPrint(
            'MediaKitPlayer: Resuming after reconnect at: ${startAt.inSeconds}s',
          );
          _seekToResume(startAt.inSeconds);
        }
        // Priority 1: Explicit initial position passed from caller verification
        else if (widget.initialPosition != null &&
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
        _isReconnecting = false;
        _isFirstLoad = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _loadEpg(String streamId) async {
    try {
      // Use shared provider service so EPG cached by channel cards is reused instantly
      final service = await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      final epg = await service.getShortEPG(streamId);
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
      _showZappingOSD = true;
      _showChannelList = false; // close sidebar on switch
      _showControls = false;    // hide regular OSD — Zapping OSD takes over
    });
    // Show zapping OSD for 3 seconds
    _zappingOSDTimer?.cancel();
    _zappingOSDTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showZappingOSD = false);
    });
    _loadStream();
  }

  /// Open/close the channel list sidebar
  void _toggleChannelList() {
    setState(() => _showChannelList = !_showChannelList);
    if (_showChannelList) {
      _scrollToCurrentChannel();
      _channelListTimer?.cancel();
      _channelListTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showChannelList = false);
      });
    } else {
      _channelListTimer?.cancel();
    }
  }

  /// Scroll channel list to keep current channel visible
  void _scrollToCurrentChannel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_channelListScrollController.hasClients) return;
      const itemHeight = 64.0;
      final offset = (_currentIndex * itemHeight) -
          (_channelListScrollController.position.viewportDimension / 2) +
          (itemHeight / 2);
      _channelListScrollController.animateTo(
        offset.clamp(0, _channelListScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _player.pause();
      // Save position on pause
      if (widget.streamType != model.StreamType.live) {
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

    try {
      final key = event.logicalKey;

      // Explicit Play
      if (key == LogicalKeyboardKey.mediaPlay) {
        if (!_isPlaying) _player.play();
        _onUserInteraction();
        return true;
      }

      // Explicit Pause
      if (key == LogicalKeyboardKey.mediaPause) {
        if (_isPlaying) _player.pause();
        _onUserInteraction();
        return true;
      }

      // Space / Enter / Select / Toggle
      if (key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.mediaPlayPause) {
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
        ref
            .read(mobileSettingsProvider.notifier)
            .toggleShowDebugStats(!current);
        return true;
      }

      // Left Arrow - Show controls or navigate, seek in VOD when hidden
      if (key == LogicalKeyboardKey.arrowLeft) {
        if (!_showControls) {
          if (widget.streamType != model.StreamType.live) {
            final newPos = _position - const Duration(seconds: 10);
            _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
          }
          _onUserInteraction();
          return true;
        }
        return false; // Let Focus handle navigation
      }

      // Right Arrow - Show controls or navigate, seek in VOD when hidden
      if (key == LogicalKeyboardKey.arrowRight) {
        if (!_showControls) {
          if (widget.streamType != model.StreamType.live) {
            final newPos = _position + const Duration(seconds: 10);
            if (newPos < _duration) {
              _player.seek(newPos);
            }
          }
          _onUserInteraction();
          return true;
        }
        return false; // Let Focus handle navigation
      }

      // Up/Down Arrow - Show controls or navigate UI, NO zapping
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown) {
        if (!_showControls) {
          _onUserInteraction();
          return true;
        }
        return false; // Let Focus handle navigation
      }

      // Channel Down = Previous Channel (inverted as requested)
      if (key == LogicalKeyboardKey.channelDown) {
        if (widget.streamType == model.StreamType.live &&
            widget.channels != null) {
          _playPrevious();
          _onUserInteraction();
          return true;
        }
      }

      // Channel Up = Next Channel (inverted as requested)
      if (key == LogicalKeyboardKey.channelUp) {
        if (widget.streamType == model.StreamType.live &&
            widget.channels != null) {
          _playNext();
          _onUserInteraction();
          return true;
        }
      }

      // OK / Select when channel list is open → switch to focused channel
      if (_showChannelList &&
          (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.select ||
              key == LogicalKeyboardKey.numpadEnter)) {
        // Channel list handles its own tap, this closes it
        setState(() => _showChannelList = false);
        return true;
      }

      // Menu key or 'M' → toggle channel list sidebar
      if (key == LogicalKeyboardKey.contextMenu ||
          key == LogicalKeyboardKey.keyM) {
        if (widget.streamType == model.StreamType.live &&
            widget.channels != null) {
          _toggleChannelList();
          return true;
        }
      }

      // Cycle Aspect Ratio - secret key 'A' or digit 1
      if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.digit1) {
        _cycleAspectRatio();
        return true;
      }

      // Escape / Back - Exit player
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        // If controls are visible, close them first
        if (_showControls) {
          setState(() => _showControls = false);
        } else {
          Navigator.of(context).pop();
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error in _handleKeyEvent: $e');
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
    final currentIndex = tracks.indexOf(current);
    final nextIndex = (currentIndex + 1) % tracks.length;
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

    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: Colors.black, // [V5.2 Fix] Enforce black background globally
        body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_showChannelList) {
            setState(() => _showChannelList = false);
          } else {
            _toggleControls();
          }
        },
        onPanDown: (_) => _onUserInteraction(),
        onPanUpdate: (_) => _onUserInteraction(),
        // Swipe from right edge → open channel list
        onHorizontalDragEnd: (details) {
          if (widget.streamType == model.StreamType.live &&
              widget.channels != null &&
              details.primaryVelocity != null &&
              details.primaryVelocity! < -300) {
            _toggleChannelList();
          }
        },
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
                    ref.watch(mobileSettingsProvider).aspectRatioMode,
                  ),
                ),
              ),

            // Loading Overlay — black only on FIRST load
            if (_isLoading && _errorMessage == null)
              Container(
                color: Colors.black,
                child: _buildLoadingView(),
              ),

            // Silent reconnect spinner (does NOT black out the video)
            if (_isReconnecting && !_isLoading)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),

            // Custom controls overlay
            if (_showControls && _errorMessage == null)
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
                              if (widget.streamType == model.StreamType.live)
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

            // [TiviMate] Zapping OSD — shown briefly on channel switch
            if (_showZappingOSD &&
                widget.streamType == model.StreamType.live &&
                widget.channels != null &&
                widget.channels!.isNotEmpty)
              _buildZappingOSD(),

            // [TiviMate] Channel list sidebar
            if (_showChannelList &&
                widget.streamType == model.StreamType.live &&
                widget.channels != null &&
                widget.channels!.isNotEmpty)
              _buildChannelListSidebar(),

            // Stats Overlay (Top Left) - Isolated to prevent main rebuilds
            Positioned(
              top: 80,
              left: 16,
              child: StatsOverlayWidget(player: _player),
            ),
          ],
        ),
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

  Widget _buildUnifiedOSD(String title) {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // EPG Info (Left)
              Expanded(child: _buildEPGBox(title)),
              const SizedBox(width: 24),
              // Controls Continuity (Right)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Prev Channel
                  TVFocusable(
                    focusNode: _prevFocusNode,
                    onPressed: _playPrevious,
                    onFocus: _resetControlsTimer,
                    child: const Icon(
                      Icons.skip_previous,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Play/Pause
                  TVFocusable(
                    focusNode: _playPauseFocusNode,
                    onPressed: _togglePlayPause,
                    onFocus: _resetControlsTimer,
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_circle_filled
                          : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Next Channel
                  TVFocusable(
                    focusNode: _nextFocusNode,
                    onPressed: _playNext,
                    onFocus: _resetControlsTimer,
                    child: const Icon(
                      Icons.skip_next,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Disable Deinterlace Button
                  if (widget.forceDeinterlace) ...[
                    const SizedBox(width: 16),
                    TVFocusable(
                      onPressed: () {
                        final streamId =
                            widget.channels?[_currentIndex].streamId ??
                                widget.streamId;
                        ref
                            .read(mobileSettingsProvider.notifier)
                            .toggleChannelDeinterlace(streamId);

                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LitePlayerScreen(
                              streamId: streamId,
                              title: widget.channels?[_currentIndex].name ??
                                  widget.title,
                              playlist: widget.playlist,
                              streamType: widget.streamType,
                              channels: widget.channels,
                              initialIndex: _currentIndex,
                            ),
                          ),
                        );
                      },
                      onFocus: _resetControlsTimer,
                      child: const Icon(
                        Icons.grid_off,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEPGBox(String title) {
    final rawNow = _epg?.nowPlaying ?? '';
    String nowPlaying = rawNow.isNotEmpty ? rawNow : "Pas d'infos EPG";
    final epgProgress = _epg?.progress ?? 0.0;

    // Format start / end time for display
    String startTime = '';
    String endTime = '';
    if (_epg != null && _epg!.start.isNotEmpty && _epg!.end.isNotEmpty) {
      try {
        final s = DateTime.parse(_epg!.start).toLocal();
        final e = DateTime.parse(_epg!.end).toLocal();
        startTime =
            '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}';
        endTime =
            '${e.hour.toString().padLeft(2, '0')}:${e.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (widget.channels != null &&
                widget.channels![_currentIndex].streamIcon.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 12),
                width: 40,
                height: 40,
                child: CachedNetworkImage(
                  imageUrl: widget.channels![_currentIndex].streamIcon,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.tv, color: Colors.white38),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nowPlaying,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // EPG Progress Bar
                  if (startTime.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          startTime,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: epgProgress.clamp(0.0, 1.0),
                              minHeight: 4,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF4FC3F7),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          endTime,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildControlsOverlay(String title) {
    if (widget.streamType == model.StreamType.live) {
      return _buildUnifiedOSD(title);
    }
    return _buildVodControlsOverlay();
  }

  /// [TiviMate] Zapping OSD — brief overlay on channel switch (like TiviMate)
  Widget _buildZappingOSD() {
    final ch = widget.channels![_currentIndex];
    final chNum = _currentIndex + 1;
    final nowPlaying = _epg?.nowPlaying ?? '';
    final epgProgress = _epg?.progress ?? 0.0;

    return Positioned(
      bottom: 24,
      left: 24,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Channel logo
              if (ch.streamIcon.isNotEmpty)
                Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white10,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: ch.streamIcon,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          const Icon(Icons.tv, color: Colors.white38, size: 32),
                    ),
                  ),
                )
              else
                Container(
                  width: 52,
                  height: 52,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white10,
                  ),
                  child: const Icon(Icons.tv, color: Colors.white38, size: 32),
                ),

              // Channel info
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1565C0),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'CH $chNum',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            ch.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_isReconnecting || _isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: SizedBox(
                          height: 3,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFF4FC3F7)),
                          ),
                        ),
                      )
                    else if (nowPlaying.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        nowPlaying,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: epgProgress.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF4FC3F7)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [TiviMate] Channel list sidebar — slide-in panel on the right
  Widget _buildChannelListSidebar() {
    final channels = widget.channels!;
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      child: Container(
        width: 280,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [Color(0xE6000000), Color(0x99000000)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.white12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list, color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Chaînes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _showChannelList = false),
                      child: const Icon(Icons.close,
                          color: Colors.white54, size: 18),
                    ),
                  ],
                ),
              ),
              // Channel list
              Expanded(
                child: ListView.builder(
                  controller: _channelListScrollController,
                  itemCount: channels.length,
                  itemExtent: 64.0,
                  itemBuilder: (context, index) {
                    final ch = channels[index];
                    final isActive = index == _currentIndex;
                    return GestureDetector(
                      onTap: () {
                        _channelListTimer?.cancel();
                        _switchChannel(index);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFF1565C0).withOpacity(0.6)
                              : Colors.transparent,
                          border: isActive
                              ? const Border(
                                  left: BorderSide(
                                    color: Color(0xFF4FC3F7),
                                    width: 3,
                                  ),
                                )
                              : null,
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            // Logo
                            Container(
                              width: 40,
                              height: 40,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: ch.streamIcon.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: CachedNetworkImage(
                                        imageUrl: ch.streamIcon,
                                        fit: BoxFit.contain,
                                        errorWidget: (_, __, ___) =>
                                            const Icon(Icons.tv,
                                                color: Colors.white38,
                                                size: 20),
                                      ),
                                    )
                                  : const Icon(Icons.tv,
                                      color: Colors.white38, size: 20),
                            ),
                            // Name + num
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    ch.name,
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 13,
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'CH ${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Active indicator
                            if (isActive)
                              const Icon(
                                Icons.play_arrow,
                                color: Color(0xFF4FC3F7),
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVodControlsOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.4),
        child: Stack(
          children: [
            // Bottom Controls (VOD - Centered)
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Prev 10s
                    TVFocusable(
                      focusNode: _prevFocusNode,
                      onPressed: () async {
                        final pos = await _player.stream.position.first;
                        _player.seek(pos - const Duration(seconds: 10));
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
                          _player.seek(pos - const Duration(seconds: 10));
                        },
                      ),
                    ),

                    const SizedBox(width: 32),

                    // Play/Pause
                    TVFocusable(
                      focusNode: _playPauseFocusNode,
                      onPressed: _togglePlayPause,
                      onFocus: _resetControlsTimer,
                      scale: 1.1,
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

                    // Next 10s
                    TVFocusable(
                      focusNode: _nextFocusNode,
                      onPressed: () async {
                        final pos = await _player.stream.position.first;
                        _player.seek(pos + const Duration(seconds: 10));
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
                          _player.seek(pos + const Duration(seconds: 10));
                        },
                      ),
                    ),
                  ],
                ),
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
                          child: Focus(
                            focusNode: _sliderFocusNode,
                            descendantsAreFocusable: false,
                            onKeyEvent: (node, event) {
                              if (event is! KeyDownEvent) {
                                return KeyEventResult.ignored;
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                _playPauseFocusNode.requestFocus();
                                return KeyEventResult.handled;
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft) {
                                final newPos =
                                    _position - const Duration(seconds: 10);
                                _player.seek(
                                  newPos < Duration.zero
                                      ? Duration.zero
                                      : newPos,
                                );
                                _resetControlsTimer();
                                return KeyEventResult.handled;
                              }

                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight) {
                                final newPos =
                                    _position + const Duration(seconds: 10);
                                if (newPos < _duration) _player.seek(newPos);
                                _resetControlsTimer();
                                return KeyEventResult.handled;
                              }

                              return KeyEventResult.ignored;
                            },
                            child: Slider(
                              value: _position.inSeconds
                                  .toDouble()
                                  .clamp(0, _duration.inSeconds.toDouble()),
                              min: 0.0,
                              max: _duration.inSeconds.toDouble(),
                              onChanged: (value) {
                                _player.seek(Duration(seconds: value.toInt()));
                                _resetControlsTimer();
                              },
                              activeColor: AppColors.primary,
                              inactiveColor: Colors.white24,
                            ),
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
    // During first load of a live channel: show logo + name for better UX
    final isLive = widget.streamType == model.StreamType.live;
    final hasChannel = isLive &&
        widget.channels != null &&
        widget.channels!.isNotEmpty;
    final ch = hasChannel ? widget.channels![_currentIndex] : null;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Channel logo during live TV first load
          if (ch != null && ch.streamIcon.isNotEmpty)
            Container(
              width: 72,
              height: 72,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: ch.streamIcon,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) =>
                      const Icon(Icons.tv, color: Colors.white38, size: 40),
                ),
              ),
            ),
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            ch != null ? ch.name : 'Chargement...',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
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
