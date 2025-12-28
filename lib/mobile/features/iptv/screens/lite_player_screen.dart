import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xtremflow/core/models/iptv_models.dart';
import 'package:xtremflow/core/models/playlist_config.dart';
import 'package:xtremflow/features/iptv/services/xtream_service_mobile.dart';
import 'package:xtremflow/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/mobile/features/iptv/screens/native_player_screen.dart';
import 'package:xtremflow/features/iptv/models/xtream_models.dart' as xm;
import 'package:xtremflow/mobile/widgets/tv_focusable.dart';

class LitePlayerScreen extends ConsumerStatefulWidget {
  final String streamId;
  final String title;
  final StreamType streamType;
  final String? containerExtension;
  final PlaylistConfig playlist;
  final List<Channel>? channels;
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
  xm.ShortEPG? _epg;
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

  // Focus
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _prevFocusNode = FocusNode();
  final FocusNode _nextFocusNode = FocusNode();

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
    if (_controller == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _controller?.pause();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
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
      _loadStream();

      if (widget.streamType == StreamType.live) {
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
    if (widget.streamType != StreamType.live || _xtreamService == null) return;
    try {
      final currentChannelId =
          widget.channels?[_currentIndex].streamId ?? widget.streamId;
      final epgData = await _xtreamService!.getShortEPG(currentChannelId);
      if (mounted) setState(() => _epg = epgData);
    } catch (_) {}
  }

  Future<void> _loadStream() async {
    if (_xtreamService == null) return;

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

      if (widget.streamType == StreamType.live) _updateEPG();

      final streamUrl = widget.streamType == StreamType.live
          ? _xtreamService!.getLiveStreamUrl(currentStreamId)
          : (widget.streamType == StreamType.vod
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
      await controller.initialize().timeout(const Duration(seconds: 15),
          onTimeout: () {
        throw Exception('Connection timed out');
      });

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Buffer Optimization: Pre-roll delay for TS streams
      if (widget.streamType == StreamType.live) {
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
      if (mounted && currentLoadId == _loadId)
        setState(() {
          _isLoading = false;
          _errorMessage = "Playback Error: $e";
        });
    }
  }

  void _videoListener() {
    if (_controller == null || !mounted) return;
    final value = _controller!.value;

    if (value.isPlaying != _isPlaying)
      setState(() => _isPlaying = value.isPlaying);

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
    setState(() => _currentIndex = index);
    _onUserInteraction(); // Ensure OSD shows up and timer resets on channel change
    _loadStream();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.channelUp) {
      if (widget.channels != null)
        _switchChannel((_currentIndex + 1) % widget.channels!.length);
      return true;
    }
    if (key == LogicalKeyboardKey.channelDown) {
      if (widget.channels != null)
        _switchChannel(
          (_currentIndex - 1 + widget.channels!.length) %
              widget.channels!.length,
        );
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
    _controller?.pause(); // Force stop audio immediately
    _controller?.dispose();
    _xtreamService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(mobileSettingsProvider);
    final title = widget.channels != null
        ? widget.channels![_currentIndex].name
        : widget.title;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _onUserInteraction,
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
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.arrow_back,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                        // Clock
                        if (settings.showClock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _currentTime,
                              style: const TextStyle(
                                color: Colors.white,
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
                    style: const TextStyle(color: Colors.red),
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
          ],
        ),
      ),
    );
  }

  Widget _buildAspectRatioWrapper() {
    final mode = ref.read(mobileSettingsProvider).aspectRatioMode;
    if (mode == 'fill')
      return SizedBox.expand(child: VideoPlayer(_controller!));
    if (mode == 'cover')
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
          if (widget.streamType != StreamType.live) _buildSeeker(),

          // Unified Box: EPG & Controls
          Container(
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
                      if (widget.streamType == StreamType.live)
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
                            color: Colors.white,
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
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (widget.streamType == StreamType.live)
                        TVFocusable(
                          focusNode: _nextFocusNode,
                          onPressed: () => _switchChannel(
                            (_currentIndex + 1) %
                                (widget.channels?.length ?? 1),
                          ),
                          child: const Icon(
                            Icons.skip_next,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      const SizedBox(width: 16),
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
                          color: Colors.white,
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
    String program = widget.streamType == StreamType.live
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
                  color: Colors.white,
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
        if (widget.streamType == StreamType.live &&
            _epg?.nowPlaying != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              color: AppColors.primary,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            next,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
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
            inactiveColor: Colors.white24,
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
}
