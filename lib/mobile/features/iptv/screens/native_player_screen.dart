import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xtremflow/core/models/iptv_models.dart';
import 'package:xtremflow/core/models/playlist_config.dart';
import 'package:xtremflow/features/iptv/services/xtream_service_mobile.dart';
import 'package:xtremflow/mobile/providers/mobile_settings_providers.dart';
import 'package:xtremflow/core/theme/app_colors.dart';
import 'package:xtremflow/mobile/providers/mobile_xtream_providers.dart';
import 'package:xtremflow/features/iptv/models/xtream_models.dart' as xm;

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

  const NativePlayerScreen({
    super.key,
    required this.streamId,
    required this.title,
    required this.playlist,
    required this.streamType,
    this.containerExtension,
    this.channels,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<NativePlayerScreen> createState() => _NativePlayerScreenState();
}

class _NativePlayerScreenState extends ConsumerState<NativePlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  late int _currentIndex;
  XtreamServiceMobile? _xtreamService;
  bool _showControls = true;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isSeeking = false;

  Timer? _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    // Only start clock if setting is enabled (will check in build too, but timer can run)
    _startClock(); 
    _currentIndex = widget.initialIndex;
    
    // Initialize media_kit player with potential software decoding fallback
    // 'hwdec': 'auto' tries hardware first, then software.
    // 'vo': 'gpu' is standard.
    final config = PlayerConfiguration(
      vo: 'gpu',
      // msgLevel removed as it might be deprecated or invalid
    );
    // Create the player instance
    _player = Player(configuration: config);
    
    // Enable software decoding fallback if hardware fails (handled by mpv usually, but ensuring 'auto' helps)
    (_player.platform as dynamic)?.setProperty('hwdec', 'auto');
    
    _controller = VideoController(_player);
    
    // Listen to player state
    _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
      }
    });

    _player.stream.position.listen((position) {
      if (mounted && !_isSeeking) {
        setState(() => _position = position);
      }
    });

    _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });
    
    _player.stream.error.listen((error) {
      if (mounted && error.isNotEmpty) {
        setState(() {
          _errorMessage = error;
          _isLoading = false;
        });
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
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    if (mounted) {
      final now = DateTime.now();
      setState(() {
        _currentTime = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
      });
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
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
    
    super.dispose();
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
      final currentStreamId = widget.channels != null && widget.channels!.isNotEmpty
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
        streamUrl = _xtreamService!.getVodStreamUrl(currentStreamId, widget.containerExtension ?? 'mp4');
      } else {
        streamUrl = _xtreamService!.getSeriesStreamUrl(currentStreamId, widget.containerExtension ?? 'mp4');
      }

      debugPrint('MediaKitPlayer: Loading stream: $streamUrl');

      await _player.open(
        Media(streamUrl, httpHeaders: {'User-Agent': 'XtremFlow/1.0'}),
        play: true,
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('MediaKitPlayer error: $e');
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
    final prevIndex = (_currentIndex - 1 + widget.channels!.length) % widget.channels!.length;
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
    } else {
      _player.play();
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }






  @override
  Widget build(BuildContext context) {
    final title = widget.channels != null && widget.channels!.isNotEmpty 
        ? widget.channels![_currentIndex].name 
        : widget.title;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          children: [
            // Video Player
            if (_errorMessage != null)
              _buildErrorView()
            else if (_isLoading)
              _buildLoadingView()
            else
              Center(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls, // We use our own custom controls
                ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Main Back Button
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
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
          ],
        ),
      ),
    );
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
            
            // Center Controls
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prev Channel / Replay 10s
                  if (widget.streamType == StreamType.live && widget.channels != null && widget.channels!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white, size: 48),
                      onPressed: _playPrevious,
                    )
                  else if (widget.streamType != StreamType.live)
                    IconButton(
                      icon: const Icon(Icons.replay_10, color: Colors.white, size: 48),
                      onPressed: () async {
                        final pos = await _player.stream.position.first;
                        _player.seek(pos - const Duration(seconds: 10));
                      },
                    ),

                  const SizedBox(width: 32),
                  
                  // Play/Pause
                  IconButton(
                    iconSize: 72,
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      color: Colors.white,
                    ),
                    onPressed: _togglePlayPause,
                  ),
                  
                  const SizedBox(width: 32),

                  // Next Channel / Forward 10s
                  if (widget.streamType == StreamType.live && widget.channels != null && widget.channels!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white, size: 48),
                      onPressed: _playNext,
                    )
                  else if (widget.streamType != StreamType.live)
                    IconButton(
                      icon: const Icon(Icons.forward_10, color: Colors.white, size: 48),
                      onPressed: () async {
                        final pos = await _player.stream.position.first;
                        _player.seek(pos + const Duration(seconds: 10));
                      },
                    ),
                ],
              ),
            ),

            // EPG Box (Bottom Left) + LIVE Badge
            if (widget.streamType == StreamType.live && _epg != null && _epg!.nowPlaying != null)
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
                                   style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                   maxLines: 2,
                                   overflow: TextOverflow.ellipsis,
                                 ),
                                 if (_epg!.nextPlaying != null)
                                   Padding(
                                     padding: const EdgeInsets.only(top: 4),
                                     child: Text(
                                       "A suivre: ${_epg!.nextPlaying}",
                                       style: const TextStyle(color: Colors.white70, fontSize: 14),
                                       maxLines: 1,
                                       overflow: TextOverflow.ellipsis,
                                     ),
                                   ),
                               ],
                             ),
                           ),
                           // LIVE Badge inside the box, right side
                           Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          Expanded(
                            child: Slider(
                              value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds.toDouble()),
                              min: 0,
                              max: _duration.inSeconds.toDouble(),
                              activeColor: AppColors.primary,
                              inactiveColor: Colors.white24,
                              onChangeStart: (_) => _isSeeking = true,
                              onChangeEnd: (value) async {
                                await _player.seek(Duration(seconds: value.toInt()));
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
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.streamType == StreamType.live && settings.showClock)
                             // Clock
                             Container(
                               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                               margin: const EdgeInsets.only(right: 12),
                               decoration: BoxDecoration(
                                 color: Colors.black54,
                                 borderRadius: BorderRadius.circular(4),
                               ),
                               child: Text(_currentTime, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
