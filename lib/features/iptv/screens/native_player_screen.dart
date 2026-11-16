import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/core/utils/form_factor.dart';
import 'package:xtremobile/core/widgets/app_dialog.dart';
import 'package:xtremobile/features/iptv/widgets/live_widgets.dart';
import 'package:xtremobile/features/iptv/widgets/player_osd.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/features/iptv/services/xtream_service_mobile.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremobile/features/iptv/screens/lite_player_screen.dart';

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

  /// Every episode of the series, in viewing order (season, then episode):
  /// enables « Épisode suivant ». Null for films and live TV.
  final List<model.Episode>? episodes;

  /// Name of the series, shown under the episode title.
  final String? seriesName;

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
    this.episodes,
    this.seriesName,
    this.forceDeinterlace = false,
  });

  final Duration? initialPosition;

  @override
  ConsumerState<NativePlayerScreen> createState() => _NativePlayerScreenState();
}

/// What the on-screen display shows (TV). Touch screens only use hidden /
/// shown: [info] and [actions] both show their controls.
enum _Osd {
  /// Nothing over the picture.
  hidden,

  /// Live: the compact plate (zapping), no buttons, 4 s.
  info,

  /// Live: the plate with its row of buttons (OK). VOD: the plate, focus on
  /// the bar (and the row of buttons when [_NativePlayerScreenState._vodRow]).
  actions,
}

