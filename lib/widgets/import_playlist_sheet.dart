import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/extension_runtime_service.dart';
import '../models/extension_model.dart';
import '../screens/settings_screen.dart';
import '../utils/snackbar_utils.dart';

/// Represents a track to be imported
class ImportQueueItem {
  final String id;
  final String title;
  final List<String> artists;
  final String album;
  final String? coverArt;
  final int durationMs;

  PlaylistImportStatus status;
  double progress;
  String? errorMessage;
  String? downloadUrl;
  String? extensionName;

  ImportQueueItem({
    required this.id,
    required this.title,
    required this.artists,
    required this.album,
    this.coverArt,
    required this.durationMs,
    this.status = PlaylistImportStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
    this.downloadUrl,
    this.extensionName,
  });

  String get artistString => artists.join(', ');
}

enum PlaylistImportStatus {
  pending,
  verifying,
  downloading,
  uploading,
  completed,
  failed,
  skipped,
}

/// Sheet for importing playlists from external URLs
class ImportPlaylistSheet extends StatefulWidget {
  final VoidCallback? onComplete;

  const ImportPlaylistSheet({super.key, this.onComplete});

  static Future<void> show(BuildContext context, {VoidCallback? onComplete}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImportPlaylistSheet(onComplete: onComplete),
    );
  }

  @override
  State<ImportPlaylistSheet> createState() => _ImportPlaylistSheetState();
}

class _ImportPlaylistSheetState extends State<ImportPlaylistSheet> {
  final _api = ApiService();
  final _extensionService = ExtensionRuntimeService.instance;
  final _urlController = TextEditingController();

  // Playlist data
  String? _playlistName;
  String? _playlistCover;
  String? _playlistOwner;
  int _trackCount = 0;

  // Import queue
  List<ImportQueueItem> _queue = [];
  bool _isLoading = false;
  bool _isImporting = false;
  bool _isPaused = false;
  String? _errorMessage;

  // Stats
  int _completedCount = 0;
  int _failedCount = 0;
  int _skippedCount = 0;

  /// Get list of enabled download extensions
  List<ExtensionMetadata> get _downloadExtensions {
    return _extensionService.enabledExtensions
        .where(
          (e) =>
              e.type == ExtensionType.downloader ||
              e.type == ExtensionType.full,
        )
        .toList();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Fetch playlist from URL
  Future<void> _fetchPlaylist() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Please enter a playlist URL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _api.fetchExternalPlaylist(url);
      if (result != null) {
        setState(() {
          _playlistName = result['name'];
          _playlistCover = result['cover_art'];
          _playlistOwner = result['owner'];
          _trackCount = result['track_count'] ?? 0;

          // Build queue from tracks
          final tracks = result['tracks'] as List<dynamic>? ?? [];
          _queue = tracks.map((t) {
            final artists =
                (t['artists'] as List<dynamic>?)
                    ?.map((a) => a.toString())
                    .toList() ??
                [];
            return ImportQueueItem(
              id: t['id'] ?? '',
              title: t['title'] ?? 'Unknown',
              artists: artists,
              album: t['album'] ?? '',
              coverArt: t['cover_art'],
              durationMs: t['duration_ms'] ?? 0,
            );
          }).toList();

          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage =
              'Could not fetch playlist. Make sure it\'s a public playlist.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to fetch playlist: $e';
        _isLoading = false;
      });
    }
  }

