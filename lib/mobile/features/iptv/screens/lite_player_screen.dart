import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:xtremflow/mobile/widgets/tv_focusable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xtremflow/core/models/iptv_models.dart';
import 'package:xtremflow/core/models/playlist_config.dart';
import 'package:xtremflow/features/iptv/services/xtream_service_mobile.dart';
import 'package:xtremflow/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/mobile/features/iptv/screens/native_player_screen.dart'
    show StreamType;
import 'package:xtremflow/features/iptv/models/xtream_models.dart' as xm;

/// Lite version of the player using standard video_player (ExoPlayer on Android)
/// Targeted for 1GB RAM devices with Light engine.
/// Standard AspectRatio implementation (No manual toggle).
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

  // EPG
  xm.ShortEPG? _epg;
  Timer? _epgTimer;

  // Progress & Seeking
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSeeking = false;
  bool _isStabilizing = false; // Flag to mask initial glitches
  Timer? _stabilizationTimer;

  // Focus Nodes
  final FocusNode _playPauseFocusNode = FocusNode();
  final FocusNode _backFocusNode = FocusNode();
  final FocusNode _deinterlaceFocusNode = FocusNode();

  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    // Enable wakelock
    WakelockPlus.enable();

    _currentIndex = widget.initialIndex;

    // Lock orientation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _xtreamService = XtreamServiceMobile(dir.path);
      await _xtreamService!.setPlaylistAsync(widget.playlist);
      _loadStream();
      _updateEPG(); // Initial Load

      // Update EPG periodically for Live TV
      if (widget.streamType == StreamType.live) {
        _epgTimer =
            Timer.periodic(const Duration(minutes: 5), (_) => _updateEPG());
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = "Service Error: $e");
    }
  }

  Future<void> _updateEPG() async {
    if (widget.streamType != StreamType.live || _xtreamService == null) return;

    try {
      final currentChannelId =
          widget.channels?[_currentIndex].streamId ?? widget.streamId;
      // Get EPG for current channel
      final epgData = await _xtreamService!.getShortEPG(currentChannelId);
      if (mounted) {
        setState(() => _epg = epgData);
      }
    } catch (_) {}
  }

  Future<void> _loadStream() async {
    if (_xtreamService == null) return;

    // cleanup previous
    await _controller?.dispose();
    _controller = null;

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentStreamId =
          widget.channels != null && widget.channels!.isNotEmpty
              ? widget.channels![_currentIndex].streamId
              : widget.streamId;

      // Update EPG when changing channels
      if (widget.streamType == StreamType.live) {
        _updateEPG();
      }

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

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(streamUrl),
        httpHeaders: {'User-Agent': 'XtremFlow/1.0'},
      );

      _controller = controller;
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // Buffer Optimization: Wait for a pre-roll delay for Live TV
      // to let the internal buffer fill before playback starts.
      if (widget.streamType == StreamType.live) {
        debugPrint('[LitePlayer] Pre-roll buffer delay (3.5s)...');
        await Future.delayed(const Duration(milliseconds: 3500));
      }

      await controller.play();
      setState(() {
        _isStabilizing = true;
        _isPlaying = true;
        _duration = controller.value.duration;
      });
      _resetControlsTimer();

      // Listen for errors and completion
      controller.addListener(_videoListener);
    } catch (e) {
      if (mounted) {
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

    final isPlaying = value.isPlaying;
    if (isPlaying != _isPlaying) {
      setState(() => _isPlaying = isPlaying);
    }

    // --- STABILIZATION MASKING LOGIC ---
    // Show spinner if buffering OR if we are in the initial stabilization phase
    final isBuffering = value.isBuffering;
    final shouldShowLoading = isBuffering || _isStabilizing;

    if (shouldShowLoading != _isLoading) {
      setState(() => _isLoading = shouldShowLoading);
    }

    // If we are playing smoothly and stabilizing, start/restart the timer
    if (isPlaying && !isBuffering && _isStabilizing) {
      _stabilizationTimer?.cancel();
      _stabilizationTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _isStabilizing = false;
            _isLoading = false;
          });
        }
      });
    } else if (isBuffering && _isStabilizing) {
      // If we hit a buffer during stabilization, reset the timer
      _stabilizationTimer?.cancel();
    }
    // ------------------------------------

    if (!_isSeeking) {
      final pos = value.position;
      final dur = value.duration;
      if (pos != _position || dur != _duration) {
        setState(() {
          _position = pos;
          _duration = dur;
        });
      }
    }

    if (value.hasError) {
      setState(() => _errorMessage = value.errorDescription);
    }
  }

  void _onUserInteraction() {
    setState(() => _showControls = true);
    _resetControlsTimer();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (_showControls && _isPlaying) {
      _controlsTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    _onUserInteraction();
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
    setState(() => _currentIndex = index);
    _loadStream();
  }

  Future<void> _seek(Duration offset) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final newPos = _controller!.value.position + offset;
    final clamped = Duration(
      milliseconds: newPos.inMilliseconds
          .clamp(0, _controller!.value.duration.inMilliseconds),
    );
    await _controller!.seekTo(clamped);
    _onUserInteraction();
  }

  // Simplified Key Handler
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      return true;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      if (!_showControls) {
        _onUserInteraction();
        return true;
      }
      return false;
    }

    // Arrow keys - Show controls or let focus navigate, NO zapping
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      if (!_showControls) {
        _onUserInteraction();
        return true;
      }
      return false; // Let Focus system handle navigation
    }

    // Channel Down = Previous Channel (inverted as requested)
    if (key == LogicalKeyboardKey.channelDown) {
      if (widget.streamType == StreamType.live) {
        _playPrevious();
        _onUserInteraction();
        return true;
      }
    }

    // Channel Up = Next Channel (inverted as requested)
    if (key == LogicalKeyboardKey.channelUp) {
      if (widget.streamType == StreamType.live) {
        _playNext();
        _onUserInteraction();
        return true;
      }
    }

    if (widget.streamType != StreamType.live) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        _seek(const Duration(seconds: -10));
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        _seek(const Duration(seconds: 10));
        return true;
      }
    }

    // Cycle Aspect Ratio - secret key 'A' or digit 1
    if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.digit1) {
      _cycleAspectRatio();
      return true;
    }

    // Toggle Deinterlace - secret key 'D' or digit 2
    if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.digit2) {
      _togglePerChannelDeinterlace();
      return true;
    }

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_showControls) {
        setState(() => _showControls = false);
      } else {
        Navigator.pop(context);
      }
      return true;
    }

    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WakelockPlus.disable();

    _controlsTimer?.cancel();
    _epgTimer?.cancel();
    _controller?.dispose();
    _xtreamService?.dispose();
    _playPauseFocusNode.dispose();
    _backFocusNode.dispose();
    _deinterlaceFocusNode.dispose();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Widget _buildVideoOutput() {
    final mode = ref.watch(mobileSettingsProvider).aspectRatioMode;

    switch (mode) {
      case 'cover':
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
      case 'fill':
        return SizedBox.expand(
          child: VideoPlayer(_controller!),
        );
      case 'contain':
      default:
        return AspectRatio(
          aspectRatio: _controller!.value.aspectRatio,
          child: VideoPlayer(_controller!),
        );
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

  void _togglePerChannelDeinterlace() {
    final currentStreamId =
        widget.channels != null && widget.channels!.isNotEmpty
            ? widget.channels![_currentIndex].streamId
            : widget.streamId;

    final notifier = ref.read(deinterlaceSettingsProvider.notifier);
    notifier.toggle(currentStreamId);

    final newState = notifier.isEnabled(currentStreamId);

    if (mounted) {
      setState(() {}); // Refresh UI
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Désentrelacement: ${newState ? "ACTIVER" : "DÉSACTIVER"}'),
          duration: const Duration(seconds: 2),
          backgroundColor: newState ? Colors.green : Colors.grey[800],
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
        onTap: _onUserInteraction,
        child: Stack(
          children: [
            // Video Output - Standard AspectRatio
            Center(
              child: _controller != null && _controller!.value.isInitialized
                  ? _buildVideoOutput()
                  : const CircularProgressIndicator(color: AppColors.primary),
            ),

            if (_errorMessage != null)
              Center(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            if (_showControls) _buildControls(title),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(String title) {
    return Stack(
      children: [
        // Top Bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              children: [
                TVFocusable(
                  focusNode: _backFocusNode,
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
                const SizedBox(width: 16),
                if (widget.channels != null &&
                    widget.channels![_currentIndex].streamIcon.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CachedNetworkImage(
                        imageUrl: widget.channels![_currentIndex].streamIcon,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const Spacer(),
              ],
            ),
          ),
        ),

        // Bottom Controls (Aligned with EPG)
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Live TV: Prev Channel
                if (widget.streamType == StreamType.live &&
                    widget.channels != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 24),
                    child: IconButton(
                      icon: const Icon(
                        Icons.skip_previous,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _playPrevious,
                    ),
                  ),

                // VOD: Replay 10s
                if (widget.streamType != StreamType.live) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.replay_10,
                      color: Colors.white70,
                      size: 36,
                    ),
                    onPressed: () => _seek(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 24),
                ],

                // Play/Pause Button
                TVFocusable(
                  focusNode: _playPauseFocusNode,
                  onPressed: _togglePlayPause,
                  scale: 1.0,
                  borderWidth: 0,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),

                // VOD: Forward 10s
                if (widget.streamType != StreamType.live) ...[
                  const SizedBox(width: 24),
                  IconButton(
                    icon: const Icon(
                      Icons.forward_10,
                      color: Colors.white70,
                      size: 36,
                    ),
                    onPressed: () => _seek(const Duration(seconds: 10)),
                  ),
                ],

                // Live TV: Next Channel
                if (widget.streamType == StreamType.live &&
                    widget.channels != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 24),
                    child: IconButton(
                      icon: const Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: 48,
                      ),
                      onPressed: _playNext,
                    ),
                  ),
              ],
            ),
          ),
        ),

        // EPG Content
        if (widget.streamType == StreamType.live &&
            _epg != null &&
            _epg!.nowPlaying != null)
          Positioned(
            bottom: 180, // Moved up to avoid button overlap
            left: 24,
            width: 350,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black
                    .withOpacity(0.85), // Higher opacity for visibility
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
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

        // Progress Bar (VOD)
        if (widget.streamType != StreamType.live)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(color: Colors.white),
                  ),
                  Expanded(
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        DirectionalFocusIntent:
                            CallbackAction<DirectionalFocusIntent>(
                          onInvoke: (intent) {
                            if (intent.direction == TraversalDirection.up ||
                                intent.direction == TraversalDirection.down) {
                              FocusScope.of(context)
                                  .focusInDirection(intent.direction);
                              return null;
                            }
                            return null;
                          },
                        ),
                      },
                      child: Shortcuts(
                        shortcuts: <LogicalKeySet, Intent>{
                          LogicalKeySet(LogicalKeyboardKey.arrowUp):
                              const DirectionalFocusIntent(
                                  TraversalDirection.up),
                          LogicalKeySet(LogicalKeyboardKey.arrowDown):
                              const DirectionalFocusIntent(
                                  TraversalDirection.down),
                        },
                        child: Slider(
                          value: _position.inSeconds
                              .toDouble()
                              .clamp(0, _duration.inSeconds.toDouble()),
                          min: 0,
                          max: _duration.inSeconds.toDouble(),
                          activeColor: AppColors.primary,
                          inactiveColor: Colors.white24,
                          onChanged: (val) {
                            setState(() {
                              _position = Duration(seconds: val.toInt());
                              _isSeeking = true;
                            });
                          },
                          onChangeEnd: (val) {
                            _controller?.seekTo(Duration(seconds: val.toInt()));
                            _isSeeking = false;
                            _onUserInteraction();
                          },
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
