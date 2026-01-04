import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // For synced lyrics
  final ScrollController _scrollController = ScrollController();
  int _currentLineIndex = -1;
  bool _userIsScrolling = false;
  bool _isScrollAnimating = false; // Prevent overlapping animations

  // GlobalKeys for each lyric line (to use with Scrollable.ensureVisible)
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // Restore window state when leaving lyrics screen
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Ensure fullscreen is exited and max size is restored (fallback)
      windowManager.isFullScreen().then((isFullScreen) {
        if (isFullScreen) {
          windowManager.setFullScreen(false);
        }
        windowManager.setMaximumSize(const Size(1280, 720));
      });
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }

  Future<void> _enterFullscreen() async {
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      // Remove max size constraint first (required for Windows fullscreen)
      await windowManager.setMaximumSize(const Size(0, 0));
      await windowManager.setFullScreen(true);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  Future<void> _exitLyrics() async {
    // Exit fullscreen first for smooth transition
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await windowManager.setFullScreen(false);
      // Restore max size constraint
      await windowManager.setMaximumSize(const Size(1280, 720));
      // Small delay to let window animation complete
      await Future.delayed(const Duration(milliseconds: 100));
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
      _lineKeys.clear(); // Clear old keys when fetching new lyrics
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

  void _updateCurrentLine(Duration position, List<LyricLine> lines) {
    if (lines.isEmpty || _userIsScrolling) return;

    int newIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (position >= lines[i].timestamp) {
        newIndex = i;
      } else {
        break;
      }
    }

    if (newIndex != _currentLineIndex && newIndex >= 0) {
      setState(() {
        _currentLineIndex = newIndex;
      });
      _scrollToLine(newIndex);
    }
  }

  void _scrollToLine(int index) async {
    // Prevent overlapping animations (Echo-Music approach)
    if (_isScrollAnimating) return;

    // Try to use GlobalKey to accurately scroll to the item
    final key = _lineKeys[index];
    if (key?.currentContext != null) {
      _isScrollAnimating = true;
      try {
        await Scrollable.ensureVisible(
          key!.currentContext!,
          alignment: 0.4, // 0.4 = slightly above center (40% from top)
          duration: const Duration(
            milliseconds: 500,
          ), // Reduced for snappier feel
          curve: Curves.easeOutCubic,
        );
      } finally {
        _isScrollAnimating = false;
      }
      return;
    }

    // Fallback: Use estimated offset if key not available yet
    if (!_scrollController.hasClients) return;

    const double estimatedLineHeight = 85.0;
    double targetOffset = index * estimatedLineHeight;

    _isScrollAnimating = true;
    try {
      await _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isScrollAnimating = false;
    }
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
            _currentLineIndex = -1;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fetchLyrics(
                currentSong.title,
                currentSong.artist,
                durationSeconds: provider.totalDuration.inSeconds,
                songId: currentSong.id,
              );
            });
          }

          // Update current line for synced lyrics
          if (_lyrics?.hasSyncedLyrics == true) {
            final lines = _lyrics!.parsedSyncedLyrics;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateCurrentLine(provider.currentPosition, lines);
            });
          }

          return Stack(
            children: [
              // 1. Background (Gradient)
              _buildBackground(provider),

              // 2. Main Layout
              LayoutBuilder(
                builder: (context, constraints) {
                  // Use split layout for desktop
                  if (constraints.maxWidth > 900) {
                    return _buildSplitLayout(context, provider, currentSong);
                  }
                  // Fallback for smaller windows/mobile
                  return _buildMobileLayout(context, provider, currentSong);
                },
              ),

              // 3. Close Button (Top right) - Only show on desktop
              Positioned(
                top: 20,
                right: 20,
                child: Builder(
                  builder: (context) {
                    // Only show floating close button on desktop (mobile has header back button)
                    final screenWidth = MediaQuery.of(context).size.width;
                    if (screenWidth > 900) {
                      return SafeArea(
                        child: IconButton(
                          icon: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 24,
                              color: Colors.white,
                            ),
                          ),
                          onPressed: _exitLyrics,
                          tooltip: 'Close',
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
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
          // Left Side: Song Info & Controls
          Expanded(flex: 9, child: _buildLeftPanel(context, provider, song)),

          const SizedBox(width: 60),

          // Right Side: Scrolling Lyrics
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
          // Header Row: Back button, Title area, Menu button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Back button
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

                // Title area
                Expanded(
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

                // Menu button (placeholder for future menu actions)
                GestureDetector(
                  onTap: () {
                    // TODO: Show lyrics menu with options
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.more_horiz,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lyrics Area with fading edges
          Expanded(child: _buildMobileLyricsPanel(context, provider, song)),

          // Bottom Controls
          _buildMobileBottomControls(context, provider),
        ],
      ),
    );
  }

  /// Mobile-specific lyrics panel with fading edges and depth effects
  Widget _buildMobileLyricsPanel(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    if (song == null) return const SizedBox();

    // Loading State
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
    }

    // No Lyrics or Error
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

    // Instrumental
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

    // Synced Lyrics with depth effects
    if (_lyrics!.hasSyncedLyrics) {
      final lines = _lyrics!.parsedSyncedLyrics;

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
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification is ScrollStartNotification) {
              _userIsScrolling = true;
            } else if (notification is ScrollEndNotification) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  _userIsScrolling = false;
                  // Re-center on current line after user stops scrolling
                  if (_currentLineIndex >= 0) {
                    _scrollToLine(_currentLineIndex);
                  }
                }
              });
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: lines.length,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).size.height * 0.35,
                bottom: MediaQuery.of(context).size.height * 0.35,
              ),
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final line = lines[index];
                final isCurrent = index == _currentLineIndex;
                final distance = (index - _currentLineIndex).abs();

                // Create/retrieve GlobalKey for this line
                _lineKeys.putIfAbsent(index, () => GlobalKey());

                // Calculate opacity based on distance from current line (Echo-Music style)
                double opacity;
                if (isCurrent) {
                  opacity = 1.0;
                } else if (distance == 1) {
                  opacity = 0.7;
                } else if (distance == 2) {
                  opacity = 0.4;
                } else {
                  opacity = 0.2;
                }

                // Calculate scale based on distance (depth effect)
                double scale;
                if (isCurrent) {
                  scale = 1.0;
                } else if (distance == 1) {
                  scale = 0.95;
                } else {
                  scale = 0.9;
                }

                // Get next line timestamp for word timing calculation
                final nextLineTimestamp = index + 1 < lines.length
                    ? lines[index + 1].timestamp
                    : null;
                final words = line.parseWords(nextLineTimestamp);

                return RepaintBoundary(
                  child: GestureDetector(
                    key: _lineKeys[index],
                    onTap: () {
                      provider.seekTo(line.timestamp);
                    },
                    child: Transform.scale(
                      scale: scale,
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: words.map((word) {
                              return _buildMobileHighlightedWord(
                                word: word,
                                position: provider.currentPosition,
                                isCurrent: isCurrent,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    // Plain Lyrics with fading edges
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
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
        children: [
          Text(
            _lyrics!.plainLyrics ?? '',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Mobile word highlighting (simplified for mobile, center aligned)
  Widget _buildMobileHighlightedWord({
    required LyricWord word,
    required Duration position,
    required bool isCurrent,
  }) {
    final isWordPast = word.isPast(position);
    final isWordActive = word.isActive(position);
    final progress = word.getProgress(position);

    final highlightedColor = Colors.white;
    final dimmedColor = Colors.white.withValues(alpha: 0.5);

    // Font size - larger for current line
    final fontSize = isCurrent ? 26.0 : 22.0;

    Color textColor;
    if (isWordPast) {
      textColor = highlightedColor;
    } else if (isWordActive) {
      textColor = highlightedColor;
    } else {
      textColor = dimmedColor;
    }

    // For the currently active word, show a sweeping highlight effect
    if (isWordActive && isCurrent) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                highlightedColor,
                highlightedColor,
                dimmedColor,
                dimmedColor,
              ],
              stops: [
                0.0,
                progress.clamp(0.0, 1.0),
                progress.clamp(0.0, 1.0),
                1.0,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(
            word.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              height: 1.3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    // Regular word (past or future)
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Text(
        word.text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          height: 1.3,
          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
  }

  /// Bottom controls with playback buttons (Echo-Music style)
  Widget _buildMobileBottomControls(
    BuildContext context,
    MusicProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress Bar
          _buildProgressBar(context, provider),

          const SizedBox(height: 16),

          // Playback Controls Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Shuffle button
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

              // Previous button
              IconButton(
                onPressed: provider.playPrevious,
                iconSize: 28,
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                ),
                tooltip: 'Previous',
              ),

              // Play/Pause button
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

              // Next button
              IconButton(
                onPressed: provider.playNext,
                iconSize: 28,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                tooltip: 'Next',
              ),

              // Repeat button
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Album Art (Constrained size)
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

                // Title (Centered)
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

                // Artist (Centered)
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

                // Progress Bar
                _buildProgressBar(context, provider),

                const SizedBox(height: 24),

                // Playback Controls (Prev, Play/Pause, Next)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: provider.playPrevious,
                      iconSize: 32,
                      icon: const Icon(
                        Icons.skip_previous_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Previous',
                    ),
                    const SizedBox(width: 24),
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
                        tooltip: provider.isPlaying ? 'Pause' : 'Play',
                      ),
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      onPressed: provider.playNext,
                      iconSize: 32,
                      icon: const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Next',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(BuildContext context, MusicProvider provider) {
    final position = provider.currentPosition;
    final duration = provider.totalDuration;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.white.withValues(alpha: 0.8),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            thumbColor: Colors.white,
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: position.inMilliseconds.toDouble().clamp(
              0.0,
              duration.inMilliseconds.toDouble(),
            ),
            min: 0,
            max: duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
            onChanged: (value) {
              provider.seekTo(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
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

    // Loading State
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: Colors.white.withValues(alpha: 0.5),
        ),
      );
    }

    // No Lyrics or Error
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

    // Instrumental
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

    // Synced Lyrics List with Word-by-Word Highlighting and Echo-Music depth effects
    if (_lyrics!.hasSyncedLyrics) {
      final lines = _lyrics!.parsedSyncedLyrics;

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
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            if (notification is ScrollStartNotification) {
              _userIsScrolling = true;
            } else if (notification is ScrollEndNotification) {
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  _userIsScrolling = false;
                  // Re-center on current line after user stops scrolling
                  if (_currentLineIndex >= 0) {
                    _scrollToLine(_currentLineIndex);
                  }
                }
              });
            }
            return false;
          },
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: lines.length,
              padding: const EdgeInsets.only(top: 300, bottom: 300),
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final line = lines[index];
                final isCurrent = index == _currentLineIndex;
                final isPast = index < _currentLineIndex;
                final distance = (index - _currentLineIndex).abs();

                // Create/retrieve GlobalKey for this line
                _lineKeys.putIfAbsent(index, () => GlobalKey());

                // Calculate opacity based on distance from current line (Echo-Music style)
                double opacity;
                if (isCurrent) {
                  opacity = 1.0;
                } else if (distance == 1) {
                  opacity = 0.7;
                } else if (distance == 2) {
                  opacity = 0.4;
                } else {
                  opacity = 0.2;
                }

                // Calculate scale based on distance (depth effect)
                double scale;
                if (isCurrent) {
                  scale = 1.0;
                } else if (distance == 1) {
                  scale = 0.98;
                } else {
                  scale = 0.95;
                }

                // Get next line timestamp for word timing calculation
                final nextLineTimestamp = index + 1 < lines.length
                    ? lines[index + 1].timestamp
                    : null;
                final words = line.parseWords(nextLineTimestamp);

                return RepaintBoundary(
                  child: GestureDetector(
                    key: _lineKeys[index],
                    onTap: () {
                      provider.seekTo(line.timestamp);
                    },
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.center,
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: words.map((word) {
                              return _buildHighlightedWord(
                                word: word,
                                position: provider.currentPosition,
                                isCurrent: isCurrent,
                                isPastLine: isPast,
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    // Plain Lyrics
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 100, horizontal: 24),
      children: [
        Text(
          _lyrics!.plainLyrics ?? '',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            height: 1.6,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Builds a highlighted word widget with word-by-word progression
  Widget _buildHighlightedWord({
    required LyricWord word,
    required Duration position,
    required bool isCurrent,
    required bool isPastLine,
  }) {
    // Determine the highlight state of this word
    final isWordPast = word.isPast(position);
    final isWordActive = word.isActive(position);
    final progress = word.getProgress(position);

    // Colors
    final highlightedColor = Colors.white;
    final dimmedColor = Colors.white.withValues(alpha: 0.4);

    // Font size based on line state
    final fontSize = isCurrent ? 34.0 : 30.0;

    Color textColor;
    if (isPastLine || isWordPast) {
      // Past lines/words are fully highlighted
      textColor = highlightedColor;
    } else if (isWordActive) {
      // Active word - could add gradient effect here
      textColor = highlightedColor;
    } else {
      // Future words are dimmed
      textColor = dimmedColor;
    }

    // Build the word with a space after it
    if (isWordActive && isCurrent) {
      // For the currently active word, show a sweeping highlight effect
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                highlightedColor,
                highlightedColor,
                dimmedColor,
                dimmedColor,
              ],
              stops: [
                0.0,
                progress.clamp(0.0, 1.0),
                progress.clamp(0.0, 1.0),
                1.0,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(
            word.text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    // Regular word (past or future)
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        word.text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          height: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