  /// Start the import process
  Future<void> _startImport() async {
    if (_queue.isEmpty || _downloadExtensions.isEmpty) {
      setState(() => _errorMessage = 'No extensions available for downloading');
      return;
    }

    setState(() {
      _isImporting = true;
      _isPaused = false;
      _completedCount = 0;
      _failedCount = 0;
      _skippedCount = 0;
    });

    for (int i = 0; i < _queue.length; i++) {
      if (!mounted) break;
      if (_isPaused) {
        // Wait until unpaused
        while (_isPaused && mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      final item = _queue[i];
      if (item.status == PlaylistImportStatus.completed ||
          item.status == PlaylistImportStatus.skipped) {
        continue;
      }

      await _processItem(i);
    }

    if (mounted) {
      setState(() => _isImporting = false);

      if (_completedCount > 0) {
        widget.onComplete?.call();
        AppSnackbar.show(
          context,
          message: 'Imported $_completedCount songs successfully!',
          icon: Icons.check_circle,
        );
      }
    }
  }

  /// Process a single queue item
  Future<void> _processItem(int index) async {
    final item = _queue[index];

    // Step 1: Verify sources
    setState(() {
      item.status = PlaylistImportStatus.verifying;
      item.progress = 0.0;
    });

    String? downloadUrl;
    String? extensionName;

    for (final ext in _downloadExtensions) {
      try {
        final result = await _extensionService.getDownloadUrl(ext.id, item.id);
        if (result.success && result.data?.url != null) {
          downloadUrl = result.data!.url;
          extensionName = ext.name;
          break;
        }
      } catch (_) {}
    }

    if (downloadUrl == null) {
      setState(() {
        item.status = PlaylistImportStatus.failed;
        item.errorMessage = 'No source found';
        _failedCount++;
      });
      return;
    }

    // Step 2: Download
    setState(() {
      item.status = PlaylistImportStatus.downloading;
      item.downloadUrl = downloadUrl;
      item.extensionName = extensionName;
      item.progress = 0.0;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${item.id}.flac';

      // Download with progress
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Download failed: HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      final file = File(tempPath);
      final sink = file.openWrite();
      int receivedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (mounted && totalBytes > 0) {
          setState(() {
            item.progress =
                receivedBytes / totalBytes * 0.5; // 0-50% for download
          });
        }
      }
      await sink.close();

      // Step 3: Upload
      setState(() {
        item.status = PlaylistImportStatus.uploading;
        item.progress = 0.5;
      });

      final (success, message) = await _api.uploadSongWithProgress(
        item.id,
        tempPath,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              item.progress = 0.5 + (progress * 0.5); // 50-100% for upload
            });
          }
        },
      );

      // Clean up temp file
      try {
        await File(tempPath).delete();
      } catch (_) {}

