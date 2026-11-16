import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:xtremobile/core/models/iptv_models.dart' as model;
import 'package:xtremobile/core/models/playlist_config.dart';
import 'package:xtremobile/core/theme/app_colors.dart';
import 'package:xtremobile/core/theme/app_theme.dart';
import 'package:xtremobile/features/iptv/widgets/live_widgets.dart';
import 'package:xtremobile/mobile/providers/mobile_xtream_providers.dart';

/// Muted live preview of the focused channel (TV channel list).
///
/// The stream opens only once the focus has rested on a channel for
/// [settle], so scrolling down a list does not open a connection per row.
/// One player is reused for every channel. Many IPTV subscriptions allow a
/// single connection: call [ChannelPreviewState.release] before opening the
/// full-screen player, and pass `active: false` while the tab is hidden.
class ChannelPreview extends ConsumerStatefulWidget {
  const ChannelPreview({
    super.key,
    required this.playlist,
    required this.channel,
    this.active = true,
    this.settle = const Duration(milliseconds: 250),
  });

  final PlaylistConfig playlist;
  final model.Channel channel;
  final bool active;
  final Duration settle;

  @override
  ConsumerState<ChannelPreview> createState() => ChannelPreviewState();
}

class ChannelPreviewState extends ConsumerState<ChannelPreview>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _controller;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _settleTimer;
  String? _openedId;
  bool _hasVideo = false;
  bool _failed = false;
  bool _released = false;
  bool _appVisible = true;

  bool get _shouldPlay => widget.active && _appVisible && !_released;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Create mpv and its video surface now, not on the first channel: the
    // first preview no longer pays for it. If mpv cannot start, the list
    // still shows (no preview), and _open() reports the failure.
    try {
      _ensurePlayer();
      _prepareSurface();
    } catch (e) {
      debugPrint('ChannelPreview: $e');
    }
    _schedule();
  }

  @override
  void didUpdateWidget(ChannelPreview old) {
    super.didUpdateWidget(old);
    if (old.channel.streamId != widget.channel.streamId ||
        old.active != widget.active) {
      _schedule();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (visible == _appVisible) return;
    _appVisible = visible;
    _schedule();
  }

  /// Stops the stream and frees the connection (before full-screen playback).
  Future<void> release() async {
    _released = true;
    _settleTimer?.cancel();
    await _stop();
  }

  /// Lets the preview play again (after full-screen playback).
  void resume() {
    _released = false;
    _schedule();
  }

  void _schedule() {
    _settleTimer?.cancel();
    if (!_shouldPlay) {
      _stop();
      return;
    }
    if (_openedId == widget.channel.streamId) return;
    // Another channel: drop the old picture and free the connection at once,
    // get the surface ready during the settle, open after it.
    if (_openedId != null) _stop().then((_) => _prepareSurface());
    _settleTimer = Timer(widget.settle, _open);
  }

  Future<void> _open() async {
    if (!mounted || !_shouldPlay) return;
    final streamId = widget.channel.streamId;
    try {
      final service = await ref.read(
        mobileXtreamServiceProvider(widget.playlist).future,
      );
      if (!mounted || !_shouldPlay || streamId != widget.channel.streamId) {
        return;
      }
      final player = _ensurePlayer();
      if (!mounted) return;
      setState(() {
        _openedId = streamId;
        _hasVideo = false;
        _failed = false;
      });
      await player.open(
        Media(
          service.getLiveStreamUrl(streamId),
          httpHeaders: {'User-Agent': 'XtremFlow/1.0'},
        ),
      );
    } catch (e) {
      debugPrint('ChannelPreview: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = Player(
      configuration: const PlayerConfiguration(
        vo: 'gpu',
        muted: true,
        bufferSize: 8 * 1024 * 1024,
      ),
    );
    final mpv = player.platform as dynamic;
    // A preview: no audio decoding, small cache, give up quickly.
    mpv?.setProperty('aid', 'no');
    mpv?.setProperty('sid', 'no');
    mpv?.setProperty('cache-secs', '2');
    // media_kit turns the disk cache on: a file per stream on the TV's slow
    // flash. 8 MB in memory is plenty for a preview.
    mpv?.setProperty('cache-on-disk', 'no');
    // Show the first frames at once instead of waiting for the cache.
    mpv?.setProperty('cache-pause', 'no');
    // One or two frames less between decoding and the screen.
    mpv?.setProperty('video-latency-hacks', 'yes');
    // media_kit seeks to 0 each time the video surface is rebuilt: make that
    // a plain keyframe seek, not a decode-and-drop up to the exact time.
    mpv?.setProperty('hr-seek', 'no');
    // Stream analysis before the first frame (FFmpeg's find_stream_info):
    // * fpsprobesize=0: FFmpeg otherwise decodes ~20 video frames (0.8 s at
    //   25 fps) of every MPEG-TS stream only to estimate its frame rate,
    //   which mpv does not need (it plays by timestamps);
    // * analyzeduration 1 s (was 1.5 s, FFmpeg's default 5 s): streams with
    //   teletext or data tracks always use all of it, as those tracks are
    //   never "identified". 1 s still holds a keyframe on IPTV streams, and
    //   H.264 / HEVC parameters come with every keyframe.
    mpv?.setProperty(
      'demuxer-lavf-o',
      'analyzeduration=1000000,probesize=1000000,fpsprobesize=0',
    );
    mpv?.setProperty('network-timeout', '8');
    mpv?.setProperty('tls-verify', 'no');
    if (defaultTargetPlatform == TargetPlatform.android) {
      mpv?.setProperty('hwdec', 'mediacodec');
    }
    _subs
      ..add(
        player.stream.width.listen((w) {
          final has = (w ?? 0) > 0;
          if (mounted && has != _hasVideo) setState(() => _hasVideo = has);
        }),
      )
      ..add(
        player.stream.error.listen((e) {
          debugPrint('ChannelPreview: $e');
          if (mounted && !_hasVideo) setState(() => _failed = true);
        }),
      );
    _player = player;
    // Rendered at 640×360, the size it is shown at (iOS, desktop; Android's
    // media_kit ignores it and renders at the stream's size).
    _controller = VideoController(
      player,
      configuration:
          const VideoControllerConfiguration(width: 640, height: 360),
    );
    return player;
  }

  /// Android: media_kit sizes the video surface to each stream, and every
  /// new size rebuilds mpv's video output then seeks back to 0 — after the
  /// first frame is decoded, so on the critical path. Most IPTV channels are
  /// 1920×1080: the surface is given that size while nothing plays (at start
  /// and during the settle), so those channels start without a rebuild.
  /// Uses the plugin's own channel; any failure only loses the head start.
  Future<void> _prepareSurface() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final player = _player;
    final controller = _controller;
    if (player == null || controller == null) return;
    try {
      final platform = await controller.platform.future;
      final r = platform.rect.value;
      if (r != null &&
          r.width == _usualSize.width &&
          r.height == _usualSize.height) {
        return;
      }
      final handle = await player.handle;
      // A stream opened meanwhile: let media_kit size the surface itself.
      if (!mounted || _openedId != null) return;
      await _mediaKitVideo.invokeMethod('VideoOutputManager.SetSurfaceSize', {
        'handle': handle.toString(),
        'width': _usualSize.width.toInt().toString(),
        'height': _usualSize.height.toInt().toString(),
      });
    } catch (e) {
      debugPrint('ChannelPreview: surface $e');
    }
  }

  static const _usualSize = Size(1920, 1080);
  static const _mediaKitVideo =
      MethodChannel('com.alexmercerind/media_kit_video');

  Future<void> _stop() async {
    final wasOpen = _openedId != null;
    _openedId = null;
    if (mounted && (wasOpen || _hasVideo || _failed)) {
      setState(() {
        _hasVideo = false;
        _failed = false;
      });
    }
    if (wasOpen) await _player?.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settleTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    final controller = _controller;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            Video(
              controller: controller,
              controls: NoVideoControls,
              fill: Colors.black,
              fit: BoxFit.cover,
            ),
          // Logo until the first frame, or when the stream will not open.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _hasVideo ? 0 : 1,
              // Short: the picture is there, show it.
              duration: const Duration(milliseconds: 120),
              child: ColoredBox(
                color: AppColors.surfaceHigh,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChannelLogo(
                        url: c.streamIcon,
                        name: c.name,
                        width: 96,
                        height: 60,
                        radius: 8,
                      ),
                      if (_failed) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Aperçu indisponible',
                          style: AppTheme.body(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
