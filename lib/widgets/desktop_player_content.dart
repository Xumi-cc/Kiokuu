import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:window_manager/window_manager.dart';
import '../providers/music_provider.dart';
import '../services/api_service.dart';
import 'add_to_playlist_sheet.dart';

import 'equalizer_background.dart';
import '../screens/lyrics_screen.dart';

class DesktopPlayerContent extends StatefulWidget {
  const DesktopPlayerContent({super.key});

  @override
  State<DesktopPlayerContent> createState() => _DesktopPlayerContentState();
}

class _DesktopPlayerContentState extends State<DesktopPlayerContent> {
  final ApiService _api = ApiService();
  bool _isInCurrentPlaylist = false;
  bool _isCheckingStatus = false;
  bool _showVolumeSlider = false;
  Timer? _volumeHideTimer;
  String? _lastCheckedSongId;
  String? _lastCheckedPlaylistId;

  // Follow System
  bool _isFollowing = false;
  bool _isCheckingFollow = false;
  bool _isTogglingFollow = false;
  String? _currentArtistId;
  String? _currentArtistImage;
  int? _followerCount;
  String? _lastCheckedArtistSongId;

  String _formatFollowers(int? count) {
    if (count == null) return '';
    if (count < 1000) return '$count Followers';
    if (count < 1000000)
      return '${(count / 1000).toStringAsFixed(1)}K Followers';
    return '${(count / 1000000).toStringAsFixed(1)}M Followers';
  }

  @override
  void dispose() {
    _volumeHideTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPlaylistMembership();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    final provider = context.read<MusicProvider>();
    final song = provider.currentSong;

    if (song == null) {
      if (mounted) {
        setState(() {
          _currentArtistId = null;
          _currentArtistImage = null;
          _followerCount = null;
        });
      }
      return;
    }

    // Don't re-check if same song
    if (song.id == _lastCheckedArtistSongId && _currentArtistId != null) {
      return;
    }

    // Reset state for new song
    if (mounted) {
      setState(() {
        _isCheckingFollow = true;
        _isFollowing = false; // Reset to default until checked
        _currentArtistId = null;
        _currentArtistImage = null;
        _followerCount = null;
      });
    }

    try {
      // 1. Get Artist ID
      final artistData = await _api.getArtistFromSong(song.id);
      if (!mounted) return;

      final artistId = artistData?['artist_id'];

      setState(() {
        _currentArtistId = artistId;
        // Use image_url (full URL with domain from DB) if available, fallback to image_path
        _currentArtistImage = ApiService.getImageUrl(artistData);
        _followerCount = artistData?['follower_count'];
        _lastCheckedArtistSongId = song.id;
      });

      if (artistId != null) {
        // 2. Check status
        final isFollowing = await _api.checkArtistFollowStatus(artistId);
        if (mounted) {
          setState(() => _isFollowing = isFollowing);
        }
      }
    } finally {
      if (mounted) setState(() => _isCheckingFollow = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_currentArtistId == null || _isCheckingFollow || _isTogglingFollow)
      return;

    setState(() => _isTogglingFollow = true);

    try {
      bool success;
      int? newCount;

      if (_isFollowing) {
        (success, newCount) = await _api.unfollowArtist(_currentArtistId!);
      } else {
        (success, newCount) = await _api.followArtist(_currentArtistId!);
      }

      if (success && mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
          if (newCount != null) {
            _followerCount = newCount;
          }
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${_isFollowing ? "unfollow" : "follow"} artist',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTogglingFollow = false);
    }
  }

  Future<void> _checkPlaylistMembership() async {
    final provider = context.read<MusicProvider>();
    final song = provider.currentSong;
    final playlistId = provider.currentPlaylistId;

    // Skip if no song or no playlist
    if (song == null || playlistId == null) {
      if (_isInCurrentPlaylist) {
        setState(() => _isInCurrentPlaylist = false);
      }
      return;
    }

    // Skip if already checked for this song/playlist combo
    if (song.id == _lastCheckedSongId && playlistId == _lastCheckedPlaylistId) {
      return;
    }

    _lastCheckedSongId = song.id;
    _lastCheckedPlaylistId = playlistId;

    // Show loading state
    if (mounted) {
      setState(() => _isCheckingStatus = true);
    }

    // Check if this song is in the current playlist
    final playlists = await _api.getSongPlaylists(song.id);
    if (mounted) {
      setState(() {
        _isInCurrentPlaylist = playlists.contains(playlistId);
        _isCheckingStatus = false;
      });
    }
  }

  void _onPlaylistChanged() {
    // Force re-check after playlist change
    _lastCheckedSongId = null;
    _lastCheckedPlaylistId = null;
    _checkPlaylistMembership();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final song = provider.currentSong;
        if (song == null) return const SizedBox();

        // Check membership whenever song/playlist changes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (song.id != _lastCheckedSongId ||
              provider.currentPlaylistId != _lastCheckedPlaylistId) {
            _checkPlaylistMembership();
          }
          if (song.id != _lastCheckedArtistSongId) {
            _checkFollowStatus();
          }
        });

