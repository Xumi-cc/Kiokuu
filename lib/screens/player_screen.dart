import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../widgets/now_playing_card.dart';
import '../widgets/desktop_player_content.dart';
import 'lyrics_screen.dart';
import 'queue_screen.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer<MusicProvider>(
          builder: (context, provider, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                // Desktop Layout (Split View)
                if (constraints.maxWidth > 900) {
                  return const DesktopPlayerContent();
                }

                // Mobile Layout - Clean ViMusic-inspired design
                return Stack(
                  children: [
                    // Background Gradient
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            provider.backgroundColor ?? Colors.black,
                            Colors.black,
                          ],
                          stops: const [0.0, 0.7],
                        ),
                      ),
                    ),
                    // Main Content
                    SafeArea(
                      child: Column(
                        children: [
                          // Minimal App Bar
                          _buildAppBar(context),
                          // Now Playing Card takes up remaining space
                          const Expanded(child: NowPlayingCard()),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final playlistName = provider.currentPlaylistName ?? 'Library';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Close button
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                color: Colors.white.withOpacity(0.9),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
              // Playlist info
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Navigate to queue with slide up animation
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            const QueueScreen(),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              const begin = Offset(0.0, 1.0);
                              const end = Offset.zero;
                              const curve = Curves.easeOutCubic;
                              var tween = Tween(
                                begin: begin,
                                end: end,
                              ).chain(CurveTween(curve: curve));
                              return SlideTransition(
                                position: animation.drive(tween),
                                child: child,
                              );
                            },
                        transitionDuration: const Duration(milliseconds: 350),
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'PLAYING FROM',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 9,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        playlistName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              // Lyrics button
              IconButton(
                icon: const Icon(Icons.lyrics_outlined, size: 22),
                color: Colors.white.withOpacity(0.9),
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const LyricsScreen(),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
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
}
