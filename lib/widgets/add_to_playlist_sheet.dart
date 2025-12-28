import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Shows a bottom sheet to add/remove the current song from playlists
/// Returns true if any playlist was modified
Future<bool> showAddToPlaylistSheet(
  BuildContext context,
  String songId,
  String songTitle, {
  VoidCallback? onPlaylistChanged,
}) async {
  final api = ApiService();
  bool wasModified = false;

  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      return AddToPlaylistSheet(
        api: api,
        songId: songId,
        songTitle: songTitle,
        onPlaylistChanged: () {
          wasModified = true;
          onPlaylistChanged?.call();
        },
      );
    },
  );

  return wasModified;
}

/// Stateful bottom sheet for adding/removing songs from playlists
class AddToPlaylistSheet extends StatefulWidget {
  final ApiService api;
  final String songId;
  final String songTitle;
  final VoidCallback? onPlaylistChanged;

  const AddToPlaylistSheet({
    super.key,
    required this.api,
    required this.songId,
    required this.songTitle,
    this.onPlaylistChanged,
  });

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  List<dynamic> _playlists = [];
  Set<String> _playlistsContainingSong = {};
  Set<String> _loadingPlaylistIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Load playlists and which ones contain the song in parallel
      final results = await Future.wait([
        widget.api.getPlaylists(),
        widget.api.getSongPlaylists(widget.songId),
      ]);

      final playlists = results[0] as List<dynamic>;
      final containingSong = results[1] as Set<String>;

      if (mounted) {
        setState(() {
          _playlists = playlists;
          _playlistsContainingSong = containingSong;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _togglePlaylist(String playlistId, String playlistName) async {
    if (_loadingPlaylistIds.contains(playlistId)) return;

    final isInPlaylist = _playlistsContainingSong.contains(playlistId);
    setState(() => _loadingPlaylistIds.add(playlistId));

    bool success;
    if (isInPlaylist) {
      success = await widget.api.removeSongFromPlaylist(
        playlistId,
        widget.songId,
      );
    } else {
      success = await widget.api.addSongToPlaylist(playlistId, widget.songId);
    }

    if (mounted) {
      setState(() {
        // Create new Set to ensure Flutter detects the change
        _loadingPlaylistIds = Set.from(_loadingPlaylistIds)..remove(playlistId);
        if (success) {
          // Create new Set to force rebuild
          final newSet = Set<String>.from(_playlistsContainingSong);
          if (isInPlaylist) {
            newSet.remove(playlistId);
          } else {
            newSet.add(playlistId);
          }
          _playlistsContainingSong = newSet;
          // Notify parent that playlists have changed
          widget.onPlaylistChanged?.call();
        }
      });

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${isInPlaylist ? "remove from" : "add to"} "$playlistName"',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Add to Playlist',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Song title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.songTitle,
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Colors.white12),
          // Playlist list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _playlists.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.playlist_add,
                          size: 48,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No playlists yet',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = _playlists[index];
                      final name = playlist['name'] ?? 'Untitled';
                      final playlistId = playlist['id'] ?? '';
                      final songCount = playlist['song_count'] ?? 0;
                      final coverImages =
                          playlist['cover_images'] as List<dynamic>? ?? [];

                      final isInPlaylist = _playlistsContainingSong.contains(
                        playlistId,
                      );
                      final isLoading = _loadingPlaylistIds.contains(
                        playlistId,
                      );

                      return ListTile(
                        key: ValueKey('$playlistId-$isInPlaylist'),
                        leading: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(4),
                            image: coverImages.isNotEmpty
                                ? DecorationImage(
                                    // Use cover_image_urls (full URLs) if available
                                    image: NetworkImage(
                                      (playlist['cover_image_urls'] as List?)
                                                  ?.isNotEmpty ==
                                              true
                                          ? (playlist['cover_image_urls']
                                                    as List)
                                                .first
                                          : coverImages[0]
                                                .toString()
                                                .startsWith('http')
                                          ? coverImages[0]
                                          : '${ApiService.baseUrl}/${coverImages[0]}',
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: coverImages.isEmpty
                              ? Icon(Icons.music_note, color: Colors.grey[600])
                              : null,
                        ),
                        title: Text(
                          name,
                          style: TextStyle(
                            color: isInPlaylist ? Colors.white : Colors.white,
                            fontWeight: isInPlaylist
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          isInPlaylist
                              ? 'Tap to remove • $songCount songs'
                              : '$songCount songs',
                          style: TextStyle(
                            color: isInPlaylist
                                ? Colors.white70
                                : Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                        trailing: isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : isInPlaylist
                            ? const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: Colors.redAccent,
                                size: 24,
                              )
                            : Icon(
                                Icons.add_circle_outline_rounded,
                                color: Colors.grey[500],
                                size: 24,
                              ),
                        onTap: isLoading
                            ? null
                            : () => _togglePlaylist(playlistId, name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
