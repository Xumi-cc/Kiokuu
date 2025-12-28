import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/llm_match_service.dart';

/// A sheet that shows an AI match result for user review
/// Allows users to Accept, Reject, or manually search for the correct song
class AIMatchReviewSheet extends StatefulWidget {
  final String fileName;
  final String? extractedTitle;
  final String? extractedArtist;
  final String? extractedAlbum;
  final LlmMatchResult? aiMatch;
  final Function(String spotifyId, String title, String artist, String? album)
  onAccept;
  final VoidCallback onReject;

  const AIMatchReviewSheet({
    super.key,
    required this.fileName,
    this.extractedTitle,
    this.extractedArtist,
    this.extractedAlbum,
    this.aiMatch,
    required this.onAccept,
    required this.onReject,
  });

  static Future<void> show(
    BuildContext context, {
    required String fileName,
    String? extractedTitle,
    String? extractedArtist,
    String? extractedAlbum,
    LlmMatchResult? aiMatch,
    required Function(
      String spotifyId,
      String title,
      String artist,
      String? album,
    )
    onAccept,
    required VoidCallback onReject,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true, // Allow tap outside to dismiss
      enableDrag: true, // Allow drag to dismiss
      builder: (context) => AIMatchReviewSheet(
        fileName: fileName,
        extractedTitle: extractedTitle,
        extractedArtist: extractedArtist,
        extractedAlbum: extractedAlbum,
        aiMatch: aiMatch,
        onAccept: onAccept,
        onReject: onReject,
      ),
    );
  }

  @override
  State<AIMatchReviewSheet> createState() => _AIMatchReviewSheetState();
}

class _AIMatchReviewSheetState extends State<AIMatchReviewSheet> {
  final _api = ApiService();
  final _searchController = TextEditingController();

  bool _isManualSearch = false;
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedManualTrack;
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
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
      _selectedManualTrack = track;
      _searchResults = [];
      _searchController.clear();
    });
  }

  void _acceptAIMatch() {
    if (widget.aiMatch != null) {
      widget.onAccept(
        widget.aiMatch!.spotifyId,
        widget.aiMatch!.title,
        widget.aiMatch!.artist,
        widget.aiMatch!.album,
      );
      Navigator.pop(context);
    }
  }

  void _acceptManualSelection() {
    if (_selectedManualTrack != null) {
      final track = _selectedManualTrack!;
      final artists = (track['artists'] as List?)?.join(', ') ?? 'Unknown';
      widget.onAccept(
        track['id'] ?? '',
        track['name'] ?? '',
        artists,
        track['album'] as String?,
      );
      Navigator.pop(context);
    }
  }

  void _reject() {
    widget.onReject();
    Navigator.pop(context);
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
            _buildHeader(),

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
                    // File info
                    _buildFileInfo(),

                    const SizedBox(height: 20),

                    // AI Match or Manual Search
                    if (_isManualSearch)
                      _buildManualSearch()
                    else if (widget.aiMatch != null)
                      _buildAIMatchResult()
                    else
                      _buildNoMatchFound(),

                    const SizedBox(height: 24),

                    // Action Buttons
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // Determine subtitle based on confidence
    String subtitle;
    if (widget.aiMatch == null) {
      subtitle = 'AI could not find a match - please search manually';
    } else {
      final confidence = (widget.aiMatch!.confidence * 100).toStringAsFixed(0);
      subtitle = 'AI is $confidence% confident - please verify';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF9C27B0), Color(0xFFE040FB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome,
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
                  'Review AI Match',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.audio_file, color: Colors.grey, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fileName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (widget.extractedTitle != null ||
                    widget.extractedArtist != null)
                  Text(
                    [
                      widget.extractedTitle,
                      widget.extractedArtist,
                    ].where((e) => e != null && e.isNotEmpty).join(' - '),
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    'No embedded metadata',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIMatchResult() {
    final match = widget.aiMatch!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome, color: Color(0xFFE040FB), size: 16),
            const SizedBox(width: 8),
            Text(
              'AI Suggestion',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            // Confidence badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.5)),
              ),
              child: Text(
                '${(match.confidence * 100).toStringAsFixed(0)}% confident',
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF9C27B0).withOpacity(0.15),
                const Color(0xFFE040FB).withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE040FB).withOpacity(0.3)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: match.albumArt.isNotEmpty
                    ? Image.network(
                        match.albumArt,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 72,
                          height: 72,
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.music_note,
                            color: Colors.grey,
                            size: 32,
                          ),
                        ),
                      )
                    : Container(
                        width: 72,
                        height: 72,
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
                      match.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      match.artist,
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (match.album.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        match.album,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Reasoning (if available)
        if (match.reasoning.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: Colors.amber[400],
                  size: 16,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    match.reasoning,
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoMatchFound() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.search_off, color: Colors.redAccent, size: 48),
          const SizedBox(height: 16),
          const Text(
            'No confident match found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI could not find a reliable match for this file. You can search manually below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildManualSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  _isManualSearch = false;
                  _selectedManualTrack = null;
                  _searchResults = [];
                  _searchController.clear();
                });
              },
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            Text(
              'Manual Search',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_selectedManualTrack != null)
          _buildSelectedManualTrack()
        else ...[
          // Search input
          TextField(
            controller: _searchController,
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
                borderSide: const BorderSide(
                  color: Color(0xFF1DB954),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),

          // Search results
          if (_searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final track = _searchResults[index];
                  final artists =
                      (track['artists'] as List?)?.join(', ') ?? 'Unknown';
                  final albumArt = track['album_art'] as String?;
                  final duration = _formatDuration(
                    track['duration_ms'] as int?,
                  );

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
                                child: const Icon(
                                  Icons.music_note,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              color: Colors.grey[800],
                              child: const Icon(
                                Icons.music_note,
                                color: Colors.grey,
                              ),
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
            ),
        ],
      ],
    );
  }

  Widget _buildSelectedManualTrack() {
    final track = _selectedManualTrack!;
    final artists = (track['artists'] as List?)?.join(', ') ?? 'Unknown';
    final albumArt = track['album_art'] as String?;
    final album = track['album'] as String? ?? '';

    return Container(
      width: double.infinity,
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
                _selectedManualTrack = null;
              });
            },
            icon: const Icon(Icons.close, color: Colors.grey),
            tooltip: 'Change selection',
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final bool canAccept = _isManualSearch
        ? _selectedManualTrack != null
        : widget.aiMatch != null;

    return Column(
      children: [
        // Accept button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: canAccept
                ? (_isManualSearch ? _acceptManualSelection : _acceptAIMatch)
                : null,
            icon: const Icon(Icons.check, size: 20),
            label: Text(
              _isManualSearch ? 'Use This Song' : 'Accept Match',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              disabledBackgroundColor: Colors.grey[800],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              elevation: 0,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Secondary action buttons
        Row(
          children: [
            // Manual search / Back button
            if (!_isManualSearch)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isManualSearch = true;
                    });
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Search Manually'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey[600]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),

            if (!_isManualSearch) const SizedBox(width: 12),

            // Reject button
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _reject,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Skip File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
