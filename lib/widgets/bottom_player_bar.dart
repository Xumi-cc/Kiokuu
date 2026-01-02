import 'dart:io';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../providers/music_provider.dart';
import 'add_to_playlist_sheet.dart';

class BottomPlayerBar extends StatefulWidget {
  final VoidCallback? onTap;
  final bool showFullControls;
  final bool
  enableHero; // Set to false when inside PlayerScreen to avoid duplicate Hero tags

  const BottomPlayerBar({
    super.key,
    this.onTap,
    this.showFullControls = false,
    this.enableHero = true,
  });

  @override
  State<BottomPlayerBar> createState() => _BottomPlayerBarState();
}

class _BottomPlayerBarState extends State<BottomPlayerBar> {
  String? _previousSongId;
  bool _slideFromRight =
      true; // true = next (right to left), false = previous (left to right)

  void _updateDirection(String? currentSongId, MusicProvider provider) {
    if (_previousSongId != null &&
        currentSongId != null &&
        _previousSongId != currentSongId) {
      // Check if we went forward or backward in the playlist
      final previousIndex = provider.playlist.indexWhere(
        (s) => s.id == _previousSongId,
      );
      final currentIndex = provider.playlist.indexWhere(
        (s) => s.id == currentSongId,
      );

      if (previousIndex != -1 && currentIndex != -1) {
        // Determine direction: if current > previous, sliding forward (from right)
        final newSlideFromRight =
            currentIndex > previousIndex ||
            (currentIndex == 0 &&
                previousIndex == provider.playlist.length - 1);

        // Update direction synchronously so AnimatedSwitcher uses correct direction
        if (_slideFromRight != newSlideFromRight) {
          _slideFromRight = newSlideFromRight;
        }
      }
    }
    _previousSongId = currentSongId;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final song = provider.currentSong;

        // Update slide direction based on song change
        _updateDirection(song?.id, provider);

        // Don't show if no song is playing
        if (song == null) return const SizedBox.shrink();

        return LayoutBuilder(
          builder: (context, constraints) {
            // Use desktop layout for large screens (>800px)
            if (constraints.maxWidth > 800) {
              return _buildDesktopLayout(context, provider, song);
            }

            // Mobile layout with album art color
            final bgColor = provider.backgroundColor ?? Colors.grey[900]!;

            return ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: GestureDetector(
                  onTap: widget.onTap,
                  onHorizontalDragEnd: (details) {
                    // Swipe gestures for prev/next
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! < -500) {
                        provider.playNext();
                      } else if (details.primaryVelocity! > 500) {
                        provider.playPrevious();
                      }
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Main player bar container with album color
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeInOut,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              bgColor.withOpacity(0.95),
                              Colors.black.withOpacity(0.85),
                            ],
                          ),
                          border: Border(
                            top: BorderSide(
                              color: Colors.white.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                        ),
                        child: widget.showFullControls
                            ? _buildFullControls(context, provider, song)
                            : _buildCompactControls(context, provider, song),
                      ),
                      // Progress indicator
                      _buildProgressIndicator(provider),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Compact player bar (like the first image)
  Widget _buildCompactControls(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe left = next, Swipe right = previous
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -500) {
            // Swiped left - Next
            provider.playNext();
          } else if (details.primaryVelocity! > 500) {
            // Swiped right - Previous
            provider.playPrevious();
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            // Album Art with animation
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(_slideFromRight ? 0.2 : -0.2, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _buildArtworkWidget(song),
            ),
            const SizedBox(width: 12),

            // Song Info with animation (Hero optional based on enableHero)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeInOut,
                switchOutCurve: Curves.easeInOut,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: Offset(_slideFromRight ? 0.1 : -0.1, 0),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  key: ValueKey(song.id + '_info'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTitleWidget(song),
                    const SizedBox(height: 2),
                    _buildArtistWidget(song),
                  ],
                ),
              ),
            ),

