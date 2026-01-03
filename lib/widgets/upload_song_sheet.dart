import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../utils/snackbar_utils.dart';

/// A beautiful, modern upload sheet with Spotify search
/// No more copying IDs - just search by song name!
class UploadSongSheet extends StatefulWidget {
  final VoidCallback? onSuccess;

  const UploadSongSheet({super.key, this.onSuccess});

  static Future<void> show(BuildContext context, {VoidCallback? onSuccess}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UploadSongSheet(onSuccess: onSuccess),
    );
  }

  @override
  State<UploadSongSheet> createState() => _UploadSongSheetState();
}

class _UploadSongSheetState extends State<UploadSongSheet> {
  final _api = ApiService();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  // State
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedTrack;
  PlatformFile? _pickedFile;
  bool _isSearching = false;
  bool _isPickingFile = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _errorMessage;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final results = await _api.searchSpotifyTracks(query.trim(), limit: 10);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _selectTrack(Map<String, dynamic> track) {
    setState(() {
      _selectedTrack = track;
      _searchResults = [];
      _searchController.clear();
      _errorMessage = null;
    });
    _searchFocusNode.unfocus();
  }

  Future<void> _pickFile() async {
    setState(() => _isPickingFile = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'flac', 'wav', 'ogg', 'm4a', 'aac', 'opus'],
      );
      if (mounted) {
        setState(() {
          _isPickingFile = false;
          if (result != null && result.files.isNotEmpty) {
            _pickedFile = result.files.first;
            _errorMessage = null;
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _upload() async {
    if (_selectedTrack == null || _pickedFile == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final (success, message) = await _api.uploadSongWithProgress(
        _selectedTrack!['id'],
        _pickedFile!.path!,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _uploadProgress = progress);
          }
        },
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context);
          widget.onSuccess?.call();
          AppSnackbar.show(context, message: message, icon: Icons.check_circle);
        } else {
          // Check for subscription required error
          if (message.startsWith('SUBSCRIPTION_REQUIRED:')) {
            Navigator.pop(context);
            _showSubscriptionRequiredSnackbar(
              context,
              message.substring('SUBSCRIPTION_REQUIRED:'.length),
            );
          } else if (message.startsWith('INVALID_AUDIO:')) {
            // Backend detected invalid audio (shouldn't happen if client validated)
            setState(() {
              _isUploading = false;
              _pickedFile = null; // Clear the invalid file
              _errorMessage = message.substring('INVALID_AUDIO:'.length);
            });
          } else {
            setState(() {
              _isUploading = false;
              _errorMessage = message;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _errorMessage = 'Upload failed: $e';
        });
      }
    }
  }

  void _showSubscriptionRequiredSnackbar(BuildContext context, String message) {
    AppSnackbar.subscriptionRequired(
      context,
      message: message,
      onSubscribe: () {
        // Navigate to subscription settings
        Navigator.of(context).pushNamed('/settings', arguments: 'subscription');
      },
    );
  }

  String _formatDuration(int? ms) {
    if (ms == null) return '';
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
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1DB954), Color(0xFF1ED760)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cloud_upload,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Upload Song',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Search for a song and upload your file',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content - wraps with keyboard-aware padding
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
                    // Selected Track or Search
                    if (_selectedTrack != null)
                      _buildSelectedTrack()
                    else
                      _buildSearchField(),

                    // Search Results
                    if (_searchResults.isNotEmpty && _selectedTrack == null)
                      _buildSearchResults(),

                    const SizedBox(height: 20),

                    // File Picker
                    _buildFilePicker(),

                    // Error Message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Upload Progress
                    if (_isUploading) ...[
                      const SizedBox(height: 20),
                      _buildUploadProgress(),
                    ],

                    const SizedBox(height: 24),

                    // Upload Button
                    _buildUploadButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 1: Find your song',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(color: Colors.white),
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search by song name or artist...',
            hintStyle: TextStyle(color: Colors.grey[600]),
            prefixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1DB954),
                      ),
                    ),
                  )
                : Icon(Icons.search, color: Colors.grey[500]),
            filled: true,
            fillColor: const Color(0xFF282828),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF1DB954), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final track = _searchResults[index];
          final artists = (track['artists'] as List?)?.join(', ') ?? 'Unknown';
          final albumArt = track['album_art'] as String?;
          final duration = _formatDuration(track['duration_ms'] as int?);

          return ListTile(
            onTap: () => _selectTrack(track),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: albumArt != null
                  ? Image.network(
                      albumArt,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: Colors.grey[800],
                        child: const Icon(Icons.music_note, color: Colors.grey),
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.grey),
                    ),
            ),
            title: Text(
              track['name'] ?? 'Unknown',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              artists,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              duration,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedTrack() {
    final track = _selectedTrack!;
    final artists = (track['artists'] as List?)?.join(', ') ?? 'Unknown';
    final albumArt = track['album_art'] as String?;
    final album = track['album'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 1: Song selected ✓',
          style: TextStyle(
            color: const Color(0xFF1DB954),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1DB954).withOpacity(0.15),
                const Color(0xFF1DB954).withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: albumArt != null
                    ? Image.network(
                        albumArt,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 64,
                          height: 64,
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.music_note,
                            color: Colors.grey,
                            size: 32,
                          ),
                        ),
                      )
                    : Container(
                        width: 64,
                        height: 64,
                        color: Colors.grey[800],
                        child: const Icon(
                          Icons.music_note,
                          color: Colors.grey,
                          size: 32,
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track['name'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artists,
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (album.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        album,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedTrack = null;
                    _errorMessage = null;
                  });
                },
                icon: const Icon(Icons.close, color: Colors.grey),
                tooltip: 'Change song',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilePicker() {
    final hasFile = _pickedFile != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasFile
              ? 'Step 2: File selected ✓'
              : 'Step 2: Select your audio file',
          style: TextStyle(
            color: hasFile ? const Color(0xFF1DB954) : Colors.grey[400],
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: (_isUploading || _isPickingFile) ? null : _pickFile,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: hasFile
                  ? const Color(0xFF1DB954).withOpacity(0.1)
                  : const Color(0xFF282828),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isPickingFile
                    ? const Color(0xFF1DB954)
                    : hasFile
                    ? const Color(0xFF1DB954).withOpacity(0.3)
                    : Colors.white10,
                width: (_isPickingFile || hasFile) ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hasFile
                        ? const Color(0xFF1DB954).withOpacity(0.2)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isPickingFile
                      ? const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF1DB954),
                            ),
                          ),
                        )
                      : Icon(
                          hasFile ? Icons.audio_file : Icons.upload_file,
                          color: hasFile
                              ? const Color(0xFF1DB954)
                              : Colors.grey[500],
                          size: 24,
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPickingFile
                            ? 'Opening file picker...'
                            : hasFile
                            ? _pickedFile!.name
                            : 'Tap to select file',
                        style: TextStyle(
                          color: _isPickingFile
                              ? Colors.white
                              : hasFile
                              ? Colors.white
                              : Colors.grey[400],
                          fontSize: 15,
                          fontWeight: (_isPickingFile || hasFile)
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isPickingFile
                            ? 'Please wait...'
                            : hasFile
                            ? _formatFileSize(_pickedFile!.size)
                            : 'MP3, FLAC, WAV, OGG, M4A, AAC',
                        style: TextStyle(
                          color: _isPickingFile
                              ? Colors.grey[400]
                              : Colors.grey[500],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasFile && !_isPickingFile)
                  IconButton(
                    onPressed: () => setState(() => _pickedFile = null),
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildUploadProgress() {
    final percent = (_uploadProgress * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                value: _uploadProgress,
                strokeWidth: 2.5,
                backgroundColor: Colors.white10,
                color: const Color(0xFF1DB954),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              percent < 100 ? 'Uploading... $percent%' : 'Processing...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _uploadProgress,
            minHeight: 6,
            backgroundColor: Colors.white10,
            color: const Color(0xFF1DB954),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          percent < 100
              ? 'Please keep the app open'
              : 'Adding to your library...',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildUploadButton() {
    final canUpload =
        _selectedTrack != null && _pickedFile != null && !_isUploading;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canUpload ? _upload : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1DB954),
          disabledBackgroundColor: Colors.grey[800],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
        ),
        child: Text(
          _isUploading ? 'Uploading...' : 'Upload Song',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
