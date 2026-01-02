import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import 'playlist_view.dart';

/// Desktop queue panel that slides in from the right side
class DesktopQueuePanel extends StatefulWidget {
  final VoidCallback onClose;

  const DesktopQueuePanel({super.key, required this.onClose});

  @override
  State<DesktopQueuePanel> createState() => _DesktopQueuePanelState();
}

class _DesktopQueuePanelState extends State<DesktopQueuePanel> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemHeight = 64.0;

  @override
  void initState() {
    super.initState();
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
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final currentIndex = provider.currentIndex;

    if (currentIndex >= 0 && _scrollController.hasClients) {
      final targetOffset =
          (currentIndex * _itemHeight) -
          (_scrollController.position.viewportDimension / 2) +
          (_itemHeight / 2);

      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.95),
        border: Border(
          left: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),
          // Queue List
          Expanded(child: _buildQueueList()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.queue_music_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Queue',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            iconSize: 20,
            color: Colors.white.withOpacity(0.7),
            onPressed: widget.onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList() {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        if (provider.playlist.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 48,
                  color: Colors.white.withOpacity(0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  'No songs in queue',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return ReorderableListView.builder(
          scrollController: _scrollController,
          padding: const EdgeInsets.only(
            top: 8,
            bottom: 100,
          ), // Bottom padding for player bar
          itemCount: provider.playlist.length,
          onReorder: (oldIndex, newIndex) {
            provider.reorderPlaylist(oldIndex, newIndex);
          },
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final animValue = Curves.easeInOut.transform(animation.value);
                final elevation = lerpDouble(0, 6, animValue) ?? 0;
                return Material(
                  elevation: elevation,
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                );
              },
              child: child,
            );
          },
          itemBuilder: (context, index) {
            final song = provider.playlist[index];
            final isPlaying = index == provider.currentIndex;

            return _buildQueueItem(
              key: ValueKey(song.id),
              song: song,
              index: index,
              isPlaying: isPlaying,
              provider: provider,
            );
          },
        );
      },
    );
  }

  Widget _buildQueueItem({
    required Key key,
    required dynamic song,
    required int index,
    required bool isPlaying,
    required MusicProvider provider,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          provider.playSongAtIndex(index);
        },
        child: Container(
          height: _itemHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isPlaying
                ? Colors.white.withOpacity(0.08)
                : Colors.transparent,
            border: isPlaying
                ? Border(left: BorderSide(color: Colors.white, width: 3))
                : null,
          ),
          child: Row(
            children: [
              // Index or playing indicator
              SizedBox(
                width: 28,
                child: isPlaying
                    ? SoundWaveAnimation(isPlaying: provider.isPlaying)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 8),
              // Artwork
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
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
                        size: 20,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Title & Artist
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: TextStyle(
                        color: isPlaying
                            ? Colors.white
                            : Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: isPlaying
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Drag handle
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: Colors.white.withOpacity(0.4),
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double? lerpDouble(num a, num b, double t) {
  return a + (b - a) * t;
}