      if (success) {
        setState(() {
          item.status = PlaylistImportStatus.completed;
          item.progress = 1.0;
          _completedCount++;
        });
      } else {
        setState(() {
          item.status = PlaylistImportStatus.failed;
          item.errorMessage = message;
          _failedCount++;
        });
      }
    } catch (e) {
      setState(() {
        item.status = PlaylistImportStatus.failed;
        item.errorMessage = e.toString();
        _failedCount++;
      });
    }
  }

  /// Skip a track
  void _skipItem(int index) {
    setState(() {
      _queue[index].status = PlaylistImportStatus.skipped;
      _skippedCount++;
    });
  }

  /// Toggle pause
  void _togglePause() {
    setState(() => _isPaused = !_isPaused);
  }

  String _formatDuration(int ms) {
    final minutes = (ms / 60000).floor();
    final seconds = ((ms % 60000) / 1000).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
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
          color: Color(0xFF121212),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.playlist_add,
                      color: Colors.black,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Import Playlist',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sync from Spotify or other services',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  24 + MediaQuery.of(context).viewPadding.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // URL Input (show if no playlist loaded)
                    if (_queue.isEmpty) ...[
                      _buildUrlInput(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _buildErrorMessage(),
                      ],
                    ],

                    // Playlist Preview & Queue
                    if (_queue.isNotEmpty) ...[
                      _buildPlaylistHeader(),
                      const SizedBox(height: 16),
                      _buildProgressStats(),
                      const SizedBox(height: 16),
                      _buildQueue(),
                      const SizedBox(height: 24),
                      _buildActionButtons(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUrlInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PLAYLIST URL',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _urlController,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'https://open.spotify.com/playlist/...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            prefixIcon: const Icon(Icons.link, color: Colors.white54),
            suffixIcon: IconButton(
              icon: const Icon(Icons.content_paste, color: Colors.white),
              tooltip: 'Paste',
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _urlController.text = data!.text!;
                  // Auto-submit if it looks like a valid URL
                  if (_urlController.text.startsWith('http')) {
                    _fetchPlaylist();
                  }
                }
              },
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.05),
            contentPadding: const EdgeInsets.all(20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white, width: 1),
            ),
          ),
          onSubmitted: (_) => _fetchPlaylist(),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _fetchPlaylist,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : const Text(
                    'Fetch Playlist',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 16),
        if (_downloadExtensions.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.extension_off_outlined,
                  color: Colors.grey[400],
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enable download extensions in Settings to import playlists.',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Close sheet
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(
                          initialCategory: SettingsCategory.extensions,
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: Colors.white.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Open Settings',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.white.withOpacity(0.8),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _playlistCover != null
                  ? Image.network(
                      _playlistCover!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildDefaultCover(),
                    )
                  : _buildDefaultCover(),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _playlistName ?? 'Unknown Playlist',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (_playlistOwner != null)
                  Text(
                    'by $_playlistOwner',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$_trackCount tracks',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
            onPressed: () {
              setState(() {
                _queue = [];
                _playlistName = null;
                _playlistCover = null;
                _playlistOwner = null;
                _trackCount = 0;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultCover() {
    return Container(
      width: 64,
      height: 64,
      color: Colors.grey[800],
      child: const Icon(Icons.album, color: Colors.grey, size: 32),
    );
  }

  Widget _buildProgressStats() {
    final pending = _queue
        .where((i) => i.status == PlaylistImportStatus.pending)
        .length;
    final inProgress = _queue
        .where(
          (i) =>
              i.status == PlaylistImportStatus.verifying ||
              i.status == PlaylistImportStatus.downloading ||
              i.status == PlaylistImportStatus.uploading,
        )
        .length;

    return Row(
      children: [
        _buildStatChip('Pending', pending, Colors.grey[600]!),
        const SizedBox(width: 8),
        _buildStatChip('Working', inProgress, Colors.white),
        const SizedBox(width: 8),
        _buildStatChip('Done', _completedCount, Colors.white.withOpacity(0.6)),
        if (_failedCount > 0) ...[
          const SizedBox(width: 8),
          _buildStatChip('Failed', _failedCount, Colors.white),
        ],
        if (_skippedCount > 0) ...[
          const SizedBox(width: 8),
          _buildStatChip('Skipped', _skippedCount, Colors.grey[800]!),
        ],
      ],
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    final isWhite = color == Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isWhite ? Colors.white : color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isWhite ? Colors.white : color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        '$count $label',
        style: TextStyle(
          color: isWhite ? Colors.black : color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildQueue() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _queue.length,
        itemBuilder: (context, index) => _buildQueueItem(index),
      ),
    );
  }

  Widget _buildQueueItem(int index) {
    final item = _queue[index];
    Color statusColor;
    IconData statusIcon;

    switch (item.status) {
      case PlaylistImportStatus.pending:
        statusColor = Colors.grey[800]!;
        statusIcon = Icons.circle_outlined;
        break;
      case PlaylistImportStatus.verifying:
        statusColor = Colors.white;
        statusIcon = Icons.search;
        break;
      case PlaylistImportStatus.downloading:
        statusColor = Colors.white;
        statusIcon = Icons.download;
        break;
      case PlaylistImportStatus.uploading:
        statusColor = Colors.white;
        statusIcon = Icons.cloud_upload;
        break;
      case PlaylistImportStatus.completed:
        statusColor = Colors.white;
        statusIcon = Icons.check_circle;
        break;
      case PlaylistImportStatus.failed:
        statusColor = Colors.white;
        statusIcon = Icons.error_outline;
        break;
      case PlaylistImportStatus.skipped:
        statusColor = Colors.grey[700]!;
        statusIcon = Icons.skip_next;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.02)),
        ),
      ),
      child: Row(
        children: [
          // Status icon or progress
          SizedBox(
            width: 32,
            height: 32,
            child:
                item.status == PlaylistImportStatus.downloading ||
                    item.status == PlaylistImportStatus.uploading
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: item.progress,
                        strokeWidth: 2,
                        color: Colors.white,
                        backgroundColor: Colors.white10,
                      ),
                      // Tiny icon inside loader?
                      Icon(
                        item.status == PlaylistImportStatus.uploading
                            ? Icons.cloud_upload
                            : Icons.download,
                        size: 12,
                        color: Colors.white,
                      ),
                    ],
                  )
                : Icon(
                    statusIcon,
                    color: statusColor,
                    size: item.status == PlaylistImportStatus.pending ? 14 : 20,
                  ),
          ),
          const SizedBox(width: 12),

          // Cover art
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: item.coverArt != null
                ? Image.network(
                    item.coverArt!,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.grey,
                        size: 20,
                      ),
                    ),
                  )
                : Container(
                    width: 40,
                    height: 40,
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ),
          ),
          const SizedBox(width: 12),

          // Track info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  item.artistString,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.errorMessage != null)
                  Text(
                    item.errorMessage!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Duration
          Text(
            _formatDuration(item.durationMs),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),

          // Skip button (only for pending items)
          if (item.status == PlaylistImportStatus.pending && _isImporting)
            IconButton(
              icon: const Icon(Icons.skip_next, color: Colors.grey, size: 20),
              onPressed: () => _skipItem(index),
              tooltip: 'Skip',
            ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_isImporting) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _togglePause,
              icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
              label: Text(_isPaused ? 'Resume' : 'Pause'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() => _isImporting = false);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _downloadExtensions.isEmpty ? null : _startImport,
        icon: const Icon(Icons.download, size: 20),
        label: Text(
          'Start Import (${_queue.length})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.grey[800],
          disabledForegroundColor: Colors.grey[600],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
