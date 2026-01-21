import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/music_provider.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../services/api_service.dart';

class PlaylistView extends StatelessWidget {
  const PlaylistView({super.key});

  @override
  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        if (provider.playlist.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.music_note_rounded,
                  size: 80,
                  color: Colors.white.withOpacity(0.2),
                ),
                const SizedBox(height: 16),
                Text(
                  'Your queue is empty',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Header - Echo-Music style
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Up Next',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${provider.playlist.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: provider.clearPlaylist,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(40, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),

            // List
            Expanded(
              child: ListView.builder(
                physics: const BouncingScrollPhysics(),
                itemCount: provider.playlist.length,
                itemBuilder: (context, index) {
                  final song = provider.playlist[index];
                  final isPlaying =
                      provider.currentSong?.id == song.id && provider.isPlaying;
                  final isCurrent = provider.currentSong?.id == song.id;

                  return Dismissible(
                    key: Key('${song.id}_$index'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: Colors.red.withValues(alpha: 0.8),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onDismissed: (_) => provider.removeSong(index),
                    child: InkWell(
                      onTap: () => provider.playSongAtIndex(index),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            // Artwork or Playing Indicator
                            SizedBox(
                              width: 42, // Reduced size
                              height: 42,
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.white.withOpacity(0.1),
                                      image: song.artworkPath != null
                                          ? (song.artworkPath!.startsWith(
                                                  'http',
                                                )
                                                ? DecorationImage(
                                                    image: NetworkImage(
                                                      song.artworkPath!,
                                                    ),
                                                    fit: BoxFit.cover,
                                                    colorFilter: isCurrent
                                                        ? ColorFilter.mode(
                                                            Colors.black
                                                                .withOpacity(
                                                                  0.5,
                                                                ),
                                                            BlendMode.darken,
                                                          )
                                                        : null,
                                                  )
                                                : DecorationImage(
                                                    image: FileImage(
                                                      File(song.artworkPath!),
                                                    ),
                                                    fit: BoxFit.cover,
                                                    colorFilter: isCurrent
                                                        ? ColorFilter.mode(
                                                            Colors.black
                                                                .withOpacity(
                                                                  0.5,
                                                                ),
                                                            BlendMode.darken,
                                                          )
                                                        : null,
                                                  ))
                                          : null,
                                    ),
                                    child: song.artworkPath == null
                                        ? Center(
                                            child: Icon(
                                              Icons.music_note,
                                              color: Colors.white.withOpacity(
                                                0.5,
                                              ),
                                              size: 20,
                                            ),
                                          )
                                        : null,
                                  ),
                                  if (isCurrent)
                                    Center(
                                      child: isPlaying
                                          ? const SoundWaveAnimation(
                                              isPlaying: true,
                                            )
                                          : const Icon(
                                              Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: 24,
                                            ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Title & Artist
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    song.title,
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: isCurrent
                                              ? Colors.white
                                              : Colors.white.withValues(
                                                  alpha: 0.6,
                                                ),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14, // Reduced font size
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    song.artist,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 12, // Reduced font size
                                        ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),

                            // Duration
                            const SizedBox(width: 8),
                            Text(
                              _formatDuration(song.duration),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 12,
                              ),
                            ),

                            // Menu
                            IconButton(
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white.withOpacity(0.4),
                                size: 18,
                              ),
                              onPressed: () =>
                                  _showSongMenu(context, provider, song, index),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSongMenu(
    BuildContext context,
    MusicProvider provider,
    Song song,
    int index,
  ) async {
    final currentUserId = await ApiService().userId;
    final isUploader = song.uploadedBy == currentUserId;

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 50,
              spreadRadius: 10,
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 20),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Song Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    // Album Art
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
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
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.artist,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withOpacity(0.6),
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Divider(color: Colors.white10, height: 1),
              const SizedBox(height: 8),

              // Actions
              _buildBottomSheetItem(
                sheetContext,
                icon: Icons.play_arrow_rounded,
                title: 'Play Now',
                onTap: () {
                  Navigator.pop(sheetContext);
                  provider.playSongAtIndex(index);
                },
              ),
              _buildBottomSheetItem(
                sheetContext,
                icon: Icons.playlist_play_rounded,
                title: 'Play Next',
                onTap: () {
                  Navigator.pop(sheetContext);
                  // TODO: Implement Play Next
                },
              ),
              _buildBottomSheetItem(
                sheetContext,
                icon: Icons.playlist_add_rounded,
                title: 'Add to Playlist',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showAddToPlaylistDialog(context, song);
                },
              ),
              _buildBottomSheetItem(
                sheetContext,
                icon: Icons.favorite_border_rounded,
                title: 'Add to Favorites',
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final api = ApiService();
                  final success = await api.likeSong(song.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success ? 'Added to favorites!' : 'Failed to add',
                        ),
                      ),
                    );
                  }
                },
              ),
              const Divider(color: Colors.white10, height: 32),
              _buildBottomSheetItem(
                sheetContext,
                icon: Icons.delete_outline_rounded,
                title: 'Remove from queue',
                color: Colors.orangeAccent,
                onTap: () {
                  Navigator.pop(sheetContext);
                  provider.removeSong(index);
                },
              ),
              if (isUploader)
                _buildBottomSheetItem(
                  sheetContext,
                  icon: Icons.delete_forever_rounded,
                  title: 'Delete song permanently',
                  color: Colors.redAccent,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        backgroundColor: const Color(0xFF1a1a1a),
                        title: const Text(
                          'Delete Song?',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: Text(
                          'Are you sure you want to permanently delete "${song.title}"? This cannot be undone.',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text(
                              'Delete',
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      final response = await ApiService().deleteSong(song.id);
                      if (response.$1 && context.mounted) {
                        provider.removeSongById(song.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Song deleted')),
                        );
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(response.$2)));
                      }
                    }
                  },
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, Song song) async {
    final api = ApiService();
    List<Playlist> playlists = [];
    bool isLoading = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Load playlists on first build
          if (isLoading) {
            api.getPlaylists().then((data) {
              setModalState(() {
                playlists = data.map((p) => Playlist.fromJson(p)).toList();
                isLoading = false;
              });
            });
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      const Text(
                        'Add to Playlist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showCreatePlaylistDialog(context, song);
                        },
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text(
                          'New',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white10, height: 24),

                // Playlist list
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else if (playlists.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.playlist_add,
                          size: 48,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No playlists yet',
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create your first playlist',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: playlists.length,
                      itemBuilder: (context, index) {
                        final playlist = playlists[index];
                        return ListTile(
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[800],
                              image: playlist.coverImages.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(
                                        // Use coverImageUrls (full URLs) if available
                                        playlist.coverImageUrls.isNotEmpty
                                            ? playlist.coverImageUrls[0]
                                            : playlist.coverImages[0]
                                                  .startsWith('http')
                                            ? playlist.coverImages[0]
                                            : '${ApiService.baseUrl}/${playlist.coverImages[0]}',
                                      ),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: playlist.coverImages.isEmpty
                                ? const Icon(
                                    Icons.music_note,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          title: Text(
                            playlist.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            '${playlist.songCount} songs',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                          onTap: () async {
                            Navigator.pop(context);
                            final success = await api.addSongToPlaylist(
                              playlist.id,
                              song.id,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? 'Added to "${playlist.name}"'
                                        : 'Failed to add song',
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, Song song) {
    final nameController = TextEditingController();
    final api = ApiService();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
        return AnimatedPadding(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                24,
                0,
                24,
                24 + MediaQuery.of(context).viewPadding.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  const Text(
                    'Create New Playlist',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Playlist name',
                      hintStyle: TextStyle(color: Colors.grey[600]),
                      filled: true,
                      fillColor: Colors.grey[900],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.trim().isEmpty) return;

                        final result = await api.createPlaylist(
                          nameController.text.trim(),
                        );

                        if (result != null && context.mounted) {
                          // Add song to the new playlist
                          final playlistId = result['id'];
                          await api.addSongToPlaylist(playlistId, song.id);

                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Created "${nameController.text}" and added song',
                              ),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'Create & Add Song',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: color ?? Colors.white, size: 24),
            const SizedBox(width: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: color ?? Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
}

class SoundWaveAnimation extends StatefulWidget {
  final bool isPlaying;
  const SoundWaveAnimation({super.key, required this.isPlaying});

  @override
  State<SoundWaveAnimation> createState() => _SoundWaveAnimationState();
}

class _SoundWaveAnimationState extends State<SoundWaveAnimation>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + (index * 200)),
      );
    });

    if (widget.isPlaying) {
      for (var controller in _controllers) {
        controller.repeat(reverse: true);
      }
    }
  }

  @override
  void didUpdateWidget(SoundWaveAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        for (var controller in _controllers) {
          controller.repeat(reverse: true);
        }
      } else {
        for (var controller in _controllers) {
          controller.stop();
        }
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Fixed height container to prevent "dancing"
    return SizedBox(
      height: 18, // Max bar height
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end, // Bars grow from bottom
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controllers[index],
            builder: (context, child) {
              return Container(
                width: 3,
                height: 6 + (_controllers[index].value * 12), // 6-18px range
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
