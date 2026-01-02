import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../providers/music_provider.dart';
import '../models/song.dart';
import '../widgets/playlist_view.dart'; // For SoundWaveAnimation

class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 72.0; // Approximate height of queue item

  @override
  void initState() {
    super.initState();
    // Auto-scroll to current song after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSong();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentSong() {
    final provider = context.read<MusicProvider>();
    final currentIndex = provider.currentIndex;
    if (currentIndex >= 0 && currentIndex < provider.playlist.length) {
      // Calculate scroll position to center the current song
      final targetOffset =
          (currentIndex * _itemHeight) -
          (MediaQuery.of(context).size.height / 3);
      final maxScroll = _scrollController.position.maxScrollExtent;
      final clampedOffset = targetOffset.clamp(0.0, maxScroll);

      _scrollController.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

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
                        (provider.backgroundColor ?? Colors.black).withOpacity(
                          0.8,
                        ),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.4],
                    ),
                  ),
                ),
                // Content
                SafeArea(
                  child: Column(
                    children: [
                      // Collapsed Player Bar
                      _buildCollapsedPlayer(context, provider),
                      const Divider(color: Colors.white12, height: 1),
                      // Queue Header
                      _buildQueueHeader(context, provider),
                      // Queue List
                      Expanded(child: _buildQueueList(context, provider)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCollapsedPlayer(BuildContext context, MusicProvider provider) {
    final song = provider.currentSong;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            color: Colors.white,
            onPressed: () => Navigator.of(context).pop(),
          ),
          // Artwork (no Hero here to avoid animation conflict with slide)
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: Colors.white.withOpacity(0.1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: song?.artworkPath != null
                  ? (song!.artworkPath!.startsWith('http')
                        ? Image.network(
                            song.artworkPath!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildDefaultArtwork(),
                          )
                        : Image.file(
                            File(song.artworkPath!),
                            fit: BoxFit.cover,
                          ))
                  : _buildDefaultArtwork(),
            ),
          ),
          const SizedBox(width: 12),
          // Song Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  song?.title ?? 'Unknown Title',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song?.artist ?? 'Unknown Artist',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous_rounded, size: 28),
                color: Colors.white.withOpacity(0.8),
                onPressed: provider.playPrevious,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              _buildPlayPauseButton(provider),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 28),
                color: Colors.white.withOpacity(0.8),
                onPressed: provider.playNext,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayPauseButton(MusicProvider provider) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: provider.isLoading ? null : provider.togglePlayPause,
          customBorder: const CircleBorder(),
          child: Center(
            child: provider.isLoading
                ? LoadingAnimationWidget.threeArchedCircle(
                    color: Colors.black,
                    size: 18,
                  )
                : Icon(
                    provider.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 20,
                    color: Colors.black,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueHeader(BuildContext context, MusicProvider provider) {
    final playlistName = provider.currentPlaylistName ?? 'Queue';
    final songCount = provider.playlist.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Playing from',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                playlistName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Text(
            '$songCount songs',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList(BuildContext context, MusicProvider provider) {
    final playlist = provider.playlist;
    final currentIndex = provider.currentIndex;

    if (playlist.isEmpty) {
      return Center(
        child: Text(
          'Queue is empty',
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
        ),
      );
    }

    return ReorderableListView.builder(
      scrollController: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: playlist.length,
      onReorder: (oldIndex, newIndex) {
        provider.reorderPlaylist(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final double elevation = Tween<double>(
              begin: 0,
              end: 8,
            ).evaluate(animation);
            return Material(
              elevation: elevation,
              color: Colors.grey[900]?.withOpacity(0.95),
              borderRadius: BorderRadius.circular(8),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final song = playlist[index];
        final isPlaying = index == currentIndex;

        return _buildQueueItem(
          key: ValueKey(song.id),
          context: context,
          provider: provider,
          song: song,
          index: index,
          isPlaying: isPlaying,
        );
      },
    );
  }

  Widget _buildQueueItem({
    required Key key,
    required BuildContext context,
    required MusicProvider provider,
    required Song song,
    required int index,
    required bool isPlaying,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        color: isPlaying ? Colors.white.withOpacity(0.1) : Colors.transparent,
        border: isPlaying
            ? const Border(left: BorderSide(color: Colors.white, width: 3))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.white.withOpacity(0.1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: song.artworkPath != null
                ? (song.artworkPath!.startsWith('http')
                      ? Image.network(
                          song.artworkPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildDefaultArtwork(),
                        )
                      : Image.file(File(song.artworkPath!), fit: BoxFit.cover))
                : _buildDefaultArtwork(),
          ),
        ),
        title: Text(
          song.title,
          style: TextStyle(
            color: isPlaying ? Colors.white : Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          song.artist,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPlaying)
              SoundWaveAnimation(isPlaying: provider.isPlaying)
            else
              const SizedBox(width: 24),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: Colors.white.withOpacity(0.4),
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        onTap: () {
          provider.playSongAtIndex(index);
        },
      ),
    );
  }

  Widget _buildDefaultArtwork() {
    return Container(
      color: Colors.grey[900],
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withOpacity(0.3),
        size: 24,
      ),
    );
  }
}