        return GestureDetector(
          // Enable window dragging on desktop
          onPanStart: (_) {
            if (!kIsWeb &&
                (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
              windowManager.startDragging();
            }
          },
          child: Stack(
            children: [
              // Background - Blurred/Gradient
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        provider.backgroundColor?.withOpacity(0.8) ??
                            Colors.black,
                        Colors.black,
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 20,
                  ),
                  child: Column(
                    children: [
                      // Top Bar
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            provider.currentPlaylistName ?? 'Favorites',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Volume & Close buttons with slider overlay
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Buttons row (fixed position)
                              Row(
                                children: [
                                  // Volume button with mouse wheel support
                                  Listener(
                                    onPointerSignal: (event) {
                                      if (event is PointerScrollEvent) {
                                        // Scroll up = positive delta.dy, scroll down = negative delta.dy
                                        // We invert it: scroll up should increase volume
                                        final delta = -event.scrollDelta.dy;
                                        final volumeChange = delta > 0
                                            ? 5.0
                                            : -5.0;
                                        final newVolume =
                                            (provider.volume + volumeChange)
                                                .clamp(0.0, 100.0);
                                        provider.setVolume(newVolume);
                                      }
                                    },
                                    child: MouseRegion(
                                      onEnter: (_) {
                                        _volumeHideTimer?.cancel();
                                        setState(
                                          () => _showVolumeSlider = true,
                                        );
                                      },
                                      onExit: (_) {
                                        _volumeHideTimer?.cancel();
                                        _volumeHideTimer = Timer(
                                          const Duration(milliseconds: 300),
                                          () {
                                            if (mounted) {
                                              setState(
                                                () => _showVolumeSlider = false,
                                              );
                                            }
                                          },
                                        );
                                      },
                                      child: IconButton(
                                        icon: Icon(
                                          provider.volume == 0
                                              ? Icons.volume_off_rounded
                                              : provider.volume < 50
                                              ? Icons.volume_down_rounded
                                              : Icons.volume_up_rounded,
                                          color: Colors.white,
                                        ),
                                        onPressed: () {
                                          if (provider.volume > 0) {
                                            provider.setVolume(0);
                                          } else {
                                            provider.setVolume(50);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                ],
                              ),
                              // Volume slider (appears below volume button) with mouse wheel support
                              if (_showVolumeSlider)
                                Positioned(
                                  top: 48,
                                  left: 0,
                                  child: Listener(
                                    onPointerSignal: (event) {
                                      if (event is PointerScrollEvent) {
                                        // Scroll up = positive delta.dy, scroll down = negative delta.dy
                                        // We invert it: scroll up should increase volume
                                        final delta = -event.scrollDelta.dy;
                                        final volumeChange = delta > 0
                                            ? 5.0
                                            : -5.0;
                                        final newVolume =
                                            (provider.volume + volumeChange)
                                                .clamp(0.0, 100.0);
                                        provider.setVolume(newVolume);
                                      }
                                    },
                                    child: MouseRegion(
                                      onEnter: (_) {
                                        _volumeHideTimer?.cancel();
                                      },
                                      onExit: (_) {
                                        _volumeHideTimer?.cancel();
                                        _volumeHideTimer = Timer(
                                          const Duration(milliseconds: 300),
                                          () {
                                            if (mounted) {
                                              setState(
                                                () => _showVolumeSlider = false,
                                              );
                                            }
                                          },
                                        );
                                      },
                                      child: Container(
                                        height: 120,
                                        width: 48,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF282828),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.5,
                                              ),
                                              blurRadius: 10,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: RotatedBox(
                                          quarterTurns: 3,
                                          child: SliderTheme(
                                            data: SliderThemeData(
                                              trackHeight: 3,
                                              thumbShape:
                                                  const RoundSliderThumbShape(
                                                    enabledThumbRadius: 6,
                                                  ),
                                              overlayShape:
                                                  const RoundSliderOverlayShape(
                                                    overlayRadius: 12,
                                                  ),
                                              activeTrackColor: Colors.white,
                                              inactiveTrackColor: Colors.white
                                                  .withOpacity(0.3),
                                              thumbColor: Colors.white,
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
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),

                      const Spacer(flex: 2),

                      // Main Content Area (Text Left, Image Right)
                      Expanded(
                        flex: 12,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Left Side: Text Info & Progress
                            Expanded(
                              flex: 5,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // Calculate responsive font sizes
                                  final screenWidth = MediaQuery.of(
                                    context,
                                  ).size.width;
                                  final titleFontSize = (screenWidth * 0.028)
                                      .clamp(20.0, 36.0);
                                  final artistFontSize = (screenWidth * 0.01)
                                      .clamp(11.0, 14.0);

                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Title with Hero for FLIP animation
                                      Hero(
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
                                                  style:
                                                      Theme.of(context)
                                                          .textTheme
                                                          .displayMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: Colors.white,
                                                            fontSize:
                                                                titleFontSize,
                                                            height: 1.1,
                                                          ) ??
                                                      const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                  child: Text(
                                                    song.title,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              );
                                            },
                                        child: Material(
                                          type: MaterialType.transparency,
                                          child: Text(
                                            song.title,
                                            style: Theme.of(context)
                                                .textTheme
                                                .displayMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                  fontSize: titleFontSize,
                                                  height: 1.1,
                                                ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Artist Row with Explicit Icon
                                      Row(
                                        children: [
                                          // Explicit Icon (E)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[800],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'E',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Artist with Hero for FLIP animation
                                          Hero(
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
                                                    type: MaterialType
                                                        .transparency,
                                                    child: InkWell(
                                                      onTap: () {
                                                        if (_currentArtistId !=
                                                            null) {
                                                          // Pop back to home and pass artist info
                                                          // so HomeScreen can show artist profile with sidebar
                                                          Navigator.of(
                                                            context,
                                                          ).pop({
                                                            'action':
                                                                'openArtist',
                                                            'artistId':
                                                                _currentArtistId!,
                                                            'artistName':
                                                                song.artist,
                                                            'artistImage':
                                                                _currentArtistImage,
                                                            'followerCount':
                                                                _followerCount,
                                                          });
                                                        }
                                                      },
                                                      hoverColor: Colors.white
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      child: DefaultTextStyle(
                                                        style:
                                                            Theme.of(context)
                                                                .textTheme
                                                                .titleLarge
                                                                ?.copyWith(
                                                                  color: Colors
                                                                      .white
                                                                      .withOpacity(
                                                                        0.7,
                                                                      ),
                                                                  letterSpacing:
                                                                      1.5,
                                                                  fontSize:
                                                                      artistFontSize,
                                                                ) ??
                                                            TextStyle(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                    0.7,
                                                                  ),
                                                            ),
                                                        child: Text(
                                                          song.artist
                                                              .toUpperCase(),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                            child: Material(
                                              type: MaterialType.transparency,
                                              child: Text(
                                                song.artist.toUpperCase(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      color: Colors.white
                                                          .withOpacity(0.7),
                                                      letterSpacing: 1.5,
                                                      fontSize: artistFontSize,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 48),

                                      // Progress Bar
                                      _buildProgressBar(context, provider),

                                      const SizedBox(height: 32),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.start,
                                        children: [
                                          // Previous button with Hero
                                          Hero(
                                            tag: 'player_previous',
                                            child: Material(
                                              type: MaterialType.transparency,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.skip_previous_rounded,
                                                ),
                                                color: Colors.white,
                                                iconSize: 32,
                                                onPressed:
                                                    provider.playPrevious,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          // Play/Pause button with Hero
                                          Hero(
                                            tag: 'player_play_pause',
                                            child: Container(
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.white,
                                              ),
                                              child: IconButton(
                                                icon: provider.isLoading
                                                    ? LoadingAnimationWidget.threeArchedCircle(
                                                        color: Colors.black,
                                                        size: 24,
                                                      )
                                                    : Icon(
                                                        provider.isPlaying
                                                            ? Icons
                                                                  .pause_rounded
                                                            : Icons
                                                                  .play_arrow_rounded,
                                                      ),
                                                color: Colors.black,
                                                iconSize: 40,
                                                onPressed: provider.isLoading
                                                    ? null
                                                    : provider.togglePlayPause,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          // Next button with Hero
                                          Hero(
                                            tag: 'player_next',
                                            child: Material(
                                              type: MaterialType.transparency,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.skip_next_rounded,
                                                ),
                                                color: Colors.white,
                                                iconSize: 32,
                                                onPressed: provider.playNext,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),

                            const Spacer(),

                            // Right Side: Album Art + Vertical Actions
                            Expanded(
                              flex: 4, // Smaller to give more room to text
                              child: Row(
                                children: [
                                  // Album Art - constrained max size
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 320,
                                      maxHeight: 320,
                                    ),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      clipBehavior: Clip.none,
                                      children: [
                                        Positioned.fill(
                                          child: EqualizerBackground(
                                            isPlaying: provider.isPlaying,
                                          ),
                                        ),
                                        // Album Art with Hero for FLIP animation
                                        Hero(
                                          tag: 'player_artwork_${song.id}',
                                          child: AspectRatio(
                                            aspectRatio: 1,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.5),
                                                    blurRadius: 30,
                                                    offset: const Offset(0, 15),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: song.artworkPath != null
                                                    ? (song.artworkPath!
                                                              .startsWith(
                                                                'http',
                                                              )
                                                          ? Image.network(
                                                              song.artworkPath!,
                                                              fit: BoxFit.cover,
                                                              gaplessPlayback:
                                                                  true,
                                                              errorBuilder:
                                                                  (
                                                                    _,
                                                                    __,
                                                                    ___,
                                                                  ) =>
                                                                      _buildDefaultArtwork(),
                                                            )
                                                          : Image.file(
                                                              File(
                                                                song.artworkPath!,
                                                              ),
                                                              fit: BoxFit.cover,
                                                              gaplessPlayback:
                                                                  true,
                                                              errorBuilder:
                                                                  (
                                                                    _,
                                                                    __,
                                                                    ___,
                                                                  ) =>
                                                                      _buildDefaultArtwork(),
                                                            ))
                                                    : _buildDefaultArtwork(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Push action bar to the right
                                  const Spacer(),

                                  // Vertical Action Bar (aligned with down arrow)
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.open_in_full,
                                          size: 20,
                                        ),
                                        color: Colors.white,
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            PageRouteBuilder(
                                              pageBuilder:
                                                  (
                                                    context,
                                                    animation,
                                                    secondaryAnimation,
                                                  ) => const LyricsScreen(),
                                              transitionsBuilder:
                                                  (
                                                    context,
                                                    animation,
                                                    secondaryAnimation,
                                                    child,
                                                  ) {
                                                    return FadeTransition(
                                                      opacity: animation,
                                                      child: child,
                                                    );
                                                  },
                                              transitionDuration:
                                                  const Duration(
                                                    milliseconds: 300,
                                                  ),
                                            ),
                                          );
                                        },
                                        tooltip: 'Lyrics',
                                      ),
                                      const SizedBox(height: 16),
                                      // Repeat button (cycles: off -> all -> one)
                                      Consumer<MusicProvider>(
                                        builder: (context, provider, _) {
                                          final repeatMode =
                                              provider.repeatMode;
                                          IconData icon;
                                          Color color;

                                          switch (repeatMode) {
                                            case RepeatMode.off:
                                              icon = Icons.repeat;
                                              color = Colors.white;
                                              break;
                                            case RepeatMode.all:
                                              icon = Icons.repeat;
                                              color = Colors.white;
                                              break;
                                            case RepeatMode.one:
                                              icon = Icons.repeat_one;
                                              color = Colors.white;
                                              break;
                                          }

                                          return IconButton(
                                            icon: Icon(icon),
                                            color: color,
                                            onPressed: provider.toggleRepeat,
                                            tooltip:
                                                repeatMode == RepeatMode.off
                                                ? 'Repeat Off'
                                                : repeatMode == RepeatMode.all
                                                ? 'Repeat All'
                                                : 'Repeat One',
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      // Shuffle button (shuffle play)
                                      Consumer<MusicProvider>(
                                        builder: (context, provider, _) {
                                          final isShuffled =
                                              provider.isShuffled;
                                          return IconButton(
                                            icon: const Icon(Icons.shuffle),
                                            color: isShuffled
                                                ? Colors.white
                                                : Colors.white,
                                            onPressed: () {
                                              // If already playing from a playlist, toggle shuffle
                                              if (provider.currentPlaylistId !=
                                                  null) {
                                                // If turning shuffle on, restart from beginning
                                                if (!isShuffled &&
                                                    provider
                                                        .playlist
                                                        .isNotEmpty) {
                                                  provider.toggleShuffle();
                                                  provider.playSongAtIndex(0);
                                                } else {
                                                  provider.toggleShuffle();
                                                }
                                              } else {
                                                // Just toggle if no playlist
                                                provider.toggleShuffle();
                                              }
                                            },
                                            tooltip: isShuffled
                                                ? 'Shuffle On'
                                                : 'Shuffle Play',
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      // Add to playlist / In playlist indicator
                                      _isCheckingStatus
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white.withOpacity(
                                                  0.7,
                                                ),
                                              ),
                                            )
                                          : IconButton(
                                              onPressed: () {
                                                showAddToPlaylistSheet(
                                                  context,
                                                  song.id,
                                                  song.title,
                                                  onPlaylistChanged:
                                                      _onPlaylistChanged,
                                                );
                                              },
                                              icon: Icon(
                                                _isInCurrentPlaylist
                                                    ? Icons.check_circle_rounded
                                                    : Icons
                                                          .add_circle_outline_rounded,
                                              ),
                                              color: _isInCurrentPlaylist
                                                  ? Colors.white
                                                  : Colors.white,
                                            ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Spacer(flex: 2),

                      // Bottom Bar (Artist Info & Tags)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Artist Info
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      if (_currentArtistId != null) {
                                        // Pop back to home with artist info
                                        Navigator.of(context).pop({
                                          'action': 'openArtist',
                                          'artistId': _currentArtistId!,
                                          'artistName': song.artist,
                                          'artistImage': _currentArtistImage,
                                          'followerCount': _followerCount,
                                        });
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: CircleAvatar(
                                      // _currentArtistImage is now always full URL from ApiService.getImageUrl
                                      backgroundImage:
                                          _currentArtistImage != null
                                          ? NetworkImage(_currentArtistImage!)
                                          : (song.artworkPath != null
                                                ? (song.artworkPath!.startsWith(
                                                        'http',
                                                      )
                                                      ? NetworkImage(
                                                          song.artworkPath!,
                                                        )
                                                      : FileImage(
                                                              File(
                                                                song.artworkPath!,
                                                              ),
                                                            )
                                                            as ImageProvider)
                                                : null),
                                      radius: 16,
                                      backgroundColor: Colors.grey[800],
                                      child:
                                          (_currentArtistImage == null &&
                                              song.artworkPath == null)
                                          ? const Icon(Icons.person, size: 16)
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        song.artist.toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (_followerCount != null)
                                        Text(
                                          _formatFollowers(_followerCount),
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(
                                              0.6,
                                            ),
                                            fontSize: 11,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(width: 16),
                                  if (_currentArtistId != null)
                                    SizedBox(
                                      height: 28,
                                      child: OutlinedButton(
                                        onPressed:
                                            (_isCheckingFollow ||
                                                _isTogglingFollow)
                                            ? null
                                            : _toggleFollow,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _isFollowing
                                              ? Colors.black
                                              : Colors.white,
                                          backgroundColor: _isFollowing
                                              ? Colors.white
                                              : Colors.transparent,
                                          side: const BorderSide(
                                            color: Colors.white,
                                            width: 1,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          minimumSize: Size
                                              .zero, // Removes default minimum size constraints
                                          tapTargetSize: MaterialTapTargetSize
                                              .shrinkWrap, // Removes extra touch padding
                                        ),
                                        child:
                                            (_isCheckingFollow ||
                                                _isTogglingFollow)
                                            ? LoadingAnimationWidget.staggeredDotsWave(
                                                color: _isFollowing
                                                    ? Colors.black
                                                    : Colors.white,
                                                size: 12,
                                              )
                                            : Text(
                                                _isFollowing
                                                    ? 'Following'
                                                    : 'Follow',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Tags (from MusicBrainz genres + tags)
                              Builder(
                                builder: (context) {
                                  final song = provider.currentSong;
                                  final allTags = <String>[];

                                  // Add genres first (as hashtags)
                                  if (song != null && song.genres.isNotEmpty) {
                                    allTags.addAll(
                                      song.genres.take(3).map((g) => '#$g'),
                                    );
                                  }

                                  // Add tags if we have room
                                  if (song != null &&
                                      song.tags.isNotEmpty &&
                                      allTags.length < 5) {
                                    final remainingSlots = 5 - allTags.length;
                                    allTags.addAll(
                                      song.tags
                                          .take(remainingSlots)
                                          .map((t) => '#$t'),
                                    );
                                  }

                                  if (allTags.isEmpty) {
                                    return const SizedBox.shrink();
                                  }

                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: allTags
                                        .map((tag) => _buildTag(tag))
                                        .toList(),
                                  );
                                },
                              ),
                            ],
                          ),

                          // Right Side Bottom Controls (Previous/Next)
                          Column(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.keyboard_arrow_up_rounded,
                                  size: 28,
                                ),
                                color: Colors.white,
                                onPressed: provider.playPrevious,
                                tooltip: 'Previous Song',
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 28,
                                ),
                                color: Colors.white,
                                onPressed: provider.playNext,
                                tooltip: 'Next Song',
                              ),
                            ],
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
      },
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, MusicProvider provider) {
    final position = provider.currentPosition;
    final duration = provider.totalDuration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return SizedBox(
      height: 4, // Thin line
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
          thumbColor: Colors.white,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white.withOpacity(0.2),
          overlayShape: SliderComponentShape.noOverlay,
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
    );
  }

  Widget _buildDefaultArtwork() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(Icons.music_note_rounded, size: 64, color: Colors.white54),
      ),
    );
  }
}
