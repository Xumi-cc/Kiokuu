import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/playlist_view.dart';
import '../widgets/now_playing_card.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/desktop_player_content.dart';
import 'lyrics_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showBottomBar = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Show bottom bar when scrolled down more than 100 pixels
    if (_scrollController.hasClients) {
      final shouldShow = _scrollController.offset > 100;
      if (shouldShow != _showBottomBar) {
        setState(() {
          _showBottomBar = shouldShow;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<MusicProvider>(
        builder: (context, provider, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              // Desktop Layout (Split View)
              if (constraints.maxWidth > 900) {
                return const DesktopPlayerContent();
              }


              // Mobile Layout (Single Column)
              return Stack(
                children: [
                  // Scrollable Content with Background
                  SingleChildScrollView(
                    controller: _scrollController,
                    child: Stack(
                      children: [
                        // Scrolling Background Gradient
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          height: constraints.maxHeight, // Full screen height
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                provider.backgroundColor ?? Colors.black,
                                Colors.black,
                              ],
                              stops: const [0.0, 0.6],
                            ),
                          ),
                        ),
                        // Content
                        Column(
                          children: [
                            SafeArea(child: _buildAppBar(context)),
                            const NowPlayingCard(),
                            const SizedBox(height: 20),
                            _buildPlaylistSection(context),
                            const SizedBox(height: 120), // Space for bottom bar
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bottom Player Bar (Hero disabled to avoid duplicates)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    left: 0,
                    right: 0,
                    bottom: _showBottomBar ? 0 : -100,
                    child: const BottomPlayerBar(
                      showFullControls: false,
                      enableHero: false, // Disable Hero on PlayerScreen to avoid duplicate tags
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: null,
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final playlistName = provider.currentPlaylistName ?? 'Library';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                color: Colors.white,
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Minimize',
              ),
              Column(
                children: [
                  Text(
                    'PLAYING FROM PLAYLIST',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    playlistName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.open_in_full, size: 24),
                color: Colors.white,
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const LyricsScreen(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return FadeTransition(
                          opacity: animation,
                          child: child,
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 300),
                    ),
                  );
                },
                tooltip: 'Lyrics',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaylistSection(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        if (provider.playlist.isEmpty) {
          return const SizedBox(height: 200, child: PlaylistView());
        }
        
        // Calculate height based on playlist size
        final itemCount = provider.playlist.length;
        final estimatedHeight = (itemCount * 70.0).clamp(200.0, 600.0);
        
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: const [0.0, 0.85, 1.0],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              height: estimatedHeight + 60, // Extra for header
              child: const PlaylistView(),
            ),
          ),
        );
      },
    );
  }
}
