import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animations/animations.dart';
import 'package:audio_session/audio_session.dart' as as_lib;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../providers/music_provider.dart';
import 'add_to_playlist_sheet.dart';

class NowPlayingCard extends StatefulWidget {
  const NowPlayingCard({super.key});

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> {
  String? _previousSongId;
  int _previousIndex = -1;
  bool _isNext = true;

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final song = provider.currentSong;

        // Determine direction
        if (song?.id != _previousSongId) {
          if (provider.currentIndex > _previousIndex) {
            _isNext = true;
          } else if (provider.currentIndex < _previousIndex) {
            _isNext = false;
          }
          _previousSongId = song?.id;
          _previousIndex = provider.currentIndex;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate available height for content
            final availableHeight = constraints.maxHeight;
            final availableWidth = constraints.maxWidth;

            // Calculate ideal artwork size based on width - larger for ViMusic-style design
            final idealArtworkSize = (availableWidth * 0.85).clamp(
              200.0,
              380.0,
            );

            // Estimate total height needed for all elements
            final estimatedHeight =
                idealArtworkSize + 40 + 80 + 20 + 80 + 10 + 80 + 20 + 60;

            // If content would overflow, scale down the artwork
            final artworkSize = availableHeight < estimatedHeight
                ? (idealArtworkSize * (availableHeight / estimatedHeight))
                      .clamp(150.0, idealArtworkSize)
                : idealArtworkSize;

            // Scale spacing proportionally
            final spacingScale = availableHeight < estimatedHeight
                ? (availableHeight / estimatedHeight).clamp(0.5, 1.0)
                : 1.0;

            // Always use Hero animation for FLIP effect between BottomPlayerBar and PlayerScreen
            const useHero = true;

            Widget artworkWidget = Material(
              type: MaterialType.transparency,
              child: Container(
                width: artworkSize,
                height: artworkSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white.withOpacity(0.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: PageTransitionSwitcher(
                    duration: const Duration(milliseconds: 400),
                    reverse: !_isNext,
                    transitionBuilder:
                        (child, primaryAnimation, secondaryAnimation) {
                          return SharedAxisTransition(
                            animation: primaryAnimation,
                            secondaryAnimation: secondaryAnimation,
                            transitionType: SharedAxisTransitionType.horizontal,
                            fillColor: Colors.transparent,
                            child: child,
                          );
                        },
                    child: RepaintBoundary(
                      key: ValueKey(song?.id ?? 'art_empty'),
                      child: song?.artworkPath != null
                          ? (song!.artworkPath!.startsWith('http')
                                ? Image.network(
                                    song.artworkPath!,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    cacheWidth: 600,
                                    errorBuilder: (_, __, ___) =>
                                        _buildDefaultArtwork(
                                          provider.isPlaying,
                                        ),
                                  )
                                : Image.file(
                                    File(song.artworkPath!),
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    cacheWidth: 600,
                                  ))
                          : _buildDefaultArtwork(provider.isPlaying),
                    ),
                  ),
                ),
              ),
            );

            if (useHero) {
              artworkWidget = Hero(
                tag: 'player_artwork_${song?.id ?? 'empty'}',
                createRectTween: (begin, end) {
                  return MaterialRectArcTween(begin: begin, end: end);
                },
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
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.white.withOpacity(0.1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.4),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: song?.artworkPath != null
                                ? (song!.artworkPath!.startsWith('http')
                                      ? Image.network(
                                          song.artworkPath!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _buildDefaultArtwork(
                                                provider.isPlaying,
                                              ),
                                        )
                                      : Image.file(
                                          File(song.artworkPath!),
                                          fit: BoxFit.cover,
                                        ))
                                : _buildDefaultArtwork(provider.isPlaying),
                          ),
                        ),
                      );
                    },
                child: artworkWidget,
              );
            }

            // Slide down animation for small screens
            Widget content = Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                artworkWidget,
                SizedBox(height: 40 * spacingScale),
                // Song Info Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: PageTransitionSwitcher(
                          duration: const Duration(milliseconds: 300),
                          transitionBuilder:
                              (child, animation, secondaryAnimation) {
                                return SharedAxisTransition(
                                  animation: animation,
                                  secondaryAnimation: secondaryAnimation,
                                  transitionType:
                                      SharedAxisTransitionType.vertical,
                                  fillColor: Colors.transparent,
                                  child: child,
                                );
                              },
                          child: Column(
                            key: ValueKey(song?.id),
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Hero(
                                tag: 'player_title_${song?.id ?? 'empty'}',
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
                                          style:
                                              Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ) ??
                                              const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                          child: Text(
                                            song?.title ?? 'Unknown Title',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      );
                                    },
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: Text(
                                    song?.title ?? 'Unknown Title',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Hero(
                                tag: 'player_artist_${song?.id ?? 'empty'}',
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
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.titleMedium?.copyWith(
                                                color: Colors.white.withOpacity(
                                                  0.7,
                                                ),
                                              ) ??
                                              TextStyle(
                                                color: Colors.white.withOpacity(
                                                  0.7,
                                                ),
                                              ),
                                          child: Text(
                                            song?.artist ?? 'Unknown Artist',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      );
                                    },
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: Text(
                                    song?.artist ?? 'Unknown Artist',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors.white.withOpacity(0.7),
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Add to playlist button - shows checkmark if playing from a playlist
                      Builder(
                        builder: (context) {
                          final isInCurrentPlaylist =
                              provider.currentPlaylistId != null;
                          return IconButton(
                            onPressed: song != null
                                ? () => _showAddToPlaylistSheet(
                                    context,
                                    song.id,
                                    song.title,
                                  )
                                : null,
                            icon: Icon(
                              isInCurrentPlaylist
                                  ? Icons.check_circle_rounded
                                  : Icons.add_circle_outline_rounded,
                            ),
                            color: isInCurrentPlaylist
                                ? Colors.white
                                : Colors.white,
                            iconSize: 28,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20 * spacingScale),
                _buildProgressBar(provider),
                SizedBox(height: 10 * spacingScale),
                _buildControlButtons(provider),
                SizedBox(height: 16 * spacingScale),
                // Bottom row: Device indicator only (cleaner ViMusic-inspired design)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Device indicator (like Spotify)
                      GestureDetector(
                        onTap: () {
                          // TODO: Show device picker
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getDeviceIcon(provider.deviceType),
                                color: Colors.white.withOpacity(0.8),
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                provider.deviceName,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );

            return GestureDetector(
              onHorizontalDragEnd: (details) {
                if (details.primaryVelocity == null) return;
                const sensitivity = 300;
                if (details.primaryVelocity! > sensitivity) {
                  provider.playPrevious();
                } else if (details.primaryVelocity! < -sensitivity) {
                  provider.playNext();
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: content,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDefaultArtwork(bool isPlaying) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          size: 80,
          color: Colors.white.withOpacity(0.3),
        ),
      ),
    );
  }

  Widget _buildProgressBar(MusicProvider provider) {
    final position = provider.currentPosition;
    final duration = provider.totalDuration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2, // Thinner track
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.2),
            thumbColor: Colors.white,
            overlayColor: Colors.white.withOpacity(0.2),
            trackShape: const RectangularSliderTrackShape(),
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
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  IconData _getRepeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.one:
        return Icons.repeat_one_rounded;
      case RepeatMode.all:
        return Icons.repeat_rounded;
      case RepeatMode.off:
        return Icons.repeat_rounded;
    }
  }

  IconData _getDeviceIcon(as_lib.AudioDeviceType? type) {
    if (type == null) {
      // Platform-based fallback icon
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        return Icons.computer_rounded;
      }
      return Icons.smartphone_rounded;
    }

    switch (type) {
      case as_lib.AudioDeviceType.bluetoothA2dp:
      case as_lib.AudioDeviceType.bluetoothSco:
      case as_lib.AudioDeviceType.bluetoothLe:
        return Icons.bluetooth_audio_rounded;
      case as_lib.AudioDeviceType.wiredHeadset:
      case as_lib.AudioDeviceType.wiredHeadphones:
        return Icons.headphones_rounded;
      case as_lib.AudioDeviceType.builtInSpeaker:
        return Icons.speaker_phone_rounded;
      default:
        return Icons.speaker_rounded;
    }
  }

  Widget _buildControlButtons(MusicProvider provider) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildIconButton(
            icon: Icons.shuffle_rounded,
            onPressed: provider.toggleShuffle,
            isActive: provider.isShuffled,
            activeColor: Colors.white,
          ),
          // Previous button with Hero
          Hero(
            tag: 'player_previous',
            child: Material(
              type: MaterialType.transparency,
              child: IconButton(
                icon: const Icon(Icons.skip_previous_rounded, size: 36),
                onPressed: provider.playPrevious,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
          // Play/Pause button with Hero
          Hero(
            tag: 'player_play_pause',
            child: _buildPlayPauseButton(provider),
          ),
          // Next button with Hero
          Hero(
            tag: 'player_next',
            child: Material(
              type: MaterialType.transparency,
              child: IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 36),
                onPressed: provider.playNext,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
          ),
          _buildIconButton(
            icon: _getRepeatIcon(provider.repeatMode),
            onPressed: provider.toggleRepeat,
            isActive: provider.repeatMode != RepeatMode.off,
            activeColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton(MusicProvider provider) {
    return Container(
      width: 64, // Larger button
      height: 64,
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
                      key: const ValueKey('nowplaying_loading'),
                      width: 32,
                      height: 32,
                      child: LoadingAnimationWidget.threeArchedCircle(
                        color: Colors.black,
                        size: 32,
                      ),
                    )
                  : Icon(
                      key: ValueKey(
                        'nowplaying_${provider.isPlaying ? "pause" : "play"}',
                      ),
                      provider.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 32,
                      color: Colors.black,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isActive = false,
    Color? activeColor,
    double size = 28,
  }) {
    return IconButton(
      icon: Icon(icon, size: size),
      onPressed: onPressed,
      color: isActive
          ? (activeColor ?? Colors.white)
          : Colors.white.withOpacity(0.7),
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