class _NativePlayerScreenState extends ConsumerState<NativePlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;

  /// Player screens alive. A screen replacing another one (next episode,
  /// deinterlace) starts before the old one is disposed: the wakelock is only
  /// released when the last one goes.
  static int _liveScreens = 0;

  // Focus Nodes
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _prevFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();
  final FocusNode _sliderFocusNode = FocusNode();
  final FocusNode _formatFocusNode = FocusNode();
  final FocusNode _channelListButtonFocusNode = FocusNode();
  final FocusNode _retryFocusNode = FocusNode();

  /// Focus D-pad de la chaîne active dans la sidebar : permet d'atterrir
  /// directement dessus à l'ouverture de la liste.
  final FocusNode _channelListItemFocusNode = FocusNode();

  bool _isLoading = true;
  bool _isFirstLoad = true; // true = black overlay; false = silent spinner
  bool _isReconnecting = false; // silent reconnect spinner (no black overlay)
  String? _errorMessage;
  late int _currentIndex;
  XtreamServiceMobile? _xtreamService;
  _Osd _osd = _Osd.actions;

  /// VOD (TV): the row of buttons is open under the bar (▼).
  bool _vodRow = false;
  bool get _showControls => _osd != _Osd.hidden;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  final bool _isSeeking = false;
  bool _useSoftwareDecoder = false;

  bool get _isLive => widget.streamType == model.StreamType.live;
  bool get _hasChannels =>
      widget.channels != null && widget.channels!.isNotEmpty;
  bool get _isTv => FormFactors.isTv;

  /// Film position for the plate: only its listeners rebuild, once per tick,
  /// never the whole player.
  final ValueNotifier<VodProgress> _progress =
      ValueNotifier(const VodProgress());

  /// `21:52`, changes once a minute.
  final ValueNotifier<String> _clock = ValueNotifier('');

  /// Short message at the top (« Reprise à 38:12 »).
  final ValueNotifier<String?> _toast = ValueNotifier(null);
  Timer? _toastTimer;

  /// « 2 / 5 » while a reconnection is pending.
  final ValueNotifier<String?> _reconnectLabel = ValueNotifier(null);

  /// The player has been buffering for more than a second.
  final ValueNotifier<bool> _bufferingVisible = ValueNotifier(false);
  Timer? _bufferingTimer;

  /// Zapping with the remote held down: the plate follows at once, the
  /// stream only loads once the key rests (one connection per channel
  /// skipped would hit 1-connection subscriptions).
  Timer? _zapTimer;
  DateTime? _lastZapAt;

  // [TiviMate] Channel List Sidebar
  bool _showChannelList = false;
  Timer? _channelListTimer;
  final ScrollController _channelListScrollController = ScrollController();

  Timer? _clockTimer;
  Timer? _controlsTimer; // Auto-hide timer
  Timer? _epgTimer; // Periodic EPG refresh for live TV
  Timer? _liveWatchdog; // Watchdog for live stream reconnection

  /// Every player stream subscription, so none survives this screen.
  /// Left dangling they keep firing setState against a dead element — the
  /// classic slow leak behind "crashes after a few hours".
  final List<StreamSubscription<dynamic>> _playerSubscriptions = [];

  /// Set once the app is backgrounded, to stop any in-flight reload from
  /// resurrecting playback behind the user's back.
  bool _isReleased = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _hasMarkedAsWatched = false;
  DateTime? _lastSaveTime;

  // [v23.0] Position-based stall tracking for robust watchdog
  // Tracks the last time the player position actually advanced.
  // A freeze is only "real" if position hasn't changed for > 60 seconds.
  Duration _lastKnownPosition = Duration.zero;
  DateTime? _lastPositionChangeTime;

  /// (Re)starts the auto-hide: 4 s for the live zapping plate, 5 s
  /// otherwise. Nothing hides while paused or loading.
  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_showControls) return;
    _startClock(); // Ensure clock runs when controls are shown
    // The bar was not updated while hidden (a paused film sends nothing).
    if (!_isLive) _progress.value = _currentProgress;
    if (_isPlaying) {
      final delay = _isLive && _osd == _Osd.info
          ? const Duration(seconds: 4)
          : const Duration(seconds: 5);
      _controlsTimer = Timer(delay, _hideControls);
    }
  }

  void _hideControls() {
    _controlsTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _osd = _Osd.hidden;
      _vodRow = false;
    });
    _stopClock(); // Save CPU when hidden
  }

  /// Shows the controls (touch) or the default state (TV: live plate with
  /// its buttons, VOD bar), and restarts the auto-hide.
  void _onUserInteraction() {
    if (_isTv) {
      if (_isLive) {
        if (!_showControls) _showLiveInfo();
        _resetControlsTimer();
      } else {
        _openVod(row: _vodRow);
      }
      return;
    }
    if (!_showControls) setState(() => _osd = _Osd.actions);
    _resetControlsTimer();
  }

  /// Live: the compact plate (no buttons), as when zapping.
  void _showLiveInfo() {
    if (_osd != _Osd.info) setState(() => _osd = _Osd.info);
    _resetControlsTimer();
  }

  /// Live: the plate with its buttons, focus always on « Chaînes » (OK + OK
  /// must never pause the live stream).
  void _openLiveActions() {
    setState(() => _osd = _Osd.actions);
    _focusAfterBuild(
      _hasChannels ? _channelListButtonFocusNode : _formatFocusNode,
    );
    _resetControlsTimer();
  }

  /// VOD: the plate, focus on the bar; with [row], on the buttons.
  void _openVod({bool row = false}) {
    final wasShown = _showControls;
    final rowChanged = row != _vodRow;
    setState(() {
      _osd = _Osd.actions;
      _vodRow = row;
    });
    _progress.value = _currentProgress;
    if (!wasShown || rowChanged) {
      _focusAfterBuild(row ? _playPauseFocusNode : _sliderFocusNode);
    }
    _resetControlsTimer();
  }

  void _focusAfterBuild(FocusNode node) {
    if (!_isTv) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.canRequestFocus && node.context != null) {
        node.requestFocus();
      }
    });
  }

  VodProgress get _currentProgress => VodProgress(
        position: _position,
        duration: _duration,
        buffer: _buffer,
      );

  void _showToast(String text) {
    _toastTimer?.cancel();
    _toast.value = text;
    _toastTimer = Timer(const Duration(seconds: 2), () {
      _toast.value = null;
    });
  }

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Register keyboard handler for remote control
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    // Enable wakelock to prevent screen from turning off during playback
    _liveScreens++;
    WakelockPlus.enable();

    // TV: the live stream opens on the compact plate (« Connexion… »), a
    // film on its bar. Touch: the controls.
    _osd = _isTv && _isLive ? _Osd.info : _Osd.actions;
    if (_isTv && !_isLive) _focusAfterBuild(_sliderFocusNode);

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

      // --- Buffering basse latence (TiviMate Low ~ 3-5s) ---
      // 8s/10s de readahead ajoutaient autant de retard sur le direct : 3s de
      // cache + 5s de readahead suffisent à absorber la gigue réseau tout en
      // restant nettement plus près du live edge.
      (_player.platform as dynamic)?.setProperty('cache-secs', '3');
      (_player.platform as dynamic)
          ?.setProperty('demuxer-max-bytes', '60000000'); // 60MB RAM max
      (_player.platform as dynamic)?.setProperty('demuxer-readahead-secs', '5');
      (_player.platform as dynamic)?.setProperty('demuxer-thread', 'yes');
      // --- Plafond du buffer ARRIÈRE (stabilité longue durée) ---
      // mpv garde par défaut 50 Mio de flux déjà lu pour permettre un retour
      // arrière. Sur du live ce buffer ne sert à rien : cumulé aux 150 Mo de
      // readahead il pousse le tas natif vers ~200 Mo et finit par déclencher
      // un kill mémoire Android après plusieurs heures. 8 Mo suffisent aux
      // resynchronisations internes du démuxeur.
      (_player.platform as dynamic)
          ?.setProperty('demuxer-max-back-bytes', '8000000');
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

    // [Audio Fix] L'ancienne chaîne `af=lavrresample,format=channels=stereo:
    // sample_fmts=s16` mélangeait la syntaxe FFmpeg et mpv : `lavrresample`
    // n'existe plus dans les builds récents et `sample_fmts` n'est pas une
    // option du filtre `format` de mpv. Quand la chaîne échoue à s'initialiser
    // pour un codec donné (AC3/EAC3/LATM selon la chaîne TV), mpv coupe la
    // sortie audio ⇒ « certaines chaînes n'ont pas de son ».
    // Le downmix natif `audio-channels=stereo` fait la même chose (5.1 → 2.0)
    // sans chaîne de filtres fragile, et l'AO négocie lui-même le format.
    (_player.platform as dynamic)?.setProperty('ad', 'lavc:*');
    (_player.platform as dynamic)?.setProperty('audio-channels', 'stereo');
    (_player.platform as dynamic)?.setProperty('ao', 'audiotrack');
    (_player.platform as dynamic)?.setProperty('audio-pitch-correction', 'no');
    (_player.platform as dynamic)?.setProperty(
      'audio-buffer',
      '0.2',
    ); // Live: buffer audio court (réduit le désync pendant les cache-pauses)
    (_player.platform as dynamic)?.setProperty('aid', 'auto');

    // --- Seeking & Sync globaux ---
    (_player.platform as dynamic)
        ?.setProperty('hr-seek', 'no'); // Seeking rapide (plus sûr pour IPTV)
    (_player.platform as dynamic)?.setProperty('hr-seek-framedrop', 'yes');
    (_player.platform as dynamic)?.setProperty('cache-unlink-files', 'yes');
    (_player.platform as dynamic)?.setProperty(
      'interpolation',
      'no',
    ); // Pas d'interpolation (trop lourd sur Android)

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
    // fflags=+discardcorrupt supprimé : peut causer des skips sur certains streams IPTV
    // Ces valeurs sont des PLAFONDS : FFmpeg s'arrête dès que toutes les pistes
    // sont identifiées, donc les relever ne ralentit pas les flux sains.
    // 1MB/2s ratait la piste audio (AAC-LATM déclaré tard) sur certaines
    // chaînes ⇒ pas de son. 2MB/3s les récupère sans pénaliser le zapping.
    (_player.platform as dynamic)?.setProperty(
      'demuxer-lavf-o',
      'analyzeduration=3000000,probesize=2000000',
    );

    // --- Décodeur lavc : threads libres, sans fast-mode (qualité prioritaire) ---
    // vd-lavc-skiploopfilter SUPPRIMÉ (causait la pixelisation)
    // vd-lavc-fast SUPPRIMÉ (décodage imprécis = artefacts)
    (_player.platform as dynamic)?.setProperty(
      'vd-lavc-threads',
      '0',
    ); // Threads auto (0 = détection auto)

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
    _playerSubscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted) {
          setState(() {
            _isPlaying = playing;
            if (playing) _errorMessage = null; // Clear error on successful play
          });
          if (playing) {
            _reconnectLabel.value = null;
            // Smooth Loading: Hide loading screen AFTER playback actually starts
            // Faster hide for Live TV
            final hideDelay =
                widget.streamType == model.StreamType.live ? 300 : 1000;
            Future.delayed(Duration(milliseconds: hideDelay), () {
              if (mounted && _isPlaying) {
                setState(() => _isLoading = false);
              }
            });
            _resetControlsTimer(); // Start auto-hide timer
          }
        }
      }),
    );

    _playerSubscriptions.add(
      _player.stream.position.listen((position) {
        if (mounted && !_isSeeking) {
          // [v23.0] Track last position change time for time-based watchdog
          if (position != _lastKnownPosition) {
            _lastKnownPosition = position;
            _lastPositionChangeTime = DateTime.now();
          }

          // Never rebuild the player for this: mpv emits it several times per
          // second. Only the bar listens, and only while it is on screen.
          _position = position;
          if (_showControls && !_isLive) _progress.value = _currentProgress;

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
      }),
    );

    _playerSubscriptions.add(
      _player.stream.duration.listen((duration) {
        if (mounted) {
          _progress.value = VodProgress(
            position: _position,
            duration: duration,
            buffer: _buffer,
          );
          setState(() {
            _duration = duration;
            // [V5.1 UI Fix] Force loading off as soon as metadata/duration is known
            // backup to the 'playing' event for VOD visibility
            if (duration.inSeconds > 0 && _isLoading) {
              _isLoading = false;
            }
          });
        }
      }),
    );

    // Loaded part of a film (grey on the bar). Live: not shown.
    _playerSubscriptions.add(
      _player.stream.buffer.listen((buffer) {
        _buffer = buffer;
      }),
    );

    // « Mise en mémoire tampon… » only when it lasts: live cache pauses of
    // half a second are normal and must not flash a pill.
    _playerSubscriptions.add(
      _player.stream.buffering.listen((buffering) {
        _bufferingTimer?.cancel();
        if (!buffering) {
          _bufferingVisible.value = false;
          return;
        }
        _bufferingTimer = Timer(const Duration(milliseconds: 1200), () {
          if (mounted) _bufferingVisible.value = true;
        });
      }),
    );

    // Audio / subtitle tracks: rebuild the buttons that show them (rare).
    _playerSubscriptions.add(
      _player.stream.tracks.listen((_) {
        if (mounted) _refreshActiveTracks();
      }),
    );
    _playerSubscriptions.add(
      _player.stream.track.listen((_) {
        if (mounted) _refreshActiveTracks();
      }),
    );

    _playerSubscriptions.add(
      _player.stream.width.listen((width) {
        if (mounted && (width ?? 0) > 0 && _isLoading) {
          debugPrint(
            'MediaKitPlayer: Video width detected ($width), clearing loading overlay',
          );
          setState(() => _isLoading = false);
        }
      }),
    );

    _playerSubscriptions.add(
      _player.stream.error.listen((error) async {
        if (!mounted) return;
        if (error.isEmpty) return;

        debugPrint('MediaKitPlayer Error Stream: $error');

        // For LIVE TV: never reload the stream on errors — mpv handles recovery internally.
        // Only show fatal errors that truly stop playback (detected by watchdog after 2min).
        if (widget.streamType == model.StreamType.live) {
          debugPrint(
            'MediaKitPlayer: Live — ignoring error (mpv handles internally): $error',
          );
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
      }),
    );

    // Listen for stream completion
    _playerSubscriptions.add(
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
      }),
    );

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
    if (!mounted) return;
    // The clock ticks every second but only changes once a minute; the
    // notifier only wakes its listeners (the plates) when the value differs.
    _clock.value = formatClock(DateTime.now());
  }

  @override
  void deactivate() {
    // Stop player when widget is being removed from tree
    _player.stop();
    super.deactivate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is deliberately NOT handled: on Android it fires for transient
    // interruptions (notification shade, incoming-call banner, permission
    // dialog, split-screen resize). Treating it as "backgrounded" killed
    // playback every time the user swiped the shade down.
    final isBackgrounded = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (!isBackgrounded) return;

    _releasePlayback();

    // Exit the player screen so the user comes back to the dashboard rather
    // than to a frozen frame.
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  /// Fully stop playback and release the decoder.
  ///
  /// Android reclaims MediaCodec instances from backgrounded apps: holding one
  /// while hidden is what leaves the app with a dead surface (black screen, no
  /// audio) on return. Stopping releases it deterministically, and also drops
  /// the network reader so no bandwidth is consumed in the background.
  void _releasePlayback() {
    if (_isReleased) return;
    _stopPlayback();
    WakelockPlus.disable();
  }

  /// Stops the stream for good (resume position saved) without touching the
  /// wakelock: used before handing over to another player screen, so that
  /// the subscription's single connection is free when it opens.
  void _stopPlayback() {
    if (_isReleased) return;
    _isReleased = true;

    // Kill the timers first: a watchdog firing mid-release would call
    // _loadStream() and restart the stream we are tearing down.
    _liveWatchdog?.cancel();
    _liveWatchdog = null;
    _epgTimer?.cancel();
    _epgTimer = null;
    _controlsTimer?.cancel();
    _controlsTimer = null;
    _zapTimer?.cancel();
    _zapTimer = null;
    _stopClock();

    if (widget.streamType != model.StreamType.live) {
      _saveResumePositionOnExit();
    }

    _player.stop();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Unregister keyboard handler
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);

    // Disable wakelock when leaving player (unless another player screen
    // already took over: next episode, deinterlace)
    _liveScreens--;
    if (_liveScreens <= 0) {
      _liveScreens = 0;
      WakelockPlus.disable();
    }

    // Save resume position before cleanup (only for VOD/Series).
    // Skipped when _releasePlayback already did it on backgrounding.
    if (!_isReleased) {
      _saveResumePositionOnExit();
    }

    _clockTimer?.cancel();
    _controlsTimer?.cancel();
    _epgTimer?.cancel();
    _liveWatchdog?.cancel();
    _channelListTimer?.cancel();
    _channelListScrollController.dispose();
    _zapTimer?.cancel();
    _toastTimer?.cancel();
    _bufferingTimer?.cancel();

    // Detach from the player streams BEFORE disposing it, so no late event can
    // land on a deactivated element.
    for (final subscription in _playerSubscriptions) {
      subscription.cancel();
    }
    _playerSubscriptions.clear();

    // Stop playback first to prevent audio continuing in background
    _player.stop();
    _player.dispose();
    _xtreamService?.dispose();

    // [P1-3 FIX] Dispose all focus nodes ONCE (was being disposed twice, causing crash)
    _playPauseFocusNode.dispose();
    _prevFocusNode.dispose();
    _nextFocusNode.dispose();
    _sliderFocusNode.dispose();
    _formatFocusNode.dispose();
    _channelListButtonFocusNode.dispose();
    _retryFocusNode.dispose();
    _channelListItemFocusNode.dispose();

    _progress.dispose();
    _clock.dispose();
    _toast.dispose();
    _reconnectLabel.dispose();
    _bufferingVisible.dispose();

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
        _showToast(
          'Reprise à ${formatPlayerTime(Duration(seconds: positionSeconds))}',
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
    if (!mounted || _isReleased) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _reconnectLabel.value = null;
      setState(() {
        _errorMessage = 'Flux interrompu après plusieurs tentatives';
        _isLoading = false;
      });
      return;
    }

    _reconnectAttempts++;
    _reconnectLabel.value = '$_reconnectAttempts / $_maxReconnectAttempts';
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
      if (!mounted || _isReleased) return;

      // Si le player joue et la position avance : tout va bien, reset
      if (_isPlaying && _lastPositionChangeTime != null) {
        final stallSecs =
            DateTime.now().difference(_lastPositionChangeTime!).inSeconds;
        if (stallSecs < 5) return; // Position avance normalement
      }

      // Calculer la durée réelle de gel (basée sur la position, pas sur _isPlaying)
      final stallSecs = _lastPositionChangeTime != null
          ? DateTime.now().difference(_lastPositionChangeTime!).inSeconds
          : 9999;

      debugPrint(
        'MediaKitPlayer: Watchdog — position gelée depuis ${stallSecs}s',
      );

      // Ne reconnecte QUE si vraiment gelé depuis > 60s (les cache-pauses sont < 5s)
      // Cela laisse mpv's reconnect interne (stream-lavf-o) gérer les coupures courtes
      if (stallSecs > 60) {
        debugPrint(
          'MediaKitPlayer: Watchdog — gel de 60s confirmé, reconnexion forcée',
        );
        _lastPositionChangeTime =
            DateTime.now(); // Éviter re-déclenchement immédiat
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

      // Resolve DNS and open (then drop) a bare socket to the panel host so
      // mpv's first request skips resolution and the TCP/TLS handshake.
      // Capped hard: playback must never wait more than a moment on this.
      await _xtreamService!.prewarmHost().timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () {},
          );

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

  String get _currentStreamId =>
      _hasChannels ? widget.channels![_currentIndex].streamId : widget.streamId;

  // ... (existing initState)

  Future<void> _loadStream({Duration? startAt}) async {
    try {
      if (_xtreamService == null) return;
      // The app went to background while a (re)load was queued — do not bring
      // the stream back up behind the user.
      if (_isReleased || !mounted) return;
      _zapTimer?.cancel();

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
          debugPrint(
            'MediaKitPlayer: Loading Timeout reached, forcing Visibility',
          );
          setState(() => _isLoading = false);
        }
      });

      // Determine effective Stream ID
      final currentStreamId = _currentStreamId;

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
      final service =
          await ref.read(mobileXtreamServiceProvider(widget.playlist).future);
      final epg = await service.getShortEPG(streamId);
      // Zapping fast: a late answer for a channel left behind is dropped.
      if (mounted && streamId == _currentStreamId) {
        setState(() => _epg = epg);
      }
    } catch (e) {
      debugPrint('Error loading EPG: $e');
    }
  }

  void _playNext() => _zapBy(1);

  void _playPrevious() => _zapBy(-1);

  /// Next / previous channel. A single press loads at once; presses in
  /// quick succession (or a held key) only move the plate, and the stream
  /// loads once the remote has rested for 400 ms.
  void _zapBy(int delta) {
    if (!_hasChannels) return;
    final count = widget.channels!.length;
    final index = ((_currentIndex + delta) % count + count) % count;
    final now = DateTime.now();
    final rapid = _lastZapAt != null &&
        now.difference(_lastZapAt!) < const Duration(milliseconds: 400);
    _lastZapAt = now;
    if (!rapid && !(_zapTimer?.isActive ?? false)) {
      _switchChannel(index);
      return;
    }
    _zapTimer?.cancel();
    setState(() {
      _currentIndex = index;
      _epg = null;
      _isReconnecting = true;
      _showChannelList = false;
      if (_osd == _Osd.hidden) _osd = _Osd.info;
    });
    _loadEpg(_currentStreamId);
    _resetControlsTimer();
    _zapTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted && !_isReleased) _loadStream();
    });
  }

  void _switchChannel(int index) {
    _zapTimer?.cancel();
    _channelListTimer?.cancel();
    setState(() {
      _currentIndex = index;
      _showChannelList = false; // close sidebar on switch
      // TV: the compact plate (the row of buttons stays if it was open, focus
      // on the button just pressed). Touch: the controls.
      if (_osd == _Osd.hidden) _osd = _Osd.info;
    });
    _resetControlsTimer();
    _loadStream();
  }

  /// Open/close the channel list sidebar
  void _toggleChannelList() {
    if (!_hasChannels) return;
    final open = !_showChannelList;
    setState(() {
      _showChannelList = open;
      // The list replaces the plate: one panel over the picture at a time.
      if (open) {
        _osd = _Osd.hidden;
        _vodRow = false;
      }
    });
    if (open) {
      _controlsTimer?.cancel();
      _scrollToCurrentChannel();
      _restartChannelListTimer();
      // Focus direct sur la chaîne en cours : la télécommande navigue dans la
      // liste sans étape intermédiaire. Second essai après l'animation de
      // scroll (300 ms), l'item actif pouvant ne pas encore être construit.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showChannelList) {
          _channelListItemFocusNode.requestFocus();
        }
      });
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted &&
            _showChannelList &&
            !_channelListItemFocusNode.hasFocus) {
          _channelListItemFocusNode.requestFocus();
        }
      });
    } else {
      _channelListTimer?.cancel();
    }
  }

  void _closeChannelList() {
    _channelListTimer?.cancel();
    if (_showChannelList) setState(() => _showChannelList = false);
  }

  /// (Re)arme l'auto-fermeture de la sidebar. Relancé à chaque interaction
  /// (focus D-pad, scroll) pour ne pas fermer la liste sous les doigts.
  void _restartChannelListTimer() {
    _channelListTimer?.cancel();
    _channelListTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _showChannelList = false);
    });
  }

  /// Scroll channel list to keep current channel visible
  void _scrollToCurrentChannel() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_channelListScrollController.hasClients) return;
      const itemHeight = ChannelListPlate.itemExtent;
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

  /// VOD: ±[seconds], from the last known position (presses add up before
  /// mpv reports the new one).
  void _seekBy(int seconds) {
    var target = _position + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target >= _duration) return;
    _position = target;
    _player.seek(target);
    _progress.value = _currentProgress;
    _resetControlsTimer();
  }

  void _toggleControls() {
    // Always show controls on tap, then start auto-hide timer
    if (!_showControls) {
      _onUserInteraction();
      return;
    }
    _resetControlsTimer();
  }

  void _toggleStats() {
    final current = ref.read(mobileSettingsProvider).showDebugStats;
    ref.read(mobileSettingsProvider.notifier).toggleShowDebugStats(!current);
    _resetControlsTimer();
  }

  /// Back to the Lite player (deinterlace forced for this channel).
  void _disableDeinterlace() {
    final streamId =
        widget.channels?[_currentIndex].streamId ?? widget.streamId;
    ref
        .read(mobileSettingsProvider.notifier)
        .toggleChannelDeinterlace(streamId);
    // Free the connection before the other player opens it.
    _stopPlayback();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LitePlayerScreen(
          streamId: streamId,
          title: widget.channels?[_currentIndex].name ?? widget.title,
          playlist: widget.playlist,
          streamType: widget.streamType,
          channels: widget.channels,
          initialIndex: _currentIndex,
        ),
      ),
    );
  }

  // ─── Episodes ───────────────────────────────────────────────────────────────

  int get _episodeIndex =>
      widget.episodes?.indexWhere((e) => e.id == widget.streamId) ?? -1;

  model.Episode? get _currentEpisode {
    final i = _episodeIndex;
    return i < 0 ? null : widget.episodes![i];
  }

  model.Episode? get _nextEpisode {
    final i = _episodeIndex;
    if (i < 0 || i + 1 >= widget.episodes!.length) return null;
    return widget.episodes![i + 1];
  }

  /// Plays the next episode in place of this one (its resume position is
  /// picked up as usual).
  void _playNextEpisode() {
    final next = _nextEpisode;
    if (next == null) return;
    _stopPlayback(); // saves this episode's position, frees the connection
    final series = widget.seriesName ?? '';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => NativePlayerScreen(
          streamId: next.id,
          title: '$series S${next.season}E${next.episodeNum}'.trim(),
          playlist: widget.playlist,
          streamType: widget.streamType,
          containerExtension: next.containerExtension,
          seriesId: widget.seriesId,
          season: int.tryParse(next.season),
          episodeNum: next.episodeNum,
          episodes: widget.episodes,
          seriesName: widget.seriesName,
        ),
      ),
    );
  }

  /// VOD plate: main title and the line beside it. Series: the episode title
  /// when it says something, then « Série · S1 · É4 ».
  (String, String?) get _vodTitles {
    final series = widget.seriesName?.trim() ?? '';
    if (widget.streamType != model.StreamType.series ||
        series.isEmpty ||
        widget.season == null ||
        widget.episodeNum == null) {
      return (widget.title, null);
    }
    final se = 'S${widget.season} · É${widget.episodeNum}';
    final episodeTitle = _currentEpisode?.title.trim() ?? '';
    final meaningful = episodeTitle.isNotEmpty &&
        !episodeTitle.toLowerCase().contains(series.toLowerCase()) &&
        !RegExp(r'^(episode|épisode|ep\.?|e)\s*\d+$', caseSensitive: false)
            .hasMatch(episodeTitle);
    return meaningful ? (episodeTitle, '$series · $se') : (series, se);
  }

  // ─── Tracks ─────────────────────────────────────────────────────────────────

  /// mpv ids of the tracks really playing (`aid` / `sid`; media_kit only
  /// knows them once set by hand).
  String? _activeAudioId;
  String? _activeSubtitleId;

  List<AudioTrack> get _audioTracks => _player.state.tracks.audio
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();

  List<SubtitleTrack> get _subtitleTracks => _player.state.tracks.subtitle
      .where((t) => t.id != 'auto' && t.id != 'no')
      .toList();

  Future<void> _refreshActiveTracks() async {
    try {
      final platform = _player.platform as dynamic;
      final aid = await platform?.getProperty('aid') as String?;
      final sid = await platform?.getProperty('sid') as String?;
      if (!mounted) return;
      if (aid != _activeAudioId || sid != _activeSubtitleId) {
        setState(() {
          _activeAudioId = aid;
          _activeSubtitleId = sid;
        });
      }
    } catch (_) {}
  }

  String _trackName(String? language, String? title, int index) =>
      languageName(language) ??
      (title != null && title.trim().isNotEmpty
          ? title.trim()
          : 'Piste ${index + 1}');

  /// « Audio · Français · 1 sur 2 ».
  String get _audioLabel {
    final tracks = _audioTracks;
    if (tracks.isEmpty) return 'Audio · aucune piste';
    final i = tracks.indexWhere((t) => t.id == _activeAudioId);
    if (i < 0) return 'Audio';
    final name = _trackName(tracks[i].language, tracks[i].title, i);
    return tracks.length > 1
        ? 'Audio · $name · ${i + 1} sur ${tracks.length}'
        : 'Audio · $name';
  }

  String get _subtitleValue {
    final tracks = _subtitleTracks;
    final i = tracks.indexWhere((t) => t.id == _activeSubtitleId);
    if (i < 0) return 'désactivés';
    return _trackName(tracks[i].language, tracks[i].title, i);
  }

  Future<void> _cycleAudioTrack() async {
    final tracks = _audioTracks;
    if (tracks.isEmpty) {
      _showToast('Aucune piste audio détectée');
      return;
    }

    final current = tracks.indexWhere((t) => t.id == _activeAudioId);
    final nextTrack = tracks[(current + 1) % tracks.length];

    await _player.setAudioTrack(nextTrack);
    await _refreshActiveTracks();
    _resetControlsTimer();

    // TV: the lit button already shows it.
    if (mounted && !_isTv) _showToast(_audioLabel);
  }

  /// Off → first track → … → last → off.
  Future<void> _cycleSubtitleTrack() async {
    final tracks = _subtitleTracks;
    if (tracks.isEmpty) return;
    final i = tracks.indexWhere((t) => t.id == _activeSubtitleId);
    await _player.setSubtitleTrack(
      i + 1 >= tracks.length ? SubtitleTrack.no() : tracks[i + 1],
    );
    await _refreshActiveTracks();
    _resetControlsTimer();
    if (mounted && !_isTv) _showToast('Sous-titres · $_subtitleValue');
  }

  // ─── Remote control ─────────────────────────────────────────────────────────

  static bool _isSelectKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA;

  /// Handle keyboard/remote control events.
  ///
  /// Runs before the focus system, which still receives the key afterwards:
  /// returning false leaves it to the focused button; the plates swallow the
  /// keys they must not see as navigation.
  bool _handleKeyEvent(KeyEvent event) {
    final isRepeat = event is KeyRepeatEvent;
    if (event is! KeyDownEvent && !isRepeat) return false;
    // A sheet or another screen on top: not ours.
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;

    try {
      final key = event.logicalKey;
      final up = key == LogicalKeyboardKey.arrowUp;
      final down = key == LogicalKeyboardKey.arrowDown;
      final left = key == LogicalKeyboardKey.arrowLeft;
      final right = key == LogicalKeyboardKey.arrowRight;
      final back =
          key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack;

      // Held keys: zapping (live) and seeking (VOD, plate hidden) follow.
      if (isRepeat) {
        if (_isLive &&
            _hasChannels &&
            _errorMessage == null &&
            !_showChannelList &&
            (up || down)) {
          _zapBy(up ? -1 : 1);
          return true;
        }
        if (!_isLive &&
            !_showControls &&
            _errorMessage == null &&
            (left || right)) {
          _seekBy(left ? -10 : 10);
          _openVod();
          return true;
        }
        return false;
      }

      // Sidebar ouverte : Back/Menu la ferment (◀ aussi, voir la liste), le
      // reste part au système de Focus (navigation + OK sur un item). On
      // relance juste l'auto-fermeture.
      if (_showChannelList) {
        if (back ||
            key == LogicalKeyboardKey.contextMenu ||
            key == LogicalKeyboardKey.keyM) {
          _closeChannelList();
          return true;
        }
        _restartChannelListTimer();
        return false;
      }

      // Error plate: its buttons take ◀ ▶ OK; Back leaves; ▲▼ still zap.
      if (_errorMessage != null) {
        if (back) {
          Navigator.of(context).pop();
          return true;
        }
        if (_isLive && _hasChannels && (up || down)) {
          _zapBy(up ? -1 : 1);
          return true;
        }
        return false;
      }

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

      if (key == LogicalKeyboardKey.mediaPlayPause) {
        _togglePlayPause();
        return true;
      }

      // OK
      if (_isSelectKey(key)) {
        if (!_showControls) {
          if (_isLive) {
            // Live: the buttons, focus on « Chaînes » — never a pause.
            _openLiveActions();
          } else {
            // VOD: pause / play and the plate, focus on the bar.
            _togglePlayPause();
            _openVod();
          }
          return true;
        }
        if (_isLive && _osd == _Osd.info) {
          _openLiveActions();
          return true;
        }
        _resetControlsTimer();
        return false; // the focused button or the bar
      }

      // Infos techniques
      if (key == LogicalKeyboardKey.digit0) {
        _toggleStats();
        return true;
      }

      // ◀ ▶: live, the compact plate; VOD, ±10 s with the bar.
      if (left || right) {
        if (!_showControls) {
          if (_isLive) {
            _showLiveInfo();
          } else {
            _seekBy(left ? -10 : 10);
            _openVod();
          }
          return true;
        }
        _resetControlsTimer();
        if (_isLive && _osd == _Osd.info) return true;
        return false; // move along the row / seek on the bar
      }

      // ▲ ▼: live, zapping (the focus does not move); VOD, the plate.
      if (up || down) {
        if (_isLive && _hasChannels) {
          _zapBy(up ? -1 : 1);
          return true;
        }
        if (!_showControls) {
          if (_isLive) {
            _showLiveInfo();
          } else {
            _openVod();
          }
          return true;
        }
        _resetControlsTimer();
        return false;
      }

      // Channel Down = Previous Channel (inverted as requested)
      if (key == LogicalKeyboardKey.channelDown) {
        if (_isLive && _hasChannels) {
          _playPrevious();
          return true;
        }
      }

      // Channel Up = Next Channel (inverted as requested)
      if (key == LogicalKeyboardKey.channelUp) {
        if (_isLive && _hasChannels) {
          _playNext();
          return true;
        }
      }

      // Menu key or 'M' → toggle channel list sidebar
      if (key == LogicalKeyboardKey.contextMenu ||
          key == LogicalKeyboardKey.keyM) {
        if (_isLive && _hasChannels) {
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
      if (back) {
        // If controls are visible, close them first
        if (_showControls) {
          _hideControls();
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

  /// Live plate with its buttons: ▲▼ zap (handled above), the focus stays.
  KeyEventResult _swallowUpDown(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    return key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// VOD bar: ◀ ▶ ±10 s, OK pause / play, ▼ the buttons.
  KeyEventResult _onBarKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (down || event is KeyRepeatEvent) {
        _seekBy(key == LogicalKeyboardKey.arrowLeft ? -10 : 10);
      }
      return KeyEventResult.handled;
    }
    if (_isSelectKey(key)) {
      if (down) _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (down) _openVod(row: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  /// VOD buttons: ▲ back to the bar.
  KeyEventResult _onVodRowKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      if (event is KeyDownEvent) _openVod();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final aspectMode =
        ref.watch(mobileSettingsProvider.select((s) => s.aspectRatioMode));
    final tv = _isTv;

    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor:
            Colors.black, // [V5.2 Fix] Enforce black background globally
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_showChannelList) {
              _closeChannelList();
            } else {
              _toggleControls();
            }
          },
          onPanDown: (_) => _onUserInteraction(),
          onPanUpdate: (_) => _onUserInteraction(),
          // Swipe from right edge → open channel list
          onHorizontalDragEnd: (details) {
            if (_isLive &&
                _hasChannels &&
                details.primaryVelocity != null &&
                details.primaryVelocity! < -300) {
              _toggleChannelList();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The video stays, even on error: the last picture remains
              // under the error plate.
              Center(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls, // We use our own custom controls
                  fit: _getBoxFit(aspectMode),
                ),
              ),

              // First load: nothing to show yet.
              if (_isLoading && _errorMessage == null)
                const ColoredBox(color: Colors.black),

              if (_errorMessage == null)
                ...(tv ? _buildTvOsd(aspectMode) : _buildTouchOsd(aspectMode)),

              if (_errorMessage != null) _buildErrorPlate(tv),

              // [TiviMate] Channel list sidebar
              if (_showChannelList && _isLive && _hasChannels)
                _buildChannelList(tv),

              // Infos techniques (top left) - isolated to prevent rebuilds
              Positioned(
                top: tv ? 32 : (_showControls ? 68 : 12),
                left: tv ? 48 : 44,
                child: StatsOverlayWidget(
                  player: _player,
                  formatLabel: _formatLabel(aspectMode),
                ),
              ),

              _buildStatusPill(tv),
              _buildToast(tv),
            ],
          ),
        ),
      ),
    );
  }

  LiveOsdInfo _liveInfo(String clock) {
    final ch = _hasChannels ? widget.channels![_currentIndex] : null;
    return LiveOsdInfo.from(
      channel: ch,
      fallbackName: widget.title,
      number: _channelNumber,
      epg: _epg,
      clock: clock,
      connecting: _isLoading || _isReconnecting,
    );
  }

  String get _channelNumber {
    if (!_hasChannels) return '';
    final ch = widget.channels![_currentIndex];
    return ch.num.isNotEmpty ? ch.num : '${_currentIndex + 1}';
  }

  /// Buttons separated by 10 dp: the lit halo (8 dp, ×1.06) stays clear of
  /// its neighbours.
  static List<Widget> _spaced(List<Widget> items) => [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0 &&
              items[i] is! OsdSeparator &&
              items[i - 1] is! OsdSeparator)
            const SizedBox(width: 10),
          if (items[i] is OsdSeparator) const SizedBox(width: 6),
          items[i],
          if (items[i] is OsdSeparator) const SizedBox(width: 6),
        ],
      ];

  List<Widget> _buildTvOsd(String aspectMode) {
    if (!_showControls) return const [];
    final statsOn =
        ref.watch(mobileSettingsProvider.select((s) => s.showDebugStats));
    final statsButton = OsdButton(
      key: const ValueKey('osd-stats'),
      icon: Icons.ssid_chart_rounded,
      label: statsOn ? 'Infos techniques · affichées' : 'Infos techniques',
      onPressed: _toggleStats,
      onFocus: _resetControlsTimer,
    );
    final audioButton = OsdButton(
      key: const ValueKey('osd-audio'),
      icon: Icons.graphic_eq_rounded,
      label: _audioLabel,
      onPressed: _cycleAudioTrack,
      onFocus: _resetControlsTimer,
    );
    final subtitleButton = _subtitleTracks.isEmpty
        ? null
        : OsdButton(
            key: const ValueKey('osd-subtitles'),
            icon: Icons.subtitles_outlined,
            label: 'Sous-titres · $_subtitleValue',
            onPressed: _cycleSubtitleTrack,
            onFocus: _resetControlsTimer,
          );
    final formatButton = OsdButton(
      key: const ValueKey('osd-format'),
      icon: Icons.fit_screen_outlined,
      label: 'Format · ${_formatLabel(aspectMode)}',
      focusNode: _formatFocusNode,
      onPressed: () => _cycleAspectRatio(announce: false),
      onFocus: _resetControlsTimer,
    );
    final playPause = OsdButton(
      key: const ValueKey('osd-play'),
      icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      label: _isPlaying ? 'Pause' : 'Lecture',
      focusNode: _playPauseFocusNode,
      onPressed: _togglePlayPause,
      onFocus: _resetControlsTimer,
      iconSize: 22,
    );

    if (_isLive) {
      final withActions = _osd == _Osd.actions;
      final width = MediaQuery.sizeOf(context).width - 96;
      Widget? row;
      if (withActions) {
        final next = _epg?.next;
        final nextStart = next?.startTime;
        row = Row(
          children: [
            ..._spaced([
              if (_hasChannels)
                OsdButton(
                  key: const ValueKey('osd-prev'),
                  icon: Icons.skip_previous_rounded,
                  label: 'Chaîne précédente',
                  focusNode: _prevFocusNode,
                  onPressed: _playPrevious,
                  onFocus: _resetControlsTimer,
                  iconSize: 22,
                ),
              playPause,
              if (_hasChannels)
                OsdButton(
                  key: const ValueKey('osd-next'),
                  icon: Icons.skip_next_rounded,
                  label: 'Chaîne suivante',
                  focusNode: _nextFocusNode,
                  onPressed: _playNext,
                  onFocus: _resetControlsTimer,
                  iconSize: 22,
                ),
              const OsdSeparator(),
              if (_hasChannels)
                OsdButton(
                  key: const ValueKey('osd-channels'),
                  icon: Icons.playlist_play_rounded,
                  label: 'Chaînes',
                  focusNode: _channelListButtonFocusNode,
                  onPressed: _toggleChannelList,
                  onFocus: _resetControlsTimer,
                  iconSize: 22,
                ),
              audioButton,
              if (subtitleButton != null) subtitleButton,
              formatButton,
              if (widget.forceDeinterlace)
                OsdButton(
                  key: const ValueKey('osd-deinterlace'),
                  icon: Icons.table_rows_outlined,
                  label: 'Désentrelacement',
                  onPressed: _disableDeinterlace,
                  onFocus: _resetControlsTimer,
                ),
              statsButton,
            ]),
            Expanded(
              child: next == null || nextStart == null || next.title.isEmpty
                  ? const SizedBox.shrink()
                  : OsdUpNext(time: formatClock(nextStart), title: next.title),
            ),
          ],
        );
      }
      return [
        Positioned(
          left: 48,
          bottom: 32,
          right: withActions ? 48 : null,
          width: withActions ? null : (width < 680 ? width : 680),
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: withActions ? _swallowUpDown : null,
            child: ValueListenableBuilder<String>(
              valueListenable: _clock,
              builder: (context, clock, _) =>
                  LivePlate(info: _liveInfo(clock), actions: row),
            ),
          ),
        ),
      ];
    }

    // VOD
    final (title, subtitle) = _vodTitles;
    final nextEpisode = _nextEpisode;
    return [
      Positioned(
        left: 48,
        right: 48,
        bottom: 32,
        child: ListenableBuilder(
          listenable: _sliderFocusNode,
          builder: (context, _) => VodPlate(
            title: title,
            subtitle: subtitle,
            progress: _progress,
            barLit: _sliderFocusNode.hasFocus,
            barWrapper: (child) => Focus(
              focusNode: _sliderFocusNode,
              onKeyEvent: _onBarKey,
              child: child,
            ),
            actions: !_vodRow
                ? null
                : Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onVodRowKey,
                    child: Row(
                      children: [
                        ..._spaced([
                          OsdButton(
                            key: const ValueKey('osd-back10'),
                            icon: Icons.replay_10_rounded,
                            label: '−10 s',
                            focusNode: _prevFocusNode,
                            onPressed: () => _seekBy(-10),
                            onFocus: _resetControlsTimer,
                            iconSize: 22,
                          ),
                          playPause,
                          OsdButton(
                            key: const ValueKey('osd-fwd10'),
                            icon: Icons.forward_10_rounded,
                            label: '+10 s',
                            focusNode: _nextFocusNode,
                            onPressed: () => _seekBy(10),
                            onFocus: _resetControlsTimer,
                            iconSize: 22,
                          ),
                          const OsdSeparator(),
                          audioButton,
                          if (subtitleButton != null) subtitleButton,
                          formatButton,
                          statsButton,
                        ]),
                        const Spacer(),
                        if (nextEpisode != null)
                          OsdButton(
                            key: const ValueKey('osd-next-episode'),
                            icon: Icons.skip_next_rounded,
                            label: 'Épisode suivant · '
                                'S${nextEpisode.season} É${nextEpisode.episodeNum}',
                            onPressed: _playNextEpisode,
                            onFocus: _resetControlsTimer,
                            iconSize: 22,
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ];
  }

  /// Touch: two pills at the top, three round buttons in the middle, a
  /// plate at the bottom. No veil over the picture.
  List<Widget> _buildTouchOsd(String aspectMode) {
    if (!_showControls) return const [];
    final pad = MediaQuery.paddingOf(context);
    final left = pad.left > 44 ? pad.left : 44.0;
    final right = pad.right > 44 ? pad.right : 44.0;
    final top = pad.top > 12 ? pad.top : 12.0;
    final bottom = pad.bottom > 12 ? pad.bottom : 12.0;

    String topTitle;
    if (_isLive) {
      final ch = _hasChannels ? widget.channels![_currentIndex] : null;
      final name = ch?.name ?? widget.title;
      topTitle = _channelNumber.isEmpty ? name : '$_channelNumber · $name';
    } else {
      final (title, _) = _vodTitles;
      topTitle = widget.streamType == model.StreamType.series &&
              widget.season != null &&
              widget.episodeNum != null &&
              (widget.seriesName?.isNotEmpty ?? false)
          ? '$title · S${widget.season} · É${widget.episodeNum}'
          : title;
    }

    final topBar = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TouchPill(
              padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TouchIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Retour',
                    width: 36,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      topTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.body(
                        fontSize: 15,
                        height: 1.33,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        TouchPill(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLive)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
                  child: ValueListenableBuilder<String>(
                    valueListenable: _clock,
                    builder: (context, clock, _) => Text(
                      clock,
                      style: AppTheme.body(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                        fontFeatures: AppTheme.tabular,
                      ),
                    ),
                  ),
                ),
              if (_isLive && _hasChannels)
                TouchIconButton(
                  icon: Icons.playlist_play_rounded,
                  tooltip: 'Chaînes',
                  onPressed: _toggleChannelList,
                ),
              TouchIconButton(
                icon: Icons.graphic_eq_rounded,
                tooltip: 'Audio',
                onPressed: _cycleAudioTrack,
              ),
              if (!_isLive && _subtitleTracks.isNotEmpty)
                TouchIconButton(
                  icon: Icons.subtitles_outlined,
                  tooltip: 'Sous-titres',
                  onPressed: _cycleSubtitleTrack,
                ),
              TouchIconButton(
                icon: Icons.fit_screen_outlined,
                tooltip: 'Format',
                onPressed: _cycleAspectRatio,
              ),
              TouchIconButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Plus',
                onPressed: _showMoreSheet,
              ),
            ],
          ),
        ),
      ],
    );

    final middle = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TouchCircleButton(
          icon: _isLive ? Icons.skip_previous_rounded : Icons.replay_10_rounded,
          tooltip: _isLive ? 'Chaîne précédente' : '−10 s',
          onPressed: _isLive ? _playPrevious : () => _seekBy(-10),
          iconSize: 22,
        ),
        const SizedBox(width: 40),
        TouchCircleButton(
          icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          tooltip: _isPlaying ? 'Pause' : 'Lecture',
          onPressed: _togglePlayPause,
          size: 56,
          iconSize: 26,
        ),
        const SizedBox(width: 40),
        TouchCircleButton(
          icon: _isLive ? Icons.skip_next_rounded : Icons.forward_10_rounded,
          tooltip: _isLive ? 'Chaîne suivante' : '+10 s',
          onPressed: _isLive ? _playNext : () => _seekBy(10),
          iconSize: 22,
        ),
      ],
    );

    return [
      Positioned(top: top, left: left, right: right, child: topBar),
      if (!_isLive || _hasChannels) Center(child: middle),
      if (_isLive && !_hasChannels)
        Center(
          child: TouchCircleButton(
            icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: _isPlaying ? 'Pause' : 'Lecture',
            onPressed: _togglePlayPause,
            size: 56,
            iconSize: 26,
          ),
        ),
      Positioned(
        left: left,
        right: right,
        bottom: bottom,
        child: _isLive
            ? ValueListenableBuilder<String>(
                valueListenable: _clock,
                builder: (context, clock, _) =>
                    PhoneLivePlate(info: _liveInfo(clock)),
              )
            : PhoneVodPlate(
                progress: _progress,
                onSeek: (target) {
                  _position = target;
                  _player.seek(target);
                  _progress.value = _currentProgress;
                  _resetControlsTimer();
                },
                onInteraction: _resetControlsTimer,
                onNextEpisode: _nextEpisode == null ? null : _playNextEpisode,
              ),
      ),
    ];
  }

  /// ⋯ on touch screens: what has no room in the top pill.
  Future<void> _showMoreSheet() async {
    _controlsTimer?.cancel();
    final statsOn = ref.read(mobileSettingsProvider).showDebugStats;
    final next = _nextEpisode;
    await showAppSheet<void>(
      context,
      title: 'Options',
      builder: (sheetContext) {
        void run(VoidCallback action) {
          Navigator.pop(sheetContext);
          action();
        }

        final tiles = <Widget>[
          if (_isLive && _subtitleTracks.isNotEmpty)
            AppDialogTile(
              icon: Icons.subtitles_outlined,
              label: 'Sous-titres',
              value: _subtitleValue,
              onPressed: () => run(_cycleSubtitleTrack),
            ),
          AppDialogTile(
            icon: Icons.ssid_chart_rounded,
            label: 'Infos techniques',
            value: statsOn ? 'Affichées' : 'Masquées',
            onPressed: () => run(_toggleStats),
          ),
          if (widget.forceDeinterlace)
            AppDialogTile(
              icon: Icons.table_rows_outlined,
              label: 'Désentrelacement',
              value: 'Activé · revenir au lecteur Lite',
              onPressed: () => run(_disableDeinterlace),
            ),
          if (!_isLive && next != null)
            AppDialogTile(
              icon: Icons.skip_next_rounded,
              label: 'Épisode suivant',
              value: 'S${next.season} · É${next.episodeNum}',
              onPressed: () => run(_playNextEpisode),
            ),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              tiles[i],
            ],
          ],
        );
      },
    );
    if (mounted) _resetControlsTimer();
  }

  Widget _buildErrorPlate(bool tv) {
    final e = describePlayerError(
      _errorMessage!,
      isLive: _isLive,
      prefix: _channelNumber,
    );
    final plate = ErrorPlate(
      title: e.title,
      detail: e.detail,
      actions: [
        OsdButton(
          key: const ValueKey('error-retry'),
          icon: Icons.refresh_rounded,
          label: 'Réessayer',
          alwaysLabel: true,
          autofocus: tv,
          focusNode: _retryFocusNode,
          onPressed: () {
            _reconnectAttempts = 0;
            _loadStream();
          },
        ),
        if (_isLive && _hasChannels)
          OsdButton(
            key: const ValueKey('error-next'),
            icon: Icons.skip_next_rounded,
            label: 'Chaîne suivante',
            alwaysLabel: true,
            onPressed: _playNext,
          ),
        OsdButton(
          key: const ValueKey('error-back'),
          icon: Icons.arrow_back_rounded,
          label: 'Retour',
          alwaysLabel: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
    if (tv) {
      return Positioned(left: 48, right: 48, bottom: 32, child: plate);
    }
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      left: pad.left > 44 ? pad.left : 44,
      right: pad.right > 44 ? pad.right : 44,
      bottom: pad.bottom > 12 ? pad.bottom : 12,
      child: plate,
    );
  }

  Widget _buildChannelList(bool tv) {
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      top: tv ? 32 : (pad.top > 12 ? pad.top : 12),
      bottom: tv ? 32 : (pad.bottom > 12 ? pad.bottom : 12),
      right: tv ? 48 : (pad.right > 44 ? pad.right : 44),
      width: 280,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        // ◀ closes the list (it sits on the right); ▶ goes nowhere.
        onKeyEvent: (node, event) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            if (event is KeyDownEvent) _closeChannelList();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          // A tap on the list's header must not close it.
          behavior: HitTestBehavior.opaque,
          onTap: _restartChannelListTimer,
          child: ChannelListPlate(
            playlist: widget.playlist,
            channels: widget.channels!,
            currentIndex: _currentIndex,
            currentFocusNode: _channelListItemFocusNode,
            controller: _channelListScrollController,
            onSelect: _switchChannel,
            onActivity: _restartChannelListTimer,
          ),
        ),
      ),
    );
  }

  /// « Reconnexion 2 / 5 », « Connexion… » (when no plate says it), and
  /// « Mise en mémoire tampon… » when buffering lasts.
  Widget _buildStatusPill(bool tv) {
    return Positioned(
      top: tv ? 32 : (_showControls ? 68 : 12),
      right: tv ? 48 : 44,
      child: AnimatedBuilder(
        animation: Listenable.merge([_reconnectLabel, _bufferingVisible]),
        builder: (context, _) {
          if (_errorMessage != null || _showChannelList) {
            return const SizedBox.shrink();
          }
          final reconnect = _reconnectLabel.value;
          if (reconnect != null) {
            return OsdStatusPill(text: 'Reconnexion', detail: reconnect);
          }
          final connecting = _isLoading || _isReconnecting;
          if (connecting && !(_isLive && _showControls)) {
            return OsdStatusPill(
              text: _isLive ? 'Connexion…' : 'Chargement…',
            );
          }
          if (!connecting && _bufferingVisible.value) {
            return const OsdStatusPill(text: 'Mise en mémoire tampon…');
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildToast(bool tv) {
    return Positioned(
      top: tv ? 32 : (_showControls ? 68 : 12),
      left: 0,
      right: 0,
      child: Center(
        child: ValueListenableBuilder<String?>(
          valueListenable: _toast,
          builder: (context, text, _) =>
              text == null ? const SizedBox.shrink() : PlayerToast(text: text),
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

  static String _formatLabel(String mode) => switch (mode) {
        'cover' => 'Zoom',
        'fill' => 'Étirer',
        _ => 'Original',
      };

  /// Original → Zoom → Étirer. [announce]: a toast says the new format (key
  /// A / 1, touch); on TV the lit button already shows it.
  void _cycleAspectRatio({bool announce = true}) {
    final current = ref.read(mobileSettingsProvider).aspectRatioMode;
    String next;
    if (current == 'contain') {
      next = 'cover';
    } else if (current == 'cover') {
      next = 'fill';
    } else {
      next = 'contain';
    }

    ref.read(mobileSettingsProvider.notifier).setAspectRatioMode(next);
    _resetControlsTimer();

    if (announce && mounted) _showToast('Format · ${_formatLabel(next)}');
  }
}

/// Infos techniques (top left): decoder, buffer, picture, format. Polled
/// once a second while shown, isolated from the player's rebuilds.
class StatsOverlayWidget extends ConsumerStatefulWidget {
  final Player player;
  final String formatLabel;
  const StatsOverlayWidget({
    super.key,
    required this.player,
    required this.formatLabel,
  });

  @override
  ConsumerState<StatsOverlayWidget> createState() => _StatsOverlayWidgetState();
}

class _StatsOverlayWidgetState extends ConsumerState<StatsOverlayWidget> {
  String _decoder = '…';
  String _buffer = '…';
  String _picture = '…';

  // Throttling updates
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // Use a periodic timer to poll/update stats instead of listening to every single frequent event
    // This reduces UI thread load significantly on low-end devices
    _updateTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (mounted && ref.read(mobileSettingsProvider).showDebugStats) _poll();
    });
  }

  Future<void> _poll() async {
    final state = widget.player.state;
    String hw = '', cache = '', fps = '';
    try {
      final platform = widget.player.platform as dynamic;
      hw = (await platform?.getProperty('hwdec-current') as String?) ?? '';
      cache =
          (await platform?.getProperty('demuxer-cache-duration') as String?) ??
              '';
      fps = (await platform?.getProperty('container-fps') as String?) ?? '';
    } catch (_) {}
    if (!mounted) return;

    final codec = state.track.video.codec ?? state.track.video.decoder;
    final decoder = hw.isNotEmpty && hw != 'no'
        ? '$hw (matériel)'
        : codec == null || codec.isEmpty
            ? 'logiciel'
            : 'logiciel · $codec';

    final cacheSecs = double.tryParse(cache);
    final ahead = state.buffer - state.position;
    final seconds = cacheSecs ??
        (ahead > Duration.zero ? ahead.inMilliseconds / 1000 : 0.0);
    final buffer = '${seconds.toStringAsFixed(1).replaceAll('.', ',')} s';

    final w = state.width, h = state.height;
    final rate = double.tryParse(fps);
    var picture = w != null && h != null && w > 0 ? '$w × $h' : '—';
    if (rate != null && rate > 0) {
      picture +=
          ' · ${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 2).replaceAll('.', ',')} i/s';
    }

    if (decoder != _decoder || buffer != _buffer || picture != _picture) {
      setState(() {
        _decoder = decoder;
        _buffer = buffer;
        _picture = picture;
      });
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(mobileSettingsProvider.select((s) => s.showDebugStats))) {
      return const SizedBox.shrink();
    }
    return StatsPlate(
      rows: [
        ('Décodeur', _decoder),
        ('Tampon', _buffer),
        ('Image', _picture),
        ('Format', widget.formatLabel),
      ],
    );
  }
}
