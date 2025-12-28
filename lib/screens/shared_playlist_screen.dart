import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';
import '../providers/music_provider.dart';
import 'package:provider/provider.dart';

/// Screen for viewing a shared playlist via deep link
class SharedPlaylistScreen extends StatefulWidget {
  final String shareToken;

  const SharedPlaylistScreen({super.key, required this.shareToken});

  @override
  State<SharedPlaylistScreen> createState() => _SharedPlaylistScreenState();
}

class _SharedPlaylistScreenState extends State<SharedPlaylistScreen> {
  final ApiService _api = ApiService();

  bool _isLoading = true;
  String? _error;
  String? _errorMessage;
  Map<String, dynamic>? _playlistData;
  List<dynamic> _songs = [];

  @override
  void initState() {
    super.initState();
    _loadSharedPlaylist();
  }

  Future<void> _loadSharedPlaylist() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _api.getSharedPlaylist(widget.shareToken);

      if (result == null) {
        setState(() {
          _error = 'Not Found';
          _errorMessage = 'This share link could not be found.';
          _isLoading = false;
        });
        return;
      }

      // Check for error responses (revoked, expired)
      if (result['error'] != null) {
        setState(() {
          _error = result['error'] as String;
          _errorMessage = result['message'] as String? ?? 'An error occurred.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _playlistData = result['playlist'] as Map<String, dynamic>?;
        _songs = result['songs'] as List<dynamic>? ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error';
        _errorMessage = 'Failed to load shared playlist: $e';
        _isLoading = false;
      });
    }
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Shared Playlist',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_playlistData == null) {
      return const Center(
        child: Text('No playlist data', style: TextStyle(color: Colors.white)),
      );
    }

    return _buildPlaylistContent();
  }

  Widget _buildErrorState() {
    IconData icon;
    Color iconColor;

    switch (_error) {
      case 'Access revoked':
        icon = Icons.block;
        iconColor = Colors.red;
        break;
      case 'Link expired':
        icon = Icons.timer_off;
        iconColor = Colors.orange;
        break;
      default:
        icon = Icons.error_outline;
        iconColor = Colors.grey;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: iconColor),
            const SizedBox(height: 24),
            Text(
              _error!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.home),
              label: const Text('Go Home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistContent() {
    final playlist = _playlistData!;

    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Playlist icon
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple.shade800, Colors.blue.shade800],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.music_note,
                    size: 60,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 20),

                // Playlist name
                Text(
                  playlist['name'] ?? 'Untitled Playlist',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Owner and song count
                Text(
                  'Shared by ${playlist['owner_name'] ?? 'Unknown'} • ${_songs.length} songs',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),

                if (playlist['description'] != null &&
                    (playlist['description'] as String).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    playlist['description'],
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 24),

                // Play button
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _songs.isNotEmpty ? _playAll : null,
                      icon: const Icon(Icons.play_arrow, size: 28),
                      label: const Text(
                        'Play All',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Divider
        const SliverToBoxAdapter(
          child: Divider(color: Colors.white12, height: 1),
        ),

        // Songs list
        if (_songs.isEmpty)
          const SliverFillRemaining(
            child: Center(
              child: Text(
                'This playlist is empty',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildSongTile(_songs[index], index),
              childCount: _songs.length,
            ),
          ),

        // Bottom padding
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _buildSongTile(dynamic song, int index) {
    // Prefer cover_url (full URL from API) when available
    final coverUrl = song['cover_url'] as String?;
    final coverPath = song['cover_path'] as String?;
    final imageUrl =
        coverUrl ??
        (coverPath != null && coverPath.isNotEmpty
            ? '${ApiService.baseUrl}/$coverPath'
            : null);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: imageUrl != null
            ? Image.network(
                imageUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildDefaultCover(),
              )
            : _buildDefaultCover(),
      ),
      title: Text(
        song['title'] ?? 'Unknown',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        song['artist_name'] ?? 'Unknown Artist',
        style: TextStyle(color: Colors.grey[500], fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatDuration(song['duration_ms'] ?? 0),
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      ),
      onTap: () => _playSong(index),
    );
  }

  Widget _buildDefaultCover() {
    return Container(
      width: 48,
      height: 48,
      color: Colors.grey[800],
      child: const Icon(Icons.music_note, color: Colors.grey),
    );
  }

  void _playAll() {
    // TODO: Implement play all functionality
    // This would require converting shared songs to playable format
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Play all feature coming soon!'),
        backgroundColor: Colors.grey,
      ),
    );
  }

  void _playSong(int index) {
    // TODO: Implement single song play
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Song playback from shared playlists coming soon!'),
        backgroundColor: Colors.grey,
      ),
    );
  }
}
