import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/music_provider.dart';
import '../services/lyrics_service.dart';

class LyricsScreen extends StatefulWidget {
  const LyricsScreen({super.key});

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> {
  LyricsResult? _lyrics;
  bool _isLoading = true;
  String? _error;
  String? _currentSongId;

  // flutter_lyric controller
  // flutter_lyric controller
  LyricController? _lyricController;

  // Window state
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    super.initState();
    _checkFullscreenState();
  }

  Future<void> _checkFullscreenState() async {
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      final isFull = await windowManager.isFullScreen();
      if (mounted) setState(() => _isFullscreen = isFull);
    }
  }

  @override
  void dispose() {
    _lyricController?.dispose();
    // Restore window state when leaving lyrics screen
    // Restore window state when leaving lyrics screen
    if (_isFullscreen &&
        !kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      windowManager.setFullScreen(false);
    }

    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    if (!kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      final isFull = await windowManager.isFullScreen();
      if (isFull) {
        await windowManager.setFullScreen(false);
        setState(() => _isFullscreen = false);
      } else {
        await windowManager.setFullScreen(true);
        setState(() => _isFullscreen = true);
      }
    }
  }

  Future<void> _exitLyrics() async {
    if (_isFullscreen &&
        !kIsWeb &&
        (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
      await windowManager.setFullScreen(false);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _fetchLyrics(
    String title,
    String artist, {
    int? durationSeconds,
    String? songId,
  }) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final lyrics = await LyricsService.getLyrics(
        trackName: title,
        artistName: artist,
        durationSeconds: durationSeconds,
        songId: songId,
      );

      if (mounted) {
        setState(() {
          _lyrics = lyrics;
          _isLoading = false;
          if (lyrics == null) {
            _error = 'No lyrics found';
          } else {
            _initLyricController(lyrics);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to fetch lyrics';
        });
      }
    }
  }

  void _initLyricController(LyricsResult lyrics) {
    _lyricController?.dispose();

    if (lyrics.hasSyncedLyrics && lyrics.syncedLyrics != null) {
      _lyricController = LyricController()..loadLyric(lyrics.syncedLyrics!);
    } else {
      _lyricController = null;
    }

    if (mounted) setState(() {});
  }

  LyricStyle _getLyricStyle(
    BuildContext context,
    MusicProvider provider, {
    required bool isMobile,
  }) {
    return LyricStyles.default2.copyWith(
      // Normal text style - dimmed
      textStyle: TextStyle(
        color: Colors.white.withValues(alpha: 0.35),
        fontSize: isMobile ? 20 : 26,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      // Active line style - bright
      activeStyle: TextStyle(
        color: Colors.white,
        fontSize: isMobile ? 24 : 30,
        fontWeight: FontWeight.w800,
        height: 1.4,
      ),
      // Alignment - center for immersive feel
      textAlign: TextAlign.center,
      contentAlignment: CrossAxisAlignment.center,
      // Spacing
      lineGap: isMobile ? 24 : 32,
      contentPadding: EdgeInsets.only(
        top: isMobile ? 200 : 280,
        left: isMobile ? 24 : 48,
        right: isMobile ? 24 : 48,
        bottom: isMobile ? 200 : 280,
      ),
      // Scroll behavior - centered vertically
      anchorPosition: 0.5,
      activeAnchorPosition: 0.5, // Center the active line vertically
      scrollDuration: const Duration(milliseconds: 350),
      scrollCurve: Curves.easeOutCubic,
      // Fade effect at edges
      fadeRange: FadeRange(
        top: isMobile ? 100 : 120,
        bottom: isMobile ? 100 : 120,
      ),
      // Override default gradient with solid white
      activeHighlightGradient: const LinearGradient(
        colors: [Colors.white, Colors.white],
      ),
      // Selection colors - same as dimmed text so no extra highlight when user scrolls
      selectedColor: Colors.white.withValues(alpha: 0.35),
      selectedTranslationColor: Colors.white.withValues(alpha: 0.35),
      // Line switch animation - smooth entry/exit
      enableSwitchAnimation: true,
      switchEnterDuration: const Duration(milliseconds: 300),
      switchExitDuration: const Duration(milliseconds: 200),
      switchEnterCurve: Curves.easeOutCubic,
      switchExitCurve: Curves.easeInCubic,
      // Alignment for selection and active
      highlightAlign: MainAxisAlignment.center,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<MusicProvider>(
        builder: (context, provider, _) {
          final currentSong = provider.currentSong;

          // Fetch lyrics when song changes
          if (currentSong != null && currentSong.id != _currentSongId) {
            _currentSongId = currentSong.id;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fetchLyrics(
                currentSong.title,
                currentSong.artist,
                durationSeconds: provider.totalDuration.inSeconds,
                songId: currentSong.id,
              );
            });
          }

          // Update lyric controller with current position
          if (_lyricController != null) {
            _lyricController!.setProgress(provider.currentPosition);
          }

          return Stack(
            children: [
              // 1. Background (Gradient)
              _buildBackground(provider),

              // 2. Main Layout
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 900) {
                    return _buildSplitLayout(context, provider, currentSong);
                  }
                  return _buildMobileLayout(context, provider, currentSong);
                },
              ),

              // 3. Close Button (Top right) - Only show on desktop
              // Window Drag Handler (Top Area)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 60,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (_) {
                    if (!kIsWeb &&
                        (Platform.isWindows ||
                            Platform.isMacOS ||
                            Platform.isLinux)) {
                      windowManager.startDragging();
                    }
                  },
                ),
              ),

              // 3. Controls (Top right)
              Positioned(
                top: 20,
                right: 20,
                child: SafeArea(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Fullscreen Toggle
                      if (!kIsWeb &&
                          (Platform.isWindows ||
                              Platform.isMacOS ||
                              Platform.isLinux))
                        IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isFullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                          onPressed: _toggleFullscreen,
                          tooltip: _isFullscreen
                              ? 'Exit Fullscreen'
                              : 'Fullscreen',
                        ),
                      const SizedBox(width: 12),
                      // Close Button
                      IconButton(
                        icon: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                        onPressed: _exitLyrics,
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBackground(MusicProvider provider) {
    return Stack(
      children: [
        Container(color: Colors.black),
        AnimatedContainer(
          duration: const Duration(milliseconds: 1000),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                provider.backgroundColor ?? const Color(0xFF1C1C1E),
                const Color(0xFF000000),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
        Container(color: Colors.black.withValues(alpha: 0.3)),
      ],
    );
  }

  Widget _buildSplitLayout(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(flex: 9, child: _buildLeftPanel(context, provider, song)),
          const SizedBox(width: 60),
          Expanded(flex: 11, child: _buildRightPanel(context, provider, song)),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    return SafeArea(
      child: Column(
        children: [
          // Header Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _exitLyrics,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) {
                      if (!kIsWeb &&
                          (Platform.isWindows ||
                              Platform.isMacOS ||
                              Platform.isLinux)) {
                        windowManager.startDragging();
                      }
                    },
                    child: Column(
                      children: [
                        Text(
                          'NOW PLAYING',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song?.title ?? '',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _toggleFullscreen,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Icon(
                      _isFullscreen
                          ? Icons.fullscreen_exit_rounded
                          : Icons.fullscreen_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildMobileLyricsPanel(context, provider, song)),
          _buildMobileBottomControls(context, provider),
        ],
      ),
    );
  }

  Widget _buildMobileLyricsPanel(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    if (song == null) return const SizedBox();

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
    }

    if (_error != null || _lyrics == null || !_lyrics!.hasAnyLyrics) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            _error ?? 'Lyrics not available',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_lyrics!.instrumental) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.piano,
            size: 64,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'Instrumental',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    if (_lyrics!.hasSyncedLyrics && _lyricController != null) {
      return _buildFlutterLyricView(context, provider, isMobile: true);
    }

    return _buildPlainLyrics(isMobile: true);
  }

  Widget _buildFlutterLyricView(
    BuildContext context,
    MusicProvider provider, {
    required bool isMobile,
  }) {
    _lyricController!.setOnTapLineCallback((Duration position) {
      provider.seekTo(position);
    });

    return LyricView(
      controller: _lyricController!,
      style: _getLyricStyle(context, provider, isMobile: isMobile),
      width: double.infinity,
      height: double.infinity,
    );
  }

  Widget _buildPlainLyrics({required bool isMobile}) {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white,
            Colors.white,
            Colors.transparent,
          ],
          stops: const [0.0, 0.08, 0.92, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: ListView(
        padding: EdgeInsets.symmetric(
          vertical: isMobile ? 60 : 100,
          horizontal: isMobile ? 24 : 40,
        ),
        children: [
          Text(
            _lyrics!.plainLyrics ?? '',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: isMobile ? 20 : 24,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBottomControls(
    BuildContext context,
    MusicProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildProgressBar(context, provider),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: provider.toggleShuffle,
                iconSize: 24,
                icon: Icon(
                  Icons.shuffle_rounded,
                  color: provider.isShuffled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                ),
                tooltip: 'Shuffle',
              ),
              IconButton(
                onPressed: provider.playPrevious,
                iconSize: 28,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Previous',
              ),
              Container(
                height: 56,
                width: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: IconButton(
                  onPressed: provider.togglePlayPause,
                  iconSize: 28,
                  icon: Icon(
                    provider.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.black,
                  ),
                  tooltip: provider.isPlaying ? 'Pause' : 'Play',
                ),
              ),
              IconButton(
                onPressed: provider.playNext,
                iconSize: 28,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                tooltip: 'Next',
              ),
              IconButton(
                onPressed: provider.toggleRepeat,
                iconSize: 24,
                icon: Icon(
                  provider.repeatMode == RepeatMode.one
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  color: provider.repeatMode != RepeatMode.off
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                ),
                tooltip: 'Repeat',
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    if (song == null) return const SizedBox();

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 350,
                  maxWidth: 350,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: song.artworkPath != null
                          ? (song.artworkPath!.startsWith('http')
                                ? Image.network(
                                    song.artworkPath!,
                                    fit: BoxFit.cover,
                                  )
                                : Image.file(
                                    File(song.artworkPath!),
                                    fit: BoxFit.cover,
                                  ))
                          : Container(
                              color: Colors.grey[900],
                              child: const Icon(
                                Icons.music_note,
                                size: 80,
                                color: Colors.white54,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                song.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                song.artist,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildProgressBar(context, provider),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: provider.toggleShuffle,
                    iconSize: 24,
                    icon: Icon(
                      Icons.shuffle_rounded,
                      color: provider.isShuffled
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: provider.playPrevious,
                    iconSize: 32,
                    icon: const Icon(
                      Icons.skip_previous_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    height: 64,
                    width: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: IconButton(
                      onPressed: provider.togglePlayPause,
                      iconSize: 32,
                      icon: Icon(
                        provider.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: provider.playNext,
                    iconSize: 32,
                    icon: const Icon(
                      Icons.skip_next_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: provider.toggleRepeat,
                    iconSize: 24,
                    icon: Icon(
                      provider.repeatMode == RepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: provider.repeatMode != RepeatMode.off
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, MusicProvider provider) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: provider.currentPosition.inMilliseconds.toDouble().clamp(
              0,
              provider.totalDuration.inMilliseconds.toDouble(),
            ),
            max: provider.totalDuration.inMilliseconds.toDouble().clamp(
              1,
              double.infinity,
            ),
            onChanged: (value) {
              provider.seekTo(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(provider.currentPosition),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              Text(
                _formatDuration(provider.totalDuration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildRightPanel(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    if (song == null) return const SizedBox();

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
    }

    if (_error != null || _lyrics == null || !_lyrics!.hasAnyLyrics) {
      return Center(
        child: Text(
          _error ?? 'Lyrics not available',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (_lyrics!.instrumental) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.piano,
            size: 64,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 24),
          Text(
            'Instrumental',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    if (_lyrics!.hasSyncedLyrics && _lyricController != null) {
      return _buildFlutterLyricView(context, provider, isMobile: false);
    }

    return _buildPlainLyrics(isMobile: false);
  }
}
