import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    this.settle = const Duration(milliseconds: 350),
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
    // Another channel: drop the old picture at once, open after the settle.
    if (_openedId != null) _stop();
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
    // Show the first frames at once instead of waiting for the cache.
    mpv?.setProperty('cache-pause', 'no');
    // Stream analysis before the first frame. FFmpeg's default goes up to
    // 5 s, and IPTV streams with teletext or data tracks always use all of
    // it (those tracks are never "identified"). The preview needs the video
    // only: 1.5 s / 1 MB is enough to find it (H.264 / HEVC parameters come
    // with every keyframe).
    mpv?.setProperty(
      'demuxer-lavf-o',
      'analyzeduration=1500000,probesize=1000000',
    );
    mpv?.setProperty('network-timeout', '15');
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
              duration: AppTheme.durationNormal,
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