            // Control Buttons with Hero for FLIP animation
            _buildPreviousButton(provider),
            _buildPlayPauseButton(provider),
            _buildNextButton(provider),
          ],
        ),
      ),
    );
  }

  // Full controls with progress bar (like the second image)
  Widget _buildFullControls(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress Bar
        _buildProgressBar(provider),

        // Main Controls Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Album Art
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white.withOpacity(0.1),
                  image: song.artworkPath != null
                      ? (song.artworkPath!.startsWith('http')
                            ? DecorationImage(
                                image: NetworkImage(song.artworkPath!),
                                fit: BoxFit.cover,
                              )
                            : DecorationImage(
                                image: FileImage(File(song.artworkPath!)),
                                fit: BoxFit.cover,
                              ))
                      : null,
                ),
                child: song.artworkPath == null
                    ? Icon(
                        Icons.music_note_rounded,
                        color: Colors.white.withOpacity(0.5),
                        size: 24,
                      )
                    : null,
              ),
              const SizedBox(width: 12),

              // Song Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      song.artist,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Playback Controls
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    color: provider.isShuffled
                        ? Colors.white
                        : Colors.white.withOpacity(0.7),
                    onPressed: provider.toggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 24),
                    color: Colors.white,
                    onPressed: provider.playPrevious,
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: provider.isLoading
                            ? null
                            : provider.togglePlayPause,
                        customBorder: const CircleBorder(),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: provider.isLoading
                                ? SizedBox(
                                    key: const ValueKey('full_loading'),
                                    width: 22,
                                    height: 22,
                                    child:
                                        LoadingAnimationWidget.threeArchedCircle(
                                          color: Colors.black,
                                          size: 22,
                                        ),
                                  )
                                : Icon(
                                    key: ValueKey(
                                      'full_${provider.isPlaying ? "pause" : "play"}',
                                    ),
                                    provider.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.black,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 24),
                    color: Colors.white,
                    onPressed: provider.playNext,
                  ),
                  IconButton(
                    icon: Icon(
                      provider.repeatMode == RepeatMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      size: 20,
                    ),
                    color: provider.repeatMode != RepeatMode.off
                        ? Colors.white
                        : Colors.white.withOpacity(0.7),
                    onPressed: provider.toggleRepeat,
                  ),
                ],
              ),

              // Additional Controls
              IconButton(
                icon: const Icon(Icons.queue_music_rounded, size: 20),
                color: Colors.white.withOpacity(0.7),
                onPressed: () {
                  // TODO: Show queue
                },
              ),
              IconButton(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                color: Colors.white.withOpacity(0.7),
                onPressed: () {
                  // TODO: Show more options
                },
              ),
              IconButton(
                icon: const Icon(Icons.fullscreen_rounded, size: 20),
                color: Colors.white.withOpacity(0.7),
                onPressed: widget.onTap,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(MusicProvider provider) {
    final position = provider.currentPosition;
    final duration = provider.totalDuration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.2),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withOpacity(0.2),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              final newPosition = Duration(
                milliseconds: (value * duration.inMilliseconds).round(),
              );
              provider.seekTo(newPosition);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildProgressIndicator(MusicProvider provider) {
    final position = provider.currentPosition;
    final duration = provider.totalDuration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return SizedBox(
      height: 3,
      child: Stack(
        children: [
          // Background
          Container(color: Colors.black.withOpacity(0.3)),
          // Progress fill (left to right)
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.9),
                      Colors.white.withOpacity(0.7),
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

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  // Helper method to build artwork with conditional Hero
  Widget _buildArtworkWidget(dynamic song) {
    final artworkContent = Material(
      type: MaterialType.transparency,
      child: Container(
        key: ValueKey(song.id),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.white.withOpacity(0.1),
          image: song.artworkPath != null
              ? (song.artworkPath!.startsWith('http')
                    ? DecorationImage(
                        image: NetworkImage(song.artworkPath!),
                        fit: BoxFit.cover,
                      )
                    : DecorationImage(
                        image: FileImage(File(song.artworkPath!)),
                        fit: BoxFit.cover,
                      ))
              : null,
        ),
        child: song.artworkPath == null
            ? Icon(
                Icons.music_note_rounded,
                color: Colors.white.withOpacity(0.5),
                size: 22,
              )
            : null,
      ),
    );

    if (!widget.enableHero) return artworkContent;

    return Hero(tag: 'player_artwork_${song.id}', child: artworkContent);
  }

  // Helper method to build title with conditional Hero
  Widget _buildTitleWidget(dynamic song) {
    final titleContent = Material(
      type: MaterialType.transparency,
      child: Text(
        song.title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (!widget.enableHero) return titleContent;

    return Hero(
      tag: 'player_title_${song.id}',
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            flightDirection,
            fromHeroContext,
            toHeroContext,
          ) {
            return Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                child: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
      child: titleContent,
    );
  }

  // Helper method to build artist with conditional Hero
  Widget _buildArtistWidget(dynamic song) {
    final artistContent = Material(
      type: MaterialType.transparency,
      child: Text(
        song.artist,
        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (!widget.enableHero) return artistContent;

    return Hero(
      tag: 'player_artist_${song.id}',
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            flightDirection,
            fromHeroContext,
            toHeroContext,
          ) {
            return Material(
              type: MaterialType.transparency,
              child: DefaultTextStyle(
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                ),
                child: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
      child: artistContent,
    );
  }

  // Helper method for Previous button with conditional Hero
  Widget _buildPreviousButton(MusicProvider provider) {
    final button = IconButton(
      icon: const Icon(Icons.skip_previous_rounded),
      color: Colors.white,
      iconSize: 24,
      onPressed: provider.playPrevious,
    );

    if (!widget.enableHero) return button;

    return Hero(
      tag: 'player_previous',
      child: Material(type: MaterialType.transparency, child: button),
    );
  }

  // Helper method for Play/Pause button with conditional Hero
  Widget _buildPlayPauseButton(MusicProvider provider) {
    final button = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: provider.isLoading ? null : provider.togglePlayPause,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: provider.isLoading
                ? SizedBox(
                    key: ValueKey('compact_hero_loading_${widget.enableHero}'),
                    width: 24,
                    height: 24,
                    child: LoadingAnimationWidget.threeArchedCircle(
                      color: Colors.white,
                      size: 24,
                    ),
                  )
                : Icon(
                    key: ValueKey(
                      'compact_hero_${widget.enableHero}_${provider.isPlaying ? "pause" : "play"}',
                    ),
                    provider.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
          ),
        ),
      ),
    );

    if (!widget.enableHero) return button;

    return Hero(tag: 'player_play_pause', child: button);
  }

  // Helper method for Next button with conditional Hero
  Widget _buildNextButton(MusicProvider provider) {
    final button = IconButton(
      icon: const Icon(Icons.skip_next_rounded),
      color: Colors.white,
      iconSize: 24,
      onPressed: provider.playNext,
    );

    if (!widget.enableHero) return button;

    return Hero(
      tag: 'player_next',
      child: Material(type: MaterialType.transparency, child: button),
    );
  }

  // Desktop Previous button with Hero
  Widget _buildDesktopPreviousButton(MusicProvider provider) {
    final button = IconButton(
      icon: const Icon(Icons.skip_previous_rounded),
      iconSize: 28,
      color: Colors.white.withOpacity(0.9),
      onPressed: provider.playPrevious,
    );

    if (!widget.enableHero) return button;

    return Hero(
      tag: 'player_previous',
      child: Material(type: MaterialType.transparency, child: button),
    );
  }

  // Desktop Play/Pause button with Hero
  Widget _buildDesktopPlayPauseButton(MusicProvider provider) {
    final button = Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: provider.isLoading ? null : provider.togglePlayPause,
          customBorder: const CircleBorder(),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: provider.isLoading
                  ? SizedBox(
                      key: const ValueKey('desktop_loading'),
                      width: 18,
                      height: 18,
                      child: LoadingAnimationWidget.threeArchedCircle(
                        color: Colors.black,
                        size: 18,
                      ),
                    )
                  : Icon(
                      key: ValueKey(
                        'desktop_${provider.isPlaying ? "pause" : "play"}',
                      ),
                      provider.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 24,
                    ),
            ),
          ),
        ),
      ),
    );

    if (!widget.enableHero) return button;

    return Hero(tag: 'player_play_pause', child: button);
  }

  // Desktop Next button with Hero
  Widget _buildDesktopNextButton(MusicProvider provider) {
    final button = IconButton(
      icon: const Icon(Icons.skip_next_rounded),
      iconSize: 28,
      color: Colors.white.withOpacity(0.9),
      onPressed: provider.playNext,
    );

    if (!widget.enableHero) return button;

    return Hero(
      tag: 'player_next',
      child: Material(type: MaterialType.transparency, child: button),
    );
  }

  // Desktop Player Bar (Spotify-like) - NEW METHOD for large screens
  Widget _buildDesktopLayout(
    BuildContext context,
    MusicProvider provider,
    dynamic song,
  ) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 90,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              // LEFT: Song Info (30%)
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    // Artwork with Hero animation
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: Offset(_slideFromRight ? 0.2 : -0.2, 0),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _buildArtworkWidget(song),
                    ),
                    const SizedBox(width: 8),
                    // Song title & artist with Hero animation
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeInOut,
                        switchOutCurve: Curves.easeInOut,
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: Offset(_slideFromRight ? 0.1 : -0.1, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          key: ValueKey('${song.id}_desktop_info'),
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTitleWidget(song),
                            const SizedBox(height: 4),
                            _buildArtistWidget(song),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // CENTER: Controls & Progress (40%)
              Expanded(
                flex: 4,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Controls Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.shuffle_rounded),
                          iconSize: 20,
                          color: provider.isShuffled
                              ? Colors.white
                              : Colors.white.withOpacity(0.6),
                          onPressed: provider.toggleShuffle,
                        ),
                        const SizedBox(width: 8),
                        // Previous button with Hero
                        _buildDesktopPreviousButton(provider),
                        const SizedBox(width: 12),
                        // Play/Pause with Hero
                        _buildDesktopPlayPauseButton(provider),
                        const SizedBox(width: 12),
                        // Next button with Hero
                        _buildDesktopNextButton(provider),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(
                            provider.repeatMode == RepeatMode.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded,
                          ),
                          iconSize: 20,
                          color: provider.repeatMode != RepeatMode.off
                              ? Colors.white
                              : Colors.white.withOpacity(0.6),
                          onPressed: provider.toggleRepeat,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Progress Bar Row
                    Row(
                      children: [
                        Text(
                          _formatDuration(provider.currentPosition),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 12,
                              ),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white.withOpacity(0.2),
                              thumbColor: Colors.white,
                              overlayColor: Colors.white.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: provider.totalDuration.inMilliseconds > 0
                                  ? (provider.currentPosition.inMilliseconds /
                                            provider
                                                .totalDuration
                                                .inMilliseconds)
                                        .clamp(0.0, 1.0)
                                  : 0.0,
                              onChanged: (value) {
                                final newPosition = Duration(
                                  milliseconds:
                                      (value *
                                              provider
                                                  .totalDuration
                                                  .inMilliseconds)
                                          .round(),
                                );
                                provider.seekTo(newPosition);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatDuration(provider.totalDuration),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // RIGHT: Volume & Tools (30%)
              Expanded(
                flex: 3,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Add to playlist button - shows checkmark if playing from a playlist
                    Builder(
                      builder: (ctx) {
                        final isInPlaylist = provider.currentPlaylistId != null;
                        return IconButton(
                          icon: Icon(
                            isInPlaylist
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                          ),
                          color: isInPlaylist
                              ? Colors.white
                              : Colors.white.withOpacity(0.7),
                          iconSize: 22,
                          onPressed: () => _showAddToPlaylistSheet(
                            context,
                            song.id,
                            song.title,
                          ),
                          tooltip: isInPlaylist
                              ? 'In Playlist'
                              : 'Add to Playlist',
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    if (MediaQuery.of(context).size.width > 1000) ...[
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded),
                        iconSize: 20,
                        color: Colors.white.withOpacity(0.7),
                        onPressed: () {},
                        tooltip: 'Queue',
                      ),
                      IconButton(
                        icon: const Icon(Icons.devices_rounded),
                        iconSize: 20,
                        color: Colors.white.withOpacity(0.7),
                        onPressed: () {},
                        tooltip: 'Devices',
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Volume icon + slider with mouse wheel support
                    Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          // Scroll up = positive delta.dy, scroll down = negative delta.dy
                          // We invert it: scroll up should increase volume
                          final delta = -event.scrollDelta.dy;
                          final volumeChange = delta > 0 ? 5.0 : -5.0;
                          final newVolume = (provider.volume + volumeChange)
                              .clamp(0.0, 100.0);
                          provider.setVolume(newVolume);
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            provider.volume == 0
                                ? Icons.volume_off_rounded
                                : provider.volume < 50
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                            color: Colors.white.withOpacity(0.7),
                            size: 20,
                          ),
                          SizedBox(
                            width: 100,
                            child: SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                                activeTrackColor: Colors.white,
                                inactiveTrackColor: Colors.white.withOpacity(
                                  0.2,
                                ),
                                thumbColor: Colors.white,
                                overlayColor: Colors.white.withOpacity(0.1),
                              ),
                              child: Slider(
                                value: provider.volume,
                                min: 0,
                                max: 100,
                                onChanged: (value) {
                                  provider.setVolume(value);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.open_in_full_rounded),
                      iconSize: 20,
                      color: Colors.white.withOpacity(0.7),
                      onPressed: widget.onTap,
                      tooltip: 'Full Screen',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddToPlaylistSheet(
    BuildContext context,
    String songId,
    String songTitle,
  ) {
    showAddToPlaylistSheet(context, songId, songTitle);
  }
}
