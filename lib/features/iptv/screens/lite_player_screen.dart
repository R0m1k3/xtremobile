import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/features/iptv/services/xtream_service_mobile.dart';
import 'package:xtremobile/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/features/iptv/screens/native_player_screen.dart';
import 'package:xtremobile/mobile/widgets/tv_focusable.dart';

class LitePlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final model.StreamType streamType;
  final String? containerExtension;
  final PlaylistConfig playlist;
  final List<model.Channel>? channels;
  final int initialIndex;

  // For series episodes
  final dynamic seriesId;
  final int? season;
  final int? episodeNum;

  const LitePlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    required this.streamType,
    this.containerExtension,
    this.channels,
    this.initialIndex = 0,
    this.seriesId,
    this.season,
    this.episodeNum,
  });

  @override
  ConsumerState<LitePlayerScreen> createState() => _LitePlayerScreenState();
}

class _LitePlayerScreenState extends ConsumerState<LitePlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  XtreamServiceMobile? _xtreamService;

  bool _isLoading = true;
  String? _errorMessage;
  late int _currentIndex;
  bool _showControls = true;
  bool _isPlaying = false;

  // EPG & Clock
  model.ShortEPG? _epg;
  Timer? _epgTimer;
  String _currentTime = "";
  Timer? _clockTimer;

  // Progress & Buffering
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSeeking = false;
  bool _isStabilizing = false;
  Timer? _stabilizationTimer;
  Timer? _controlsTimer;
  int _loadId = 0;

  /// Set once the app is backgrounded, so a queued reload cannot restart the
  /// stream behind the user.
  bool _isReleased = false;

  // Focus
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _prevFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();
  final FocusNode _channelListButtonFocusNode = FocusNode();

  /// Focus D-pad de la chaîne active dans la sidebar : permet d'atterrir
  /// directement dessus à l'ouverture de la liste.
  final FocusNode _channelListItemFocusNode = FocusNode();

  // [TiviMate] Channel List Sidebar
  bool _showChannelList = false;
  Timer? _channelListTimer;
  final ScrollController _channelListScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    WakelockPlus.enable();

    _currentIndex = widget.initialIndex;
    _startClock();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initializePlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` is deliberately NOT handled: on Android it fires for transient
    // interruptions (notification shade, call banner, permission dialog).
    final isBackgrounded = state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (!isBackgrounded) return;

    _releasePlayback();

    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  /// Stop playback and release the decoder when the app leaves the foreground.
  ///
  /// `pause()` alone is not enough: ExoPlayer keeps filling its buffer, so the
  /// stream would still be pulled (and metered) in the background.
  void _releasePlayback() {
    if (_isReleased) return;
    _isReleased = true;

    _clockTimer?.cancel();
    _clockTimer = null;
    _epgTimer?.cancel();
    _epgTimer = null;
    _controlsTimer?.cancel();
    _controlsTimer = null;
    _stabilizationTimer?.cancel();
    _stabilizationTimer = null;
    _channelListTimer?.cancel();
    _channelListTimer = null;

    final controller = _controller;
    _controller = null;
    controller?.pause();
    controller?.dispose();

    WakelockPlus.disable();
  }

  void _startClock() {
    _clockTimer?.cancel();
    _updateTime();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTime(),
    );
  }

  void _updateTime() {
    final now = DateTime.now();
    final timeStr =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    if (mounted && _currentTime != timeStr) {
      setState(() => _currentTime = timeStr);
    }
  }

  Future<void> _initializePlayback() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _xtreamService = XtreamServiceMobile(dir.path);
      await _xtreamService!.setPlaylistAsync(widget.playlist);

      // Warm DNS + TCP/TLS to the panel host before the first request.
      await _xtreamService!.prewarmHost().timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () {},
          );

      _loadStream();

      if (widget.streamType == model.StreamType.live) {
        _updateEPG();
        _epgTimer = Timer.periodic(
          const Duration(minutes: 5),
          (_) => _updateEPG(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = "Initialization Error: $e");
    }
  }

  Future<void> _updateEPG() async {
    if (widget.streamType != model.StreamType.live || _xtreamService == null) {
      return;
    }
    try {
      final currentChannelId =
          widget.channels?[_currentIndex].streamId ?? widget.streamId;
      final epgData = await _xtreamService!.getShortEPG(currentChannelId);
      if (mounted) setState(() => _epg = epgData);
    } catch (_) {}
  }

  Future<void> _loadStream() async {
    if (_xtreamService == null) return;
    // Backgrounded while a (re)load was queued — do not resurrect the stream.
    if (_isReleased || !mounted) return;

    await _controller?.dispose();
    _controller = null;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isStabilizing = true;
      _loadId++;
    });

    final currentLoadId = _loadId;

    try {
      final currentStreamId =
          widget.channels != null && widget.channels!.isNotEmpty
              ? widget.channels![_currentIndex].streamId
              : widget.streamId;

      if (widget.streamType == model.StreamType.live) _updateEPG();

      final streamUrl = widget.streamType == model.StreamType.live
          ? _xtreamService!.getLiveStreamUrl(currentStreamId)
          : (widget.streamType == model.StreamType.vod
              ? _xtreamService!.getVodStreamUrl(
                  currentStreamId,
                  widget.containerExtension ?? 'mp4',
                )
              : _xtreamService!.getSeriesStreamUrl(
                  currentStreamId,
                  widget.containerExtension ?? 'mp4',
                ));

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: {'User-Agent': 'XtremFlow/1.0'},
      );

      _controller = controller;
      await controller.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Connection timed out');
        },
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Buffer Optimization: Pre-roll delay for TS streams
      if (widget.streamType == model.StreamType.live) {
        await Future.delayed(const Duration(milliseconds: 2000));
      }

      await controller.play();
      setState(() {
        _isPlaying = true;
        _duration = controller.value.duration;
      });
      _resetControlsTimer();
      controller.addListener(_videoListener);
    } catch (e) {
      if (mounted && currentLoadId == _loadId) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Playback Error: $e";
        });
      }
    }
  }

  void _videoListener() {
    if (_controller == null || !mounted) return;
    final value = _controller!.value;

    if (value.isPlaying != _isPlaying) {
      setState(() => _isPlaying = value.isPlaying);
    }

    // Stabilization Masking: spinner stays until 1.5s of smooth play
    // Fix: If playing, ignore isBuffering to prevent infinite spinner on some TS streams
    // Force hide loader immediately when playing
    if (value.isPlaying) {
      if (_isLoading) setState(() => _isLoading = false);
      if (_errorMessage != null) setState(() => _errorMessage = null);
      if (_isStabilizing) _isStabilizing = false;
      _stabilizationTimer?.cancel();
    } else {
      final shouldShow = value.isBuffering || _isStabilizing;
      if (shouldShow != _isLoading) setState(() => _isLoading = shouldShow);
    }

    if (!_isSeeking) {
      setState(() {
        _position = value.position;
        _duration = value.duration;
      });
    }

    if (value.hasError) setState(() => _errorMessage = value.errorDescription);
  }

  void _onUserInteraction() {
    if (!mounted) return;
    final wasShowing = _showControls;
    setState(() => _showControls = true);
    _resetControlsTimer();

    // Auto-focus the play/pause button when OSD appears to ensure OK key works instantly
    if (!wasShowing) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _showControls) {
          _playPauseFocusNode.requestFocus();
        }
      });
    }
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls && _isPlaying) {
      _controlsTimer = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
    _onUserInteraction();
  }

  void _switchChannel(int index) {
    if (widget.channels == null) return;
    setState(() {
      _currentIndex = index;
      _showChannelList = false; // close sidebar on switch
    });
    _channelListTimer?.cancel();
    _onUserInteraction(); // Ensure OSD shows up and timer resets on channel change
    _loadStream();
  }

  /// Open/close the channel list sidebar
  void _toggleChannelList() {
    setState(() => _showChannelList = !_showChannelList);
    if (_showChannelList) {
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

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    // Sidebar ouverte : Back/Menu la ferment, le reste part au système de
    // Focus (navigation + OK sur un item). On relance juste l'auto-fermeture.
    if (_showChannelList) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack ||
          key == LogicalKeyboardKey.contextMenu ||
          key == LogicalKeyboardKey.keyM) {
        _channelListTimer?.cancel();
        setState(() => _showChannelList = false);
        return true;
      }
      _restartChannelListTimer();
      return false;
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

    if (key == LogicalKeyboardKey.channelUp) {
      if (widget.channels != null) {
        _switchChannel((_currentIndex + 1) % widget.channels!.length);
      }
      return true;
    }
    if (key == LogicalKeyboardKey.channelDown) {
      if (widget.channels != null) {
        _switchChannel(
          (_currentIndex - 1 + widget.channels!.length) %
              widget.channels!.length,
        );
      }
      return true;
    }

    if (!_showControls) {
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        _onUserInteraction();
        return true;
      }
    }

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_showControls) {
        setState(() => _showControls = false);
        return true;
      }
      Navigator.pop(context);
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WakelockPlus.disable();
    _clockTimer?.cancel();
    _epgTimer?.cancel();
    _controlsTimer?.cancel();
    _stabilizationTimer?.cancel();
    _channelListTimer?.cancel();
    _channelListScrollController.dispose();
    _controller?.pause(); // Force stop audio immediately
    _controller?.dispose();
    _xtreamService?.dispose();

    _playPauseFocusNode.dispose();
    _prevFocusNode.dispose();
    _nextFocusNode.dispose();
    _channelListButtonFocusNode.dispose();
    _channelListItemFocusNode.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(mobileSettingsProvider);
    final title = widget.channels != null
        ? widget.channels![_currentIndex].name
        : widget.title;

    return Scaffold(
      // True black behind the video surface, never the warm ink.
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (_showChannelList) {
            _channelListTimer?.cancel();
            setState(() => _showChannelList = false);
          } else {
            _onUserInteraction();
          }
        },
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
            // Video Surface
            Center(
              child: _controller != null && _controller!.value.isInitialized
                  ? _buildAspectRatioWrapper()
                  : const CircularProgressIndicator(color: AppColors.primary),
            ),

            // Top Bar (Back Button + Clock)
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back Button
                        TVFocusable(
                          onPressed: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(50),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_back,
                              color: AppColors.onSurface,
                              size: 28,
                            ),
                          ),
                        ),
                        // Clock
                        if (settings.showClock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _currentTime,
                              style: const TextStyle(
                                color: AppColors.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // Error Overlay
            if (_errorMessage != null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ),

            // Loading Spinner
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),

            // OSD (EPG + Controls)
            if (_showControls) _buildOSD(title),

            // [TiviMate] Channel list sidebar
            if (_showChannelList &&
                widget.streamType == model.StreamType.live &&
                widget.channels != null &&
                widget.channels!.isNotEmpty)
              _buildChannelListSidebar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAspectRatioWrapper() {
    final mode = ref.read(mobileSettingsProvider).aspectRatioMode;
    if (mode == 'fill') {
      return SizedBox.expand(child: VideoPlayer(_controller!));
    }
    if (mode == 'cover') {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }

  Widget _buildOSD(String title) {
    return Positioned(
      bottom: 20,
      left: 20,
      right: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seeker (VOD)
          if (widget.streamType != model.StreamType.live) _buildSeeker(),

          // Unified Box: EPG & Controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.onSurface12),
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
                      if (widget.streamType == model.StreamType.live)
                        TVFocusable(
                          focusNode: _prevFocusNode,
                          onPressed: () => _switchChannel(
                            (_currentIndex -
                                    1 +
                                    (widget.channels?.length ?? 0)) %
                                (widget.channels?.length ?? 1),
                          ),
                          child: const Icon(
                            Icons.skip_previous,
                            color: AppColors.onSurface,
                            size: 36,
                          ),
                        ),
                      const SizedBox(width: 16),
                      TVFocusable(
                        focusNode: _playPauseFocusNode,
                        onPressed: _togglePlayPause,
                        child: Icon(
                          _isPlaying
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: AppColors.onSurface,
                          size: 56,
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (widget.streamType == model.StreamType.live)
                        TVFocusable(
                          focusNode: _nextFocusNode,
                          onPressed: () => _switchChannel(
                            (_currentIndex + 1) %
                                (widget.channels?.length ?? 1),
                          ),
                          child: const Icon(
                            Icons.skip_next,
                            color: AppColors.onSurface,
                            size: 36,
                          ),
                        ),
                      const SizedBox(width: 16),

                      // Channel list sidebar (liste des chaînes de la catégorie)
                      if (widget.streamType == model.StreamType.live &&
                          widget.channels != null &&
                          widget.channels!.isNotEmpty)
                        TVFocusable(
                          focusNode: _channelListButtonFocusNode,
                          onPressed: _toggleChannelList,
                          child: const Icon(
                            Icons.playlist_play_rounded,
                            color: AppColors.onSurface,
                            size: 36,
                          ),
                        ),
                      const SizedBox(width: 16),
                      // Deinterlace Button (Switches to Native Player with forced Deinterlace)
                      TVFocusable(
                        onPressed: () {
                          // Save preference using streamId
                          final streamId =
                              widget.channels?[_currentIndex].streamId ??
                                  widget.streamId;
                          ref
                              .read(mobileSettingsProvider.notifier)
                              .toggleChannelDeinterlace(streamId);

                          // Switch to NativePlayer with Deinterlace ON
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => NativePlayerScreen(
                                streamId: streamId,
                                title: widget.channels?[_currentIndex].name ??
                                    widget.title,
                                playlist: widget.playlist,
                                streamType: widget.streamType,
                                channels: widget.channels,
                                initialIndex: _currentIndex,
                                forceDeinterlace: true,
                              ),
                            ),
                          );
                        },
                        child: const Icon(
                          Icons
                              .grid_on, // Icon representing interlaced grid/mesh
                          color: AppColors.onSurface,
                          size: 32,
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
    );
  }

  Widget _buildEPGBox(String title) {
    String program = widget.streamType == model.StreamType.live
        ? (_epg?.nowPlaying ?? "Pas d'infos EPG")
        : title;
    String next =
        _epg?.nextPlaying != null ? "Suivant: ${_epg!.nextPlaying}" : "";
    double progress = _epg?.progress ?? 0.0;

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
                ),
              ),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          program,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (widget.streamType == model.StreamType.live &&
            _epg?.nowPlaying != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.onSurface12,
              color: AppColors.primary,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            next,
            style: const TextStyle(color: AppColors.onSurface54, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _buildSeeker() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Actions(
        actions: {
          DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
            onInvoke: (intent) {
              if (intent.direction == TraversalDirection.up ||
                  intent.direction == TraversalDirection.down) {
                FocusScope.of(context).focusInDirection(intent.direction);
                return null;
              }
              return null;
            },
          ),
        },
        child: Shortcuts(
          shortcuts: {
            LogicalKeySet(LogicalKeyboardKey.arrowUp):
                const DirectionalFocusIntent(TraversalDirection.up),
            LogicalKeySet(LogicalKeyboardKey.arrowDown):
                const DirectionalFocusIntent(TraversalDirection.down),
          },
          child: Slider(
            value: _position.inSeconds.toDouble().clamp(
                  0,
                  _duration.inSeconds.toDouble(),
                ),
            min: 0,
            max: _duration.inSeconds.toDouble(),
            activeColor: AppColors.primary,
            inactiveColor: AppColors.onSurface24,
            onChanged: (v) => setState(() {
              _position = Duration(seconds: v.toInt());
              _isSeeking = true;
            }),
            onChangeEnd: (v) {
              _controller?.seekTo(Duration(seconds: v.toInt()));
              _isSeeking = false;
              _onUserInteraction();
            },
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
                    bottom: BorderSide(color: AppColors.onSurface12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.list,
                        color: AppColors.onSurface70, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Chaînes',
                        style: TextStyle(
                          color: AppColors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _channelListTimer?.cancel();
                        setState(() => _showChannelList = false);
                      },
                      child: const Icon(Icons.close,
                          color: AppColors.onSurface54, size: 18),
                    ),
                  ],
                ),
              ),
              // Channel list
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    _restartChannelListTimer();
                    return false;
                  },
                  child: ListView.builder(
                    controller: _channelListScrollController,
                    itemCount: channels.length,
                    itemExtent: 64.0,
                    itemBuilder: (context, index) {
                      final ch = channels[index];
                      final isActive = index == _currentIndex;
                      return TVFocusable(
                        // Le focusNode externe n'est posé que sur la chaîne
                        // active ; la clé force un remontage quand isActive
                        // change (TVFocusable ne gère pas didUpdateWidget).
                        key: ValueKey('sidebar-ch-$index-$isActive'),
                        focusNode: isActive ? _channelListItemFocusNode : null,
                        scale: 1.0,
                        borderRadius: BorderRadius.zero,
                        onFocus: _restartChannelListTimer,
                        onPressed: () {
                          _channelListTimer?.cancel();
                          _switchChannel(index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.primaryFill.withValues(alpha: 0.6)
                                : Colors.transparent,
                            border: isActive
                                ? const Border(
                                    left: BorderSide(
                                      color: AppColors.primary,
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
                                  color: AppColors.onSurface12,
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
                                                  color: AppColors.onSurface38,
                                                  size: 20),
                                        ),
                                      )
                                    : const Icon(Icons.tv,
                                        color: AppColors.onSurface38, size: 20),
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
                                            ? AppColors.onSurface
                                            : AppColors.onSurface70,
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
                                        color: AppColors.onSurface38,
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
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
