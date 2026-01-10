import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/extension_runtime_service.dart';
import '../models/extension_model.dart';
import '../utils/snackbar_utils.dart';

/// Represents a verified download source (like backend health check)
class VerifiedSource {
  final String name;
  final String extensionId;
  final SourceStatus status;
  final String? downloadUrl;
  final String? message;
  final int? latencyMs;
  // Audio metadata
  final String? format;
  final String? codec;
  final int? bitDepth;
  final int? sampleRate;
  final String? quality;
  // Track metadata from source (for verification)
  final String? sourceTitle;
  final String? sourceArtist;
  final String? sourceAlbum;
  final String? sourceCoverUrl;
  final String? sourceIsrc;

  const VerifiedSource({
    required this.name,
    required this.extensionId,
    required this.status,
    this.downloadUrl,
    this.message,
    this.latencyMs,
    this.format,
    this.codec,
    this.bitDepth,
    this.sampleRate,
    this.quality,
    this.sourceTitle,
    this.sourceArtist,
    this.sourceAlbum,
    this.sourceCoverUrl,
    this.sourceIsrc,
  });
}

enum SourceStatus { ok, failed, checking }

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
  final _extensionService = ExtensionRuntimeService.instance;
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

  // Extension mode - with source verification like backend
  bool _useExtension = false;
  bool _isDownloadingFromExtension = false;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalDownloadBytes = 0;

  // Source verification (like backend health check)
  bool _isVerifyingSources = false;
  List<VerifiedSource> _verifiedSources = [];
  VerifiedSource? _selectedSource;

  @override
  void initState() {
    super.initState();
  }

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
      _verifiedSources = [];
      _selectedSource = null;
      _useExtension = false;
    });
    _searchFocusNode.unfocus();

    // Start source verification if extensions are available
    if (_downloadExtensions.isNotEmpty) {
      _verifySources();
    }
  }

  /// Verify which extension sources can download this track (like backend health check)
  Future<void> _verifySources() async {
    if (_selectedTrack == null) return;

    final spotifyId = _selectedTrack!['id'] as String;
    final extensions = _downloadExtensions;

    if (extensions.isEmpty) return;

    setState(() {
      _isVerifyingSources = true;
      _verifiedSources = extensions
          .map(
            (ext) => VerifiedSource(
              name: ext.name,
              extensionId: ext.id,
              status: SourceStatus.checking,
            ),
          )
          .toList();
    });

    // Verify each extension and update UI as they complete
    int completedCount = 0;
    for (final ext in extensions) {
      // Run each verification without awaiting to allow parallel execution
      _verifyExtension(ext, spotifyId).then((result) {
        if (!mounted) return;

        completedCount++;
        setState(() {
          // Update this specific source in the list
          final index = _verifiedSources.indexWhere(
            (s) => s.extensionId == ext.id,
          );
          if (index != -1) {
            _verifiedSources[index] = result;
          }

          // Auto-select first working source if none selected
          if (_selectedSource == null && result.status == SourceStatus.ok) {
            _selectedSource = result;
            _useExtension = true;
          }

          // Mark as done when all complete
          if (completedCount >= extensions.length) {
            _isVerifyingSources = false;
          }
        });
      });
    }
  }

  /// Verify a single extension
  Future<VerifiedSource> _verifyExtension(
    ExtensionMetadata ext,
    String spotifyId,
  ) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = await _extensionService.getDownloadUrl(ext.id, spotifyId);
      stopwatch.stop();

      if (result.success &&
          result.data != null &&
          result.data!.url.isNotEmpty) {
        final info = result.data!;
        return VerifiedSource(
          name: ext.name,
          extensionId: ext.id,
          status: SourceStatus.ok,
          downloadUrl: info.url,
          message: 'Ready to download',
          latencyMs: stopwatch.elapsedMilliseconds,
          format: info.format,
          codec: info.codec,
          bitDepth: info.bitDepth,
          sampleRate: info.sampleRate,
          quality: info.quality,
          sourceTitle: info.sourceTitle,
          sourceArtist: info.sourceArtist,
          sourceAlbum: info.sourceAlbum,
          sourceCoverUrl: info.sourceCoverUrl,
          sourceIsrc: info.sourceIsrc,
        );
      } else {
        return VerifiedSource(
          name: ext.name,
          extensionId: ext.id,
          status: SourceStatus.failed,
          message: result.error ?? 'No download URL found',
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return VerifiedSource(
        name: ext.name,
        extensionId: ext.id,
        status: SourceStatus.failed,
        message: e.toString(),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
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

  /// Download audio file using the selected verified source
  Future<void> _downloadWithExtension() async {
    if (_selectedTrack == null ||
        _selectedSource == null ||
        _selectedSource!.downloadUrl == null)
      return;

    setState(() {
      _isDownloadingFromExtension = true;
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
      _totalDownloadBytes = 0;
      _errorMessage = null;
    });

    try {
      final spotifyId = _selectedTrack!['id'] as String;
      final downloadUrl = _selectedSource!.downloadUrl!;

      // Download to temp file with progress tracking
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/$spotifyId.flac';

      // Use streaming request for progress tracking
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await http.Client().send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception('Download failed: HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      setState(() => _totalDownloadBytes = totalBytes);

      final file = File(tempPath);
      final sink = file.openWrite();
      int receivedBytes = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (mounted && totalBytes > 0) {
          setState(() {
            _downloadedBytes = receivedBytes;
            _downloadProgress = receivedBytes / totalBytes;
          });
        }
      }

      await sink.close();

      // Create PlatformFile for consistency
      _pickedFile = PlatformFile(
        name: '$spotifyId.flac',
        path: tempPath,
        size: receivedBytes,
      );

      setState(() {
        _isDownloadingFromExtension = false;
        _downloadProgress = 1.0;
      });

      // Automatically proceed to upload
      await _upload();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloadingFromExtension = false;
          _downloadProgress = 0.0;
          _errorMessage = 'Extension download failed: $e';
        });
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
          // Clean up temp file if it was from extension
          if (_pickedFile!.path!.contains('cache') ||
              _pickedFile!.path!.contains('temp')) {
            try {
              await File(_pickedFile!.path!).delete();
            } catch (_) {}
          }

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
    final hasExtension =
        _downloadExtensions.isNotEmpty && _selectedTrack != null;

    // If extension is available and no file picked yet, show extension option
    if (hasExtension && !hasFile && _useExtension) {
      return _buildExtensionDownloadOption();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
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
            ),
            // Toggle to extension mode if available
            if (_downloadExtensions.isNotEmpty && !hasFile)
              TextButton.icon(
                onPressed: () => setState(() => _useExtension = true),
                icon: const Icon(Icons.extension, size: 14),
                label: const Text('Auto', style: TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF4F6BF6),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
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

  Widget _buildExtensionDownloadOption() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _isVerifyingSources
                    ? 'Step 2: Verifying sources...'
                    : _isDownloadingFromExtension
                    ? 'Step 2: Auto-downloading...'
                    : 'Step 2: Choose a source',
                style: TextStyle(
                  color: const Color(0xFF4F6BF6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            // Toggle to manual mode
            TextButton.icon(
              onPressed: _isDownloadingFromExtension
                  ? null
                  : () => setState(() => _useExtension = false),
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text('Manual', style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[400],
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSourceList(),
      ],
    );
  }

  Widget _buildSourceList() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: _verifiedSources.map((source) {
          final isSelected = _selectedSource?.extensionId == source.extensionId;
          final isWorking = source.status == SourceStatus.ok;
          final isChecking = source.status == SourceStatus.checking;

          return InkWell(
            onTap: (isWorking && !_isDownloadingFromExtension)
                ? () => setState(() => _selectedSource = source)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: source == _verifiedSources.last
                      ? BorderSide.none
                      : BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
              ),
              child: Row(
                children: [
                  // Status Icon
                  if (isChecking)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: const Color(0xFF4F6BF6),
                      ),
                    )
                  else
                    Icon(
                      isWorking ? Icons.check_circle : Icons.error_outline,
                      size: 20,
                      color: isWorking ? Colors.green : Colors.redAccent,
                    ),
                  const SizedBox(width: 12),
                  // Name and detail
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          source.name,
                          style: TextStyle(
                            color: isWorking ? Colors.white : Colors.white70,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        if (source.message != null)
                          Text(
                            source.message!,
                            style: TextStyle(
                              color: isWorking
                                  ? Colors.white54
                                  : Colors.redAccent.withOpacity(0.7),
                              fontSize: 11,
                            ),
                          ),
                        // Source track info (for verification)
                        if (isWorking && source.sourceTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                // Small cover thumbnail
                                if (source.sourceCoverUrl != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: Image.network(
                                        source.sourceCoverUrl!,
                                        width: 32,
                                        height: 32,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Container(
                                          width: 32,
                                          height: 32,
                                          color: Colors.grey[800],
                                          child: const Icon(
                                            Icons.music_note,
                                            color: Colors.grey,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        source.sourceTitle!,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (source.sourceArtist != null)
                                        Text(
                                          source.sourceArtist!,
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 10,
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
                        // Technical details
                        if (isWorking &&
                            (source.format != null || source.bitDepth != null))
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                if (source.codec != null ||
                                    source.format != null)
                                  _buildMetaBadge(
                                    source.codec?.toUpperCase() ??
                                        source.format
                                            ?.replaceAll('audio/', '')
                                            .toUpperCase() ??
                                        'FLAC',
                                  ),
                                if (source.bitDepth != null) ...[
                                  const SizedBox(width: 6),
                                  _buildMetaBadge('${source.bitDepth}bit'),
                                ],
                                if (source.sampleRate != null) ...[
                                  const SizedBox(width: 6),
                                  _buildMetaBadge(
                                    '${(source.sampleRate! / 1000).toStringAsFixed(1)}kHz',
                                  ),
                                ],
                                if (source.quality != null) ...[
                                  const SizedBox(width: 6),
                                  _buildMetaBadge(
                                    source.quality!,
                                    isHighlight: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Latency
                  if (source.latencyMs != null)
                    Text(
                      '${source.latencyMs}ms',
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 11,
                      ),
                    ),
                  const SizedBox(width: 12),
                  // Radio button for selection
                  if (isWorking)
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: isSelected
                          ? const Color(0xFF4F6BF6)
                          : Colors.white38,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildMetaBadge(String text, {bool isHighlight = false}) {
    final highlightColor = const Color(0xFF00E676); // Bright green
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isHighlight
            ? highlightColor.withOpacity(0.15)
            : Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isHighlight
              ? highlightColor.withOpacity(0.5)
              : Colors.white.withOpacity(0.15),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isHighlight ? highlightColor : Colors.white70,
          fontSize: 9,
          fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w500,
          letterSpacing: 0.3,
        ),
      ),
    );
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
    // In extension mode with track selected but no file yet
    final canAutoDownload =
        _selectedTrack != null &&
        _selectedSource != null &&
        _useExtension &&
        _pickedFile == null &&
        !_isUploading &&
        !_isDownloadingFromExtension;

    // Manual mode with file selected
    final canUpload =
        _selectedTrack != null && _pickedFile != null && !_isUploading;

    final isProcessing = _isUploading || _isDownloadingFromExtension;

    // Extension auto-download mode
    if (canAutoDownload) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _downloadWithExtension,
          icon: const Icon(Icons.download, size: 20),
          label: const Text(
            'Download & Upload',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4F6BF6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            elevation: 0,
          ),
        ),
      );
    }

    // Processing state
    if (isProcessing) {
      final isDownloading = _isDownloadingFromExtension;
      final progress = isDownloading ? _downloadProgress : _uploadProgress;
      final percent = (progress * 100).toInt();

      String progressText;
      if (isDownloading) {
        if (_totalDownloadBytes > 0) {
          final downloadedMB = (_downloadedBytes / 1024 / 1024).toStringAsFixed(
            1,
          );
          final totalMB = (_totalDownloadBytes / 1024 / 1024).toStringAsFixed(
            1,
          );
          progressText =
              'Downloading... $percent% ($downloadedMB / $totalMB MB)';
        } else {
          progressText = 'Downloading...';
        }
      } else {
        progressText = 'Uploading... $percent%';
      }

      return SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                backgroundColor: Colors.grey[800],
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDownloading
                      ? const Color(0xFF4F6BF6)
                      : const Color(0xFF4F6BF6),
                ),
                minHeight: 52,
              ),
            ),
            // Text overlay
            Transform.translate(
              offset: const Offset(0, -36),
              child: Text(
                progressText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Manual upload mode
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
        child: const Text(
          'Upload Song',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
