import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:palette_generator/palette_generator.dart';
import '../config/app_config.dart';
import '../services/api_service.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../providers/music_provider.dart';
import '../widgets/playlist_cover_mosaic.dart';
import 'package:provider/provider.dart';

import '../widgets/bottom_player_bar.dart';
import 'player_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/upload_song_sheet.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../services/offline_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'artist_profile_screen.dart';
import '../services/analytics_service.dart';
import '../widgets/skeleton_loader.dart';

/// Full-screen playlist library that shows all user playlists
class PlaylistLibraryScreen extends StatefulWidget {
  final bool isEmbedded; // When true, skip Scaffold (for mobile nav embedding)
  final void Function(String playlistId)? onPlaylistSelected;

  const PlaylistLibraryScreen({
    super.key,
    this.isEmbedded = false,
    this.onPlaylistSelected,
  });

  @override
  State<PlaylistLibraryScreen> createState() => _PlaylistLibraryScreenState();
}

class _PlaylistLibraryScreenState extends State<PlaylistLibraryScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final _storage = const FlutterSecureStorage();

  List<Playlist> _playlists = [];
  List<Playlist> _likedPlaylists = [];
  List<Map<String, dynamic>> _followedArtists = []; // For Artists filter
  List<RecentAlbum> _recentAlbums = []; // For Albums filter
  bool _isLoading = true;
  String? _userPhotoUrl;

  // UI Selection State
  String _selectedFilter = 'All'; // 'All', 'Playlists', 'Artists', 'Albums'
  bool _isGridView = false;
  final String _sortMethod = 'Recents';

  late AnimationController _fabAnimController;
  late Animation<double> _fabScale;

  @override
  void initState() {
    super.initState();
    _fabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fabScale = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _fabAnimController, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _fabAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadData({String? filterType}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final type = filterType ?? _selectedFilter;

      // Special handling for Artists filter - use followed artists
      if (type == 'Artists') {
        final futures = await Future.wait([
          _api.getFollowedArtists(),
          _storage.read(key: 'photo_url'),
        ]);

        final artistsData = futures[0] as List<Map<String, dynamic>>;
        final photoUrl = futures[1] as String?;

        if (mounted) {
          setState(() {
            _followedArtists = artistsData;
            _recentAlbums = [];
            _playlists = [];
            _userPhotoUrl = photoUrl;
            _isLoading = false;
          });
        }
        return;
      }

      // Special handling for Albums filter - use recently played albums
      if (type == 'Albums') {
        final futures = await Future.wait([
          _analyticsService.getRecentlyPlayedAlbums(limit: 50),
          _storage.read(key: 'photo_url'),
        ]);

        final albumsResult = futures[0] as PaginatedAlbums;
        final photoUrl = futures[1] as String?;

        if (mounted) {
          setState(() {
            _recentAlbums = albumsResult.albums;
            _followedArtists = [];
            _playlists = [];
            _userPhotoUrl = photoUrl;
            _isLoading = false;
          });
        }
        return;
      }

      // Normal playlist loading for other filters
      final futures = await Future.wait([
        _api.getPlaylists(type: type == 'All' ? null : type),
        _api.getLikedPlaylists(),
        _storage.read(key: 'photo_url'),
      ]);

      final playlistsData = futures[0] as List<dynamic>;
      final likedPlaylistsData = futures[1] as List<dynamic>;
      final photoUrl = futures[2] as String?;

      if (mounted) {
        setState(() {
          _playlists = playlistsData.map((p) => Playlist.fromJson(p)).toList();
          _likedPlaylists = likedPlaylistsData
              .map((p) => Playlist.fromJson(p))
              .toList();
          _followedArtists = []; // Clear artists when showing playlists
          _recentAlbums = []; // Clear albums when showing playlists

          // Sort system playlists (Liked Songs) to top by default
          _playlists.sort((a, b) {
            if (a.isSystem && !b.isSystem) return -1;
            if (!a.isSystem && b.isSystem) return 1;
            return 0; // Keep API sort for others (usually recent)
          });

          _userPhotoUrl = photoUrl;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading library data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showCreatePlaylistDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    bool isPublic = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          return AnimatedPadding(
            padding: EdgeInsets.only(bottom: keyboardHeight),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
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

                    // Title
                    const Text(
                      'Create Playlist',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Name field
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Playlist Name',
                        labelStyle: TextStyle(color: Colors.grey[400]),
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
                        prefixIcon: const Icon(
                          Icons.music_note,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description field
                    TextField(
                      controller: descController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        labelText: 'Description (optional)',
                        labelStyle: TextStyle(color: Colors.grey[400]),
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
                        prefixIcon: const Icon(
                          Icons.description,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Public toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPublic ? Icons.public : Icons.lock,
                            color: isPublic ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isPublic
                                      ? 'Public Playlist'
                                      : 'Private Playlist',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  isPublic
                                      ? 'Anyone can see this playlist'
                                      : 'Only you can see this playlist',
                                  style: TextStyle(
                                    color: Colors.grey[500],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: isPublic,
                            onChanged: (val) =>
                                setModalState(() => isPublic = val),
                            activeThumbColor: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Create button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a playlist name'),
                              ),
                            );
                            return;
                          }

                          final result = await _api.createPlaylist(
                            nameController.text.trim(),
                            description: descController.text.trim(),
                            isPublic: isPublic,
                          );

                          if (mounted) {
                            Navigator.pop(context);
                            if (result != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Playlist created!'),
                                  backgroundColor: Colors.white,
                                ),
                              );
                              _loadData();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to create playlist'),
                                ),
                              );
                            }
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
                          'Create',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showUploadOptions(BuildContext context) {
    UploadSongSheet.show(context, onSuccess: _loadData);
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header: Profile, Title, Actions
          SliverToBoxAdapter(child: _buildHeader()),

          // Filter Chips (Pinned)
          SliverAppBar(
            backgroundColor: Colors.black,
            pinned: true,
            toolbarHeight: 56,
            flexibleSpace: _buildFilterChips(),
            automaticallyImplyLeading: false,
            elevation: 0,
          ),

          // Sort & View Layout
          SliverToBoxAdapter(child: _buildSortRow()),

          // Liked Playlists Section (if any)
          if (_likedPlaylists.isNotEmpty && !_isLoading) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Liked Playlists',
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 150,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _likedPlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = _likedPlaylists[index];
                    return GestureDetector(
                      onTap: () {
                        if (widget.onPlaylistSelected != null) {
                          widget.onPlaylistSelected!(playlist.id);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PlaylistDetailScreen(playlistId: playlist.id),
                            ),
                          );
                        }
                      },
                      child: Container(
                        width: 110,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Cover
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                color: Colors.grey[800],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                // Prefer coverImageUrls (full URLs from API)
                                child: PlaylistCoverMosaic(
                                  coverImages:
                                      playlist.coverImageUrls.isNotEmpty
                                      ? playlist.coverImageUrls
                                      : playlist.coverImages,
                                  size: 110,
                                  borderRadius: 8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Name
                            Text(
                              playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              '${playlist.songCount} songs',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],

          // Content
          _buildContent(),

          // Bottom padding for player bar
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );

    // Skip Scaffold when embedded in home screen (for mobile nav)
    if (widget.isEmbedded) {
      return Container(color: Colors.black, child: content);
    }

    return Scaffold(backgroundColor: Colors.black, body: content);
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          // User Avatar
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.purple.shade200,
              image: _userPhotoUrl != null
                  ? DecorationImage(
                      image: NetworkImage(_userPhotoUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: _userPhotoUrl == null
                ? const Center(
                    child: Text(
                      'K', // Initial
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          const Text(
            'Your Library',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white, size: 28),
            onPressed: () {
              // Navigate to search
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.cloud_upload_outlined,
              color: Colors.white,
              size: 26,
            ),
            onPressed: () => _showUploadOptions(context),
            tooltip: 'Upload Music',
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white, size: 28),
            onPressed: _showCreatePlaylistDialog,
            tooltip: 'Create Playlist',
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['Playlists', 'Albums', 'Artists'];
    return Row(
      children: [
        const SizedBox(width: 16),
        ...filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                final newFilter = isSelected ? 'All' : filter;
                setState(() => _selectedFilter = newFilter);
                _loadData(filterType: newFilter);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.grey[900],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Text(
                  filter,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSortRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(
        children: [
          Icon(Icons.import_export, color: Colors.grey[400], size: 20),
          const SizedBox(width: 4),
          Text(
            _sortMethod,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              _isGridView ? Icons.grid_view : Icons.list,
              color: Colors.grey[400],
              size: 20,
            ),
            onPressed: () => setState(() => _isGridView = !_isGridView),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      // Show skeleton matching current view mode (list by default)
      if (_isGridView) {
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, index) => const SkeletonPlaylistGridCard(),
              childCount: 6,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
          ),
        );
      } else {
        // List view skeleton (default)
        return SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // 56x56 cover skeleton
                  const SkeletonLoader(width: 56, height: 56, borderRadius: 4),
                  const SizedBox(width: 16),
                  // Title and subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonLoader(
                          width: 120 + (index * 20) % 60,
                          height: 14,
                          borderRadius: 4,
                        ),
                        const SizedBox(height: 6),
                        SkeletonLoader(
                          width: 80 + (index * 10) % 40,
                          height: 12,
                          borderRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            childCount: 8,
          ),
        );
      }
    }

    final items = _getFilteredItems();

    if (items.isEmpty && _followedArtists.isEmpty && _recentAlbums.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _selectedFilter == 'Artists'
                    ? 'No followed artists yet.\nFollow artists to see them here!'
                    : _selectedFilter == 'Albums'
                    ? 'No recently played albums yet.\nPlay some music to see them here!'
                    : 'No ${_selectedFilter.toLowerCase()} found',
                style: const TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              if (_selectedFilter != 'Artists' &&
                  _selectedFilter != 'Albums') ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _showCreatePlaylistDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text('Create Playlist'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Show followed artists when Artists filter is selected
    if (_selectedFilter == 'Artists' && _followedArtists.isNotEmpty) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildArtistListItem(_followedArtists[index]),
          childCount: _followedArtists.length,
        ),
      );
    }

    // Show recently played albums when Albums filter is selected
    if (_selectedFilter == 'Albums' && _recentAlbums.isNotEmpty) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAlbumListItem(_recentAlbums[index]),
          childCount: _recentAlbums.length,
        ),
      );
    }

    if (_isGridView) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildGridItem(items[index]),
            childCount: items.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
        ),
      );
    } else {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildListItem(items[index]),
          childCount: items.length,
        ),
      );
    }
  }

  List<Playlist> _getFilteredItems() {
    // Filtering is now done server-side
    return _playlists;
  }

  Widget _buildListItem(Playlist playlist) {
    if (playlist.isSystem) {
      // Only Liked Songs gets the special icon treatment
      // Most Played and Recently Played show cover mosaics
      if (playlist.name == 'Liked Songs') {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Center(
              child: Icon(Icons.favorite, color: Colors.white, size: 24),
            ),
          ),
          title: const Text(
            'Liked Songs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text(
            'Playlist • ${playlist.songCount} songs',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
          onTap: () => _openPlaylist(playlist),
        );
      }

      // Most Played and Recently Played use cover mosaic (like regular playlists)
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: SizedBox(
          width: 56,
          height: 56,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            // Prefer coverImageUrls (full URLs from API)
            child:
                (playlist.coverImageUrls.isNotEmpty ||
                    playlist.coverImages.isNotEmpty)
                ? PlaylistCoverMosaic(
                    coverImages: playlist.coverImageUrls.isNotEmpty
                        ? playlist.coverImageUrls
                        : playlist.coverImages,
                  )
                : Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: playlist.name == 'Most Played'
                            ? [const Color(0xFFFF6B35), const Color(0xFFFFA07A)]
                            : [
                                const Color(0xFF1DB954),
                                const Color(0xFF1ED760),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Icon(
                      playlist.name == 'Most Played'
                          ? Icons.bar_chart
                          : Icons.history,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
          ),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          'Playlist • ${playlist.songCount} songs',
          style: TextStyle(color: Colors.grey[400], fontSize: 13),
        ),
        onTap: () => _openPlaylist(playlist),
      );
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: SizedBox(
        width: 56,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          // Prefer coverImageUrls (full URLs from API)
          child:
              (playlist.coverImageUrls.isNotEmpty ||
                  playlist.coverImages.isNotEmpty)
              ? PlaylistCoverMosaic(
                  coverImages: playlist.coverImageUrls.isNotEmpty
                      ? playlist.coverImageUrls
                      : playlist.coverImages,
                )
              : Container(
                  color: Colors.grey[900],
                  child: const Icon(Icons.music_note, color: Colors.grey),
                ),
        ),
      ),
      title: Text(
        playlist.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        'Playlist • ${playlist.songCount} songs',
        style: TextStyle(color: Colors.grey[400], fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _openPlaylist(playlist),
      onLongPress: () => _showPlaylistOptions(playlist),
    );
  }

  Widget _buildArtistListItem(Map<String, dynamic> artist) {
    // Prefer image_url (full URL from API) when available
    final imageUrl = artist['image_url'] as String?;
    final imagePath = artist['image_path'] ?? '';
    final fullImageUrl =
        imageUrl ??
        (imagePath.isNotEmpty
            ? (imagePath.startsWith('http')
                  ? imagePath
                  : '${ApiService.baseUrl}/$imagePath')
            : null);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          shape: BoxShape.circle,
          image: fullImageUrl != null
              ? DecorationImage(
                  image: NetworkImage(fullImageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: fullImageUrl == null
            ? const Icon(Icons.person, color: Colors.grey, size: 28)
            : null,
      ),
      title: Text(
        artist['name'] ?? 'Unknown Artist',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${artist['follower_count'] ?? 0} followers',
        style: TextStyle(color: Colors.grey[400], fontSize: 13),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArtistProfileScreen(
              artistId: artist['artist_id'] ?? '',
              artistName: artist['name'] ?? '',
              artistImage: fullImageUrl,
              initialFollowers: artist['follower_count'],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlbumListItem(RecentAlbum album) {
    // Prefer imageUrl (full URL from API) when available
    final fullImageUrl =
        album.imageUrl ??
        (album.imagePath.isNotEmpty
            ? (album.imagePath.startsWith('http')
                  ? album.imagePath
                  : '${ApiService.baseUrl}/${album.imagePath}')
            : null);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
          image: fullImageUrl != null
              ? DecorationImage(
                  image: NetworkImage(fullImageUrl),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: fullImageUrl == null
            ? const Icon(Icons.album, color: Colors.grey, size: 28)
            : null,
      ),
      title: Text(
        album.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${album.artistName} • ${album.playCount} plays',
        style: TextStyle(color: Colors.grey[400], fontSize: 13),
      ),
      onTap: () {
        // Could navigate to album detail screen if available
        // For now, just a placeholder
      },
    );
  }

  Widget _buildGridItem(Playlist playlist) {
    if (playlist.isSystem) {
      // Only Liked Songs gets the special icon treatment
      if (playlist.name == 'Liked Songs') {
        return InkWell(
          onTap: () => _openPlaylist(playlist),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(Icons.favorite, color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Liked Songs',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                'Playlist • ${playlist.songCount} songs',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ],
          ),
        );
      }

      // Most Played and Recently Played use cover mosaic
      return InkWell(
        onTap: () => _openPlaylist(playlist),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                // Prefer coverImageUrls (full URLs from API)
                child:
                    (playlist.coverImageUrls.isNotEmpty ||
                        playlist.coverImages.isNotEmpty)
                    ? PlaylistCoverMosaic(
                        coverImages: playlist.coverImageUrls.isNotEmpty
                            ? playlist.coverImageUrls
                            : playlist.coverImages,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: playlist.name == 'Most Played'
                                ? [
                                    const Color(0xFFFF6B35),
                                    const Color(0xFFFFA07A),
                                  ]
                                : [
                                    const Color(0xFF1DB954),
                                    const Color(0xFF1ED760),
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            playlist.name == 'Most Played'
                                ? Icons.bar_chart
                                : Icons.history,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Playlist • ${playlist.songCount} songs',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _openPlaylist(playlist),
      onLongPress: () => _showPlaylistOptions(playlist),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              // Prefer coverImageUrls (full URLs from API)
              child:
                  (playlist.coverImageUrls.isNotEmpty ||
                      playlist.coverImages.isNotEmpty)
                  ? PlaylistCoverMosaic(
                      coverImages: playlist.coverImageUrls.isNotEmpty
                          ? playlist.coverImageUrls
                          : playlist.coverImages,
                    )
                  : Container(
                      color: Colors.grey[900],
                      child: const Icon(
                        Icons.music_note,
                        color: Colors.grey,
                        size: 40,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            playlist.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Playlist • ${playlist.songCount} songs',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  void _openPlaylist(Playlist playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
      ),
    ).then((_) => _loadData());
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.library_music,
              size: 64,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Your Library is empty',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first playlist or like some songs',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreatePlaylistDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Playlist'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptions(Playlist playlist) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF282828),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildOptionItem(
              icon: Icons.edit,
              title: 'Edit Playlist',
              onTap: () {
                Navigator.pop(context);
                _showEditPlaylistDialog(playlist);
              },
            ),
            _buildOptionItem(
              icon: Icons.share,
              title: 'Share',
              onTap: () => Navigator.pop(context),
            ),
            _buildOptionItem(
              icon: Icons.delete_outline,
              title: 'Delete Playlist',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _confirmDeletePlaylist(playlist);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white),
      title: Text(title, style: TextStyle(color: color ?? Colors.white)),
      onTap: onTap,
    );
  }

  void _showEditPlaylistDialog(Playlist playlist) {
    final nameController = TextEditingController(text: playlist.name);
    final descController = TextEditingController(text: playlist.description);
    bool isPublic = playlist.isPublic;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text(
                  'Edit Playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Playlist Name',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Description',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  value: isPublic,
                  onChanged: (v) => setModalState(() => isPublic = v),
                  title: const Text(
                    'Public',
                    style: TextStyle(color: Colors.white),
                  ),
                  activeThumbColor: Colors.white,
                  tileColor: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final success = await _api.updatePlaylist(
                        playlist.id,
                        name: nameController.text.trim(),
                        description: descController.text.trim(),
                        isPublic: isPublic,
                      );
                      if (mounted) {
                        Navigator.pop(context);
                        _loadData();
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
                      'Save Changes',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeletePlaylist(Playlist playlist) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Playlist?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"? This action cannot be undone.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await _api.deletePlaylist(playlist.id);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Playlist deleted')),
                );
                _loadData();
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// Playlist detail screen showing songs
class PlaylistDetailScreen extends StatefulWidget {
  final String playlistId;
  final bool isEmbedded; // When true, skip Scaffold/AppBar (for master-detail)

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.isEmbedded = false,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final ApiService _api = ApiService();
  final _storage = const FlutterSecureStorage();
  Playlist? _playlist;
  bool _isLoading = true;
  bool _isLiked = false;
  String _username = '';
  String? _photoUrl;
  bool _isDownloading = false;
  int _downloadedCount = 0;
  int _totalDownloads = 0;
  bool _isPlaylistOffline = false;
  DateTime? _downloadStartTime;
  List<Color> _ambientColors = []; // For AMOLED ambient background

  // Smooth download progress overlay
  OverlayEntry? _downloadOverlay;
  final ValueNotifier<_DownloadProgress> _downloadProgressNotifier =
      ValueNotifier(_DownloadProgress(0, 0, ''));

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadPlaylist();
  }

  @override
  void dispose() {
    _removeDownloadOverlay();
    _downloadProgressNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadUsername() async {
    final results = await Future.wait([
      _storage.read(key: 'username'),
      _storage.read(key: 'photo_url'),
    ]);
    if (mounted) {
      setState(() {
        _username = results[0] ?? '';
        _photoUrl = results[1];
      });
    }
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload when playlist ID changes (e.g., switching playlists in sidebar)
    if (oldWidget.playlistId != widget.playlistId) {
      _loadPlaylist();
    }
  }

  Future<void> _loadPlaylist() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _api.getPlaylist(widget.playlistId),
        _api.checkPlaylistLikeStatus(widget.playlistId),
      ]);

      final data = results[0] as Map<String, dynamic>?;
      final isLiked = results[1] as bool;

      if (data != null && mounted) {
        final playlist = Playlist.fromJson(data);

        setState(() {
          _playlist = playlist;
          _isLiked = isLiked;
          _isLoading = false;
        });

        // Cache playlist metadata for offline browsing (auto-cache on view)
        await _cachePlaylistForOffline(playlist);

        // Extract colors for ambient background
        _extractAmbientColors();
        // Check if playlist is available offline
        _checkOfflineStatus();
      } else if (mounted) {
        // API returned null - try offline fallback
        await _loadOfflinePlaylist();
      }
    } catch (e) {
      debugPrint('Error loading playlist from API: $e');
      // Try loading from offline storage
      await _loadOfflinePlaylist();
    }
  }

  /// Cache playlist metadata and song list for offline browsing
  Future<void> _cachePlaylistForOffline(Playlist playlist) async {
    try {
      final offlineService = OfflineStorageService();
      final prefs = await SharedPreferences.getInstance();

      // Cache playlist name
      await prefs.setString('playlist_name_${playlist.id}', playlist.name);

      // Cache song list (for showing songs even if not downloaded)
      if (playlist.songs != null && playlist.songs!.isNotEmpty) {
        await offlineService.cachePlaylistSongs(
          playlist.id,
          playlist.songs!
              .map(
                (s) => CachedPlaylistSong(
                  id: s.id,
                  title: s.title,
                  artist: s.artistName,
                  album: s.albumName,
                  coverPath: s.coverPath,
                  durationMs: s.durationMs,
                ),
              )
              .toList(),
        );
      }

      debugPrint(
        '📋 Auto-cached playlist "${playlist.name}" for offline browsing',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to cache playlist for offline: $e');
    }
  }

  /// Load playlist from offline storage when API is unavailable
  Future<void> _loadOfflinePlaylist() async {
    try {
      final offlineService = OfflineStorageService();
      final offlineSongs = await offlineService.getPlaylistSongs(
        widget.playlistId,
      );

      if (offlineSongs.isNotEmpty && mounted) {
        // Get cached playlist name
        final prefs = await SharedPreferences.getInstance();
        final playlistName =
            prefs.getString('playlist_name_${widget.playlistId}') ?? 'Playlist';

        // Get cached full playlist (includes unavailable songs)
        final cachedSongs = await offlineService.getCachedPlaylistSongs(
          widget.playlistId,
        );

        // Create playable songs map for quick lookup
        final availableIds = offlineSongs.map((s) => s.id).toSet();
        final availableSongMap = {for (final s in offlineSongs) s.id: s};

        List<PlaylistSong> playlistSongs;
        int availableCount = offlineSongs.length;
        int totalCount = offlineSongs.length;

        if (cachedSongs != null && cachedSongs.isNotEmpty) {
          // Use cached list - show all songs, mark unavailable ones
          totalCount = cachedSongs.length;
          playlistSongs = cachedSongs.map((cached) {
            final available = availableSongMap[cached.id];
            return PlaylistSong(
              id: cached.id,
              title: cached.title,
              artistName: cached.artist,
              albumName: cached.album,
              durationMs: cached.durationMs,
              coverPath: cached.coverPath,
              filePath: available?.localPath, // null if not available
              isOfflineAvailable: available != null,
            );
          }).toList();
        } else {
          // Fallback: only show available songs
          playlistSongs = offlineSongs
              .map(
                (s) => PlaylistSong(
                  id: s.id,
                  title: s.title,
                  artistName: s.artist,
                  albumName: s.album,
                  durationMs: s.durationMs,
                  coverPath: s.coverPath,
                  filePath: s.localPath,
                  isOfflineAvailable: true,
                ),
              )
              .toList();
        }

        final syntheticPlaylist = Playlist(
          id: widget.playlistId,
          name: '$playlistName (Offline)',
          description:
              'Downloaded for offline playback ($availableCount/$totalCount available)',
          songCount: totalCount,
          coverImages: offlineSongs
              .where((s) => s.coverPath != null)
              .take(4)
              .map((s) => s.coverPath!)
              .toList(),
          createdAt: offlineSongs.first.downloadedAt,
          songs: playlistSongs,
        );

        setState(() {
          _playlist = syntheticPlaylist;
          _isPlaylistOffline = true;
          _isLoading = false;
        });

        debugPrint(
          '📦 Loaded offline playlist: ${syntheticPlaylist.name} ($availableCount/$totalCount available)',
        );
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading offline playlist: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _extractAmbientColors() async {
    if (_playlist == null || _playlist!.coverImages.isEmpty) {
      // Use default ambient color
      if (mounted) {
        setState(() {
          _ambientColors = [const Color(0xFF400080)]; // Default purple
        });
      }
      return;
    }

    try {
      // Prefer coverImageUrls (full URLs from API)
      final imageUrl = _playlist!.coverImageUrls.isNotEmpty
          ? _playlist!.coverImageUrls.first
          : (_playlist!.coverImages.first.startsWith('http')
                ? _playlist!.coverImages.first
                : '${ApiService.baseUrl}/${_playlist!.coverImages.first}');
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        NetworkImage(imageUrl),
        maximumColorCount: 3,
      );

      final colors = <Color>[];
      if (paletteGenerator.dominantColor != null) {
        colors.add(paletteGenerator.dominantColor!.color);
      }
      if (paletteGenerator.vibrantColor != null) {
        colors.add(paletteGenerator.vibrantColor!.color);
      }
      if (paletteGenerator.mutedColor != null) {
        colors.add(paletteGenerator.mutedColor!.color);
      }

      if (mounted && colors.isNotEmpty) {
        setState(() {
          _ambientColors = colors;
        });
      }
    } catch (e) {
      debugPrint('Error extracting ambient colors: $e');
      if (mounted) {
        setState(() {
          _ambientColors = [const Color(0xFF400080)]; // Fallback
        });
      }
    }
  }

  Future<void> _checkOfflineStatus() async {
    if (_playlist?.songs == null || _playlist!.songs!.isEmpty) {
      if (mounted) setState(() => _isPlaylistOffline = false);
      return;
    }

    final offlineService = OfflineStorageService();
    bool allAvailable = true;

    for (final song in _playlist!.songs!) {
      final isAvailable = await offlineService.isAvailable(song.id);
      if (!isAvailable) {
        allAvailable = false;
        break;
      }
    }

    if (mounted) {
      setState(() => _isPlaylistOffline = allAvailable);
    }
  }

  Future<void> _toggleLike() async {
    final newLikedState = !_isLiked;
    setState(() => _isLiked = newLikedState);

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            ),
            SizedBox(width: 12),
            Text('Updating...', style: TextStyle(color: Colors.black)),
          ],
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 10),
      ),
    );

    final success = newLikedState
        ? await _api.likePlaylist(widget.playlistId)
        : await _api.unlikePlaylist(widget.playlistId);

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }

    if (!success && mounted) {
      // Revert on failure
      setState(() => _isLiked = !newLikedState);
      AppSnackbar.show(context, message: 'Failed to update', icon: Icons.error);
    } else if (mounted) {
      AppSnackbar.show(
        context,
        message: newLikedState
            ? 'Added to Liked Playlists'
            : 'Removed from Liked Playlists',
        icon: newLikedState ? Icons.favorite : Icons.favorite_border,
      );
    }
  }

  Future<void> _downloadPlaylist() async {
    if (_playlist?.songs == null || _playlist!.songs!.isEmpty) {
      AppSnackbar.show(
        context,
        message: 'No songs to download',
        icon: Icons.info,
      );
      return;
    }

    // Ensure songs directory exists
    final songsDir = await OfflineStorageService.getSongsDir();
    final dir = Directory(songsDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    setState(() {
      _isDownloading = true;
      _isPlaylistOffline = false; // Reset until download completes
      _downloadedCount = 0;
      _totalDownloads = _playlist!.songs!.length;
    });

    // Show persistent progress snackbar
    _downloadStartTime = DateTime.now();
    _showDownloadProgressSnackbar(0, _playlist!.songs!.length);

    int successCount = 0;
    final offlineService = OfflineStorageService();

    // Cache playlist name for offline mode display
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'playlist_name_${widget.playlistId}',
      _playlist!.name,
    );

    // Cache full playlist song list (for showing unavailable songs as greyed out)
    await offlineService.cachePlaylistSongs(
      widget.playlistId,
      _playlist!.songs!
          .map(
            (s) => CachedPlaylistSong(
              id: s.id,
              title: s.title,
              artist: s.artistName,
              album: s.albumName,
              coverPath: s.coverPath,
              durationMs: s.durationMs,
            ),
          )
          .toList(),
    );
    for (int i = 0; i < _playlist!.songs!.length; i++) {
      final song = _playlist!.songs![i];
      final songStartTime = DateTime.now();

      // Skip already downloaded songs (resumable downloads)
      if (await offlineService.isAvailable(song.id)) {
        successCount++;
        if (mounted) {
          setState(() => _downloadedCount++);
          final isLast = i + 1 == _playlist!.songs!.length;
          _showDownloadProgressSnackbar(
            i + 1,
            _playlist!.songs!.length,
            speed: isLast ? 'Complete!' : 'Skipped (already downloaded)',
          );
        }
        continue;
      }

      // Download to centralized songs directory (songs stored once, referenced by playlists)
      final songsDir = await OfflineStorageService.getSongsDir();

      final result = await _api.downloadSong(song.id, song.id, songsDir);
      if (result != null) {
        successCount++;
        // Save metadata and associate with this playlist
        await offlineService.addSong(
          OfflineSong(
            id: song.id,
            title: song.title,
            artist: song.artistName,
            album: song.albumName,
            localPath: result,
            coverPath: song.coverPath,
            durationMs: song.durationMs,
            downloadedAt: DateTime.now(),
            source: song.source, // Track source for HD upgrade detection
          ),
          widget.playlistId, // Associate with this playlist
        );
      }

      // Calculate speed and ETA
      final elapsed = DateTime.now().difference(_downloadStartTime!).inSeconds;
      final isLast = i + 1 == _playlist!.songs!.length;
      String speedText = 'Downloading...';

      if (isLast) {
        speedText = 'Complete!';
      } else if (elapsed > 0) {
        final songsPerMin = ((i + 1) / elapsed * 60).toStringAsFixed(1);
        final remaining = _playlist!.songs!.length - (i + 1);
        final etaSeconds = remaining > 0
            ? (elapsed / (i + 1) * remaining).toInt()
            : 0;
        final etaMin = etaSeconds ~/ 60;
        final etaSec = etaSeconds % 60;
        speedText = '$songsPerMin songs/min • ${etaMin}m ${etaSec}s remaining';
      }

      if (mounted) {
        setState(() => _downloadedCount++);
        _showDownloadProgressSnackbar(
          i + 1,
          _playlist!.songs!.length,
          speed: speedText,
        );
      }
    }

    if (mounted) {
      _removeDownloadOverlay();
      setState(() => _isDownloading = false);
      _checkOfflineStatus(); // Update offline indicator
      AppSnackbar.show(
        context,
        message:
            'Downloaded $successCount/${_playlist!.songs!.length} songs for offline',
        icon: successCount == _playlist!.songs!.length
            ? Icons.check
            : Icons.warning,
      );
    }
  }

  void _showDownloadProgressSnackbar(
    int current,
    int total, {
    String speed = '',
  }) {
    // Update the notifier - this triggers smooth rebuild without flicker
    _downloadProgressNotifier.value = _DownloadProgress(current, total, speed);

    // Create overlay only once when starting
    if (_downloadOverlay == null) {
      _showDownloadOverlay();
    }
  }

  void _showDownloadOverlay() {
    _downloadOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
        child: Material(
          color: Colors.transparent,
          child: ValueListenableBuilder<_DownloadProgress>(
            valueListenable: _downloadProgressNotifier,
            builder: (context, progress, _) {
              final percent = progress.total > 0
                  ? ((progress.current / progress.total) * 100).toInt()
                  : 0;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Animated progress ring with percentage
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: progress.total > 0
                                  ? progress.current / progress.total
                                  : 0,
                            ),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            builder: (context, value, _) =>
                                CircularProgressIndicator(
                                  strokeWidth: 3,
                                  backgroundColor: Colors.grey[300],
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Colors.black,
                                      ),
                                  value: value,
                                ),
                          ),
                        ),
                        TweenAnimationBuilder<int>(
                          tween: IntTween(begin: 0, end: percent),
                          duration: const Duration(milliseconds: 300),
                          builder: (context, value, _) => Text(
                            '$value%',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Downloading ${progress.current} of ${progress.total} songs',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              progress.speed.isNotEmpty
                                  ? progress.speed
                                  : 'Starting download...',
                              key: ValueKey(progress.speed),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_downloadOverlay!);
  }

  void _removeDownloadOverlay() {
    _downloadOverlay?.remove();
    _downloadOverlay = null;
  }

  void _playAll() {
    if (_playlist?.songs == null || _playlist!.songs!.isEmpty) return;

    final provider = Provider.of<MusicProvider>(context, listen: false);
    final songs = _playlist!.songs!
        .map(
          (ps) => Song(
            id: ps.id,
            title: ps.title,
            artist: ps.artistName,
            album: ps.albumName,
            filePath: ps.streamUrl ?? '',
            streamUrl: ps.streamUrl,
            coverUrl: ps.coverUrl,
            artworkPath:
                ps.coverUrl ??
                (ps.coverPath != null
                    ? '${ApiService.baseUrl}/${ps.coverPath}'
                    : null),
            duration: ps.duration,
            genres: ps.genres,
            tags: ps.tags,
            source: ps.source,
          ),
        )
        .toList();

    provider.setPlaylist(
      songs,
      initialIndex: 0,
      playlistId: widget.playlistId,
      playlistName: _playlist?.name,
    );
  }

  void _shufflePlay() {
    if (_playlist?.songs == null || _playlist!.songs!.isEmpty) return;

    final provider = Provider.of<MusicProvider>(context, listen: false);
    final songs = _playlist!.songs!
        .map(
          (ps) => Song(
            id: ps.id,
            title: ps.title,
            artist: ps.artistName,
            album: ps.albumName,
            filePath: ps.streamUrl ?? '',
            streamUrl: ps.streamUrl,
            coverUrl: ps.coverUrl,
            artworkPath:
                ps.coverUrl ??
                (ps.coverPath != null
                    ? '${ApiService.baseUrl}/${ps.coverPath}'
                    : null),
            duration: ps.duration,
            genres: ps.genres,
            tags: ps.tags,
            source: ps.source,
          ),
        )
        .toList();

    // Set playlist first, then enable shuffle mode
    provider.setPlaylist(
      songs,
      initialIndex: 0,
      playlistId: widget.playlistId,
      playlistName: _playlist?.name,
    );

    // Enable shuffle if not already on
    if (!provider.isShuffled) {
      provider.toggleShuffle();
    }
  }

  String _getTotalDuration(List<PlaylistSong> songs) {
    if (songs.isEmpty) return '0 Minutes';
    final totalSeconds = songs.fold<int>(
      0,
      (prev, song) => prev + song.durationMs ~/ 1000,
    );
    final minutes = totalSeconds ~/ 60;
    if (minutes >= 60) {
      final hrs = minutes ~/ 60;
      final mins = minutes % 60;
      return '${hrs}h ${mins}m';
    }
    return '$minutes Minutes';
  }

  void _showPlaylistOptions(Playlist playlist) {
    // Don't show edit options for system playlists
    if (playlist.isSystem) {
      return; // System playlists can't be edited
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF282828),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text(
                'Share Playlist',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Create a 7-day share link',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _showShareDialog(playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.white),
              title: const Text(
                'Manage Share Links',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'View clicks, revoke access',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _showManageSharesDialog(playlist);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.white),
              title: const Text(
                'Edit Playlist',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                // TODO: Navigate to edit
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showShareDialog(Playlist playlist) async {
    // Show loading indicator
    AppSnackbar.show(
      context,
      message: 'Generating share link...',
      icon: Icons.hourglass_empty,
    );

    // Create share link
    final result = await _api.createShareLink(playlist.id);
    if (result == null) {
      if (mounted) {
        AppSnackbar.show(
          context,
          message: 'Failed to create share link',
          icon: Icons.error_outline,
        );
      }
      return;
    }

    final shareToken = result['share_token'] as String;
    final expiresAt = DateTime.parse(result['expires_at'] as String);
    final shareUrl = AppConfig.getShareUrl(shareToken);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.share, color: Colors.white),
            const SizedBox(width: 12),
            const Text(
              'Share Link Created',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share "${playlist.name}" with others:',
              style: TextStyle(color: Colors.grey[300]),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      shareUrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: shareUrl));
                      Navigator.pop(context);
                      AppSnackbar.show(
                        context,
                        message: 'Link copied!',
                        icon: Icons.check,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Expires in ${_formatExpiryDate(expiresAt)}',
                  style: TextStyle(color: Colors.orange[300], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Anyone with this link can view your playlist in the KioKuu app.',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatExpiryDate(DateTime date) {
    final now = DateTime.now();
    final diff = date.difference(now);
    if (diff.inDays > 0) {
      return '${diff.inDays} days';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hours';
    } else {
      return 'Soon';
    }
  }

  void _showManageSharesDialog(Playlist playlist) async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Loading share links...',
              style: TextStyle(color: Colors.black),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 10),
      ),
    );

    final shares = await _api.getShareLinks(playlist.id);
    final stats = await _api.getShareStats(playlist.id);

    if (!mounted) return;

    // Dismiss loading snackbar
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF282828),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Share Links', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stats row
              if (stats != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        'Total Clicks',
                        stats['total_clicks']?.toString() ?? '0',
                        Icons.touch_app,
                      ),
                      _buildStatItem(
                        'Active Links',
                        stats['active_links']?.toString() ?? '0',
                        Icons.link,
                      ),
                      _buildStatItem(
                        'Likes',
                        stats['likes_count']?.toString() ?? '0',
                        Icons.favorite,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Shares list
              if (shares.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No share links yet',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: shares.length,
                    itemBuilder: (context, index) {
                      final share = shares[index];
                      final status = share['status'] as String? ?? 'active';
                      final clickCount = share['click_count'] as int? ?? 0;
                      final token = share['share_token'] as String? ?? '';

                      Color statusColor;
                      IconData statusIcon;
                      switch (status) {
                        case 'revoked':
                          statusColor = Colors.red;
                          statusIcon = Icons.block;
                          break;
                        case 'expired':
                          statusColor = Colors.orange;
                          statusIcon = Icons.timer_off;
                          break;
                        default:
                          statusColor = Colors.white;
                          statusIcon = Icons.check_circle;
                      }

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(statusIcon, color: statusColor),
                        title: Text(
                          token.length > 12
                              ? '${token.substring(0, 12)}...'
                              : token,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          '$clickCount clicks • $status',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 11,
                          ),
                        ),
                        trailing: status == 'active'
                            ? IconButton(
                                icon: const Icon(
                                  Icons.block,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () => _revokeShareLink(
                                  playlist.id,
                                  share['id'] as String,
                                  context,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showShareDialog(playlist);
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Link'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 10)),
      ],
    );
  }

  void _revokeShareLink(
    String playlistId,
    String shareId,
    BuildContext dialogContext,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        final reasonController = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Text(
            'Revoke Access',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This will immediately revoke access for anyone using this link.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  hintText: 'Reason (optional)',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                Navigator.pop(dialogContext);

                // Show loading indicator
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Revoking access...',
                          style: TextStyle(color: Colors.black),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.white,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    margin: const EdgeInsets.all(16),
                    duration: const Duration(seconds: 10),
                  ),
                );

                final success = await _api.revokeShareLink(
                  playlistId,
                  shareId,
                  reason: reasonController.text.isNotEmpty
                      ? reasonController.text
                      : null,
                );

                if (mounted) {
                  ScaffoldMessenger.of(this.context).hideCurrentSnackBar();
                  if (success) {
                    AppSnackbar.show(
                      this.context,
                      message: 'Share link revoked',
                      icon: Icons.check,
                    );
                  } else {
                    AppSnackbar.show(
                      this.context,
                      message: 'Failed to revoke link',
                      icon: Icons.error,
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Revoke'),
            ),
          ],
        );
      },
    );
  }

  /// Build skeleton loading state for playlist detail
  Widget _buildPlaylistDetailSkeleton() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    // Mobile skeleton - centered layout
    if (isMobile) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header skeleton
            const SizedBox(height: 40),
            // Playlist cover skeleton
            const SkeletonLoader(width: 180, height: 180, borderRadius: 12),
            const SizedBox(height: 24),
            // Title skeleton
            const SkeletonLoader(width: 200, height: 24, borderRadius: 4),
            const SizedBox(height: 8),
            // Subtitle skeleton
            const SkeletonLoader(width: 140, height: 14, borderRadius: 4),
            const SizedBox(height: 24),
            // Action buttons skeleton
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SkeletonLoader(width: 80, height: 36, borderRadius: 18),
                SizedBox(width: 16),
                SkeletonLoader(width: 48, height: 48, isCircle: true),
                SizedBox(width: 16),
                SkeletonLoader(width: 80, height: 36, borderRadius: 18),
              ],
            ),
            const SizedBox(height: 32),
            // Song list skeleton
            ...List.generate(
              6,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SkeletonSongItem(index: index),
              ),
            ),
          ],
        ),
      );
    }

    // Desktop skeleton - side-by-side layout matching actual desktop view
    final double coverSize = screenWidth > 1100 ? 200 : 150;
    final double horizontalPadding = screenWidth > 1100 ? 32 : 20;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section with gradient background
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top spacing (where nav row used to be)
                const SizedBox(height: 48),

                // Main Header Content - Row with cover and details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Cover Art skeleton
                    SkeletonLoader(
                      width: coverSize,
                      height: coverSize,
                      borderRadius: 12,
                    ),
                    SizedBox(width: screenWidth > 1000 ? 32 : 20),

                    // Playlist Details skeleton
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // "Playlist" label
                          const SkeletonLoader(
                            width: 80,
                            height: 14,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 8),
                          // Title skeleton
                          SkeletonLoader(
                            width: screenWidth > 1100 ? 350 : 250,
                            height: screenWidth > 1100 ? 48 : 32,
                            borderRadius: 4,
                          ),
                          const SizedBox(height: 16),
                          // Metadata row skeleton (username • year • duration)
                          Row(
                            children: const [
                              SkeletonLoader(
                                width: 100,
                                height: 14,
                                borderRadius: 4,
                              ),
                              SizedBox(width: 12),
                              SkeletonLoader(
                                width: 40,
                                height: 14,
                                borderRadius: 4,
                              ),
                              SizedBox(width: 12),
                              SkeletonLoader(
                                width: 60,
                                height: 14,
                                borderRadius: 4,
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // Action Buttons Row skeleton
                          Row(
                            children: const [
                              // Play button skeleton
                              SkeletonLoader(
                                width: 110,
                                height: 48,
                                borderRadius: 24,
                              ),
                              SizedBox(width: 24),
                              // Shuffle icon
                              SkeletonLoader(
                                width: 40,
                                height: 40,
                                isCircle: true,
                              ),
                              SizedBox(width: 16),
                              // Like icon
                              SkeletonLoader(
                                width: 40,
                                height: 40,
                                isCircle: true,
                              ),
                              SizedBox(width: 8),
                              // Download icon
                              SkeletonLoader(
                                width: 40,
                                height: 40,
                                isCircle: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Table header skeleton
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey[800]!, width: 1),
              ),
            ),
            child: Row(
              children: const [
                SizedBox(width: 40), // # column
                SkeletonLoader(width: 20, height: 12, borderRadius: 4),
                SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: SkeletonLoader(width: 40, height: 12, borderRadius: 4),
                ),
                Expanded(
                  flex: 2,
                  child: SkeletonLoader(width: 50, height: 12, borderRadius: 4),
                ),
                SkeletonLoader(width: 30, height: 12, borderRadius: 4),
                SizedBox(width: 40),
              ],
            ),
          ),

          // Song list skeleton (desktop style with row layout)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Column(
              children: List.generate(
                8,
                (index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      // Row number
                      SizedBox(
                        width: 40,
                        child: SkeletonLoader(
                          width: 16,
                          height: 14,
                          borderRadius: 4,
                        ),
                      ),
                      // Title column (with album art)
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            const SkeletonLoader(
                              width: 40,
                              height: 40,
                              borderRadius: 4,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonLoader(
                                  width: 120 + (index % 80).toDouble(),
                                  height: 14,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 4),
                                SkeletonLoader(
                                  width: 80 + (index % 40).toDouble(),
                                  height: 12,
                                  borderRadius: 4,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Artist column
                      Expanded(
                        flex: 2,
                        child: SkeletonLoader(
                          width: 100 + (index % 50).toDouble(),
                          height: 14,
                          borderRadius: 4,
                        ),
                      ),
                      // Duration
                      const SkeletonLoader(
                        width: 40,
                        height: 14,
                        borderRadius: 4,
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _playlist?.songs ?? [];
    final isMobile = MediaQuery.of(context).size.width < 800;

    // Desktop / Embedded Implementation
    if (!isMobile || widget.isEmbedded) {
      final content = _isLoading
          ? _buildPlaylistDetailSkeleton()
          : _playlist == null
          ? const Center(
              child: Text(
                'Playlist not found',
                style: TextStyle(color: Colors.white),
              ),
            )
          : CustomScrollView(
              slivers: [
                ..._buildDesktopSlivers(context, songs),
                const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
              ],
            );

      if (widget.isEmbedded) {
        return Container(color: Colors.black, child: content);
      }

      return Scaffold(
        key: const ValueKey('desktop_playlist_scaffold'),
        backgroundColor: Colors.black,
        body: Stack(children: [content, _buildBottomPlayerBar()]),
      );
    }

    // Mobile Implementation (Clean & Modern)
    if (_isLoading) {
      return Scaffold(
        key: const ValueKey('mobile_playlist_loading'),
        backgroundColor: Colors.black,
        body: SafeArea(child: _buildPlaylistDetailSkeleton()),
      );
    }

    if (_playlist == null) {
      return Scaffold(
        key: const ValueKey('mobile_playlist_not_found'),
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Playlist not found',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Go Back',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      key: const ValueKey('mobile_playlist_scaffold'),
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Base Background
          Container(color: Colors.black),

          // Ambient Background Effect
          if (_ambientColors.isNotEmpty) ...[
            // Primary color spot (top right)
            Positioned(
              top: -80,
              right: -100,
              width: 400,
              height: 350,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ambientColors[0].withOpacity(0.35),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],
          if (_ambientColors.length > 1) ...[
            // Secondary color spot (left)
            Positioned(
              top: 200,
              left: -80,
              width: 300,
              height: 300,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ambientColors[1].withOpacity(0.25),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],
          if (_ambientColors.length > 2) ...[
            // Third color spot (center/top)
            Positioned(
              top: -100,
              left: 50,
              right: 50,
              height: 300,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _ambientColors[2].withOpacity(0.2),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
          ],

          // Gradient overlay to fade to black
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 650,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),

          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Minimal App Bar
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: false,
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 20,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  // Only show options for non-system playlists
                  if (!_playlist!.isSystem)
                    IconButton(
                      icon: const Icon(
                        Icons.more_horiz,
                        size: 28,
                        color: Colors.white,
                      ),
                      onPressed: () => _showPlaylistOptions(_playlist!),
                    ),
                ],
              ),

              // Hero Content
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // Cover Art
                    Hero(
                      tag: 'playlist_cover_${widget.playlistId}',
                      child: Container(
                        width: 180,
                        height: 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          // Prefer coverImageUrls (full URLs from API)
                          child:
                              (_playlist!.coverImageUrls.isNotEmpty ||
                                  _playlist!.coverImages.isNotEmpty)
                              ? PlaylistCoverMosaic(
                                  coverImages:
                                      _playlist!.coverImageUrls.isNotEmpty
                                      ? _playlist!.coverImageUrls
                                      : _playlist!.coverImages,
                                  size: 180,
                                  borderRadius: 0,
                                )
                              : Container(
                                  color: const Color(0xFFFFF176),
                                  child: Center(
                                    child: Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.3),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Title & Meta
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _playlist!.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24, // Increased from 20
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Created by ${_username.isNotEmpty ? _username : 'User'}',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${_playlist!.createdAt.year} • ${_getTotalDuration(songs)}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),

                    const SizedBox(height: 20),

                    // Action Buttons Row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Shuffle
                          IconButton(
                            onPressed: _shufflePlay,
                            icon: const Icon(Icons.shuffle, size: 24),
                            color: Colors.grey[400],
                            splashRadius: 20,
                          ),

                          const SizedBox(width: 24),

                          // Play/Pause Button
                          Consumer<MusicProvider>(
                            builder: (context, provider, _) {
                              final isThisPlaylist =
                                  provider.currentPlaylistId ==
                                  widget.playlistId;
                              final isPlaying =
                                  isThisPlaylist && provider.isPlaying;

                              return SizedBox(
                                height: 48,
                                width: 140,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    if (isThisPlaylist) {
                                      provider.togglePlayPause();
                                    } else {
                                      _playAll();
                                    }
                                  },
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  label: Text(
                                    isPlaying ? 'Pause' : 'Play',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E2329),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: EdgeInsets.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 24),

                          // Heart/Like
                          IconButton(
                            onPressed: _toggleLike,
                            icon: Icon(
                              _isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 24,
                            ),
                            color: _isLiked
                                ? const Color(0xFF1DB954)
                                : Colors.grey[400],
                            splashRadius: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Secondary Actions Row (Download, Share, More)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Download
                          IconButton(
                            onPressed: _isDownloading
                                ? null
                                : _downloadPlaylist,
                            icon: _isDownloading
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.grey[400],
                                      value: _totalDownloads > 0
                                          ? _downloadedCount / _totalDownloads
                                          : null,
                                    ),
                                  )
                                : Icon(
                                    _isPlaylistOffline
                                        ? Icons.download_done
                                        : Icons.download_for_offline_outlined,
                                    size: 24,
                                  ),
                            color: _isPlaylistOffline
                                ? const Color(0xFF1DB954)
                                : Colors.grey[400],
                            splashRadius: 20,
                            tooltip: _isDownloading
                                ? 'Downloading $_downloadedCount/$_totalDownloads'
                                : _isPlaylistOffline
                                ? 'Available offline'
                                : 'Download for offline',
                          ),

                          const SizedBox(width: 16),

                          // Share (only for non-system playlists)
                          if (!_playlist!.isSystem)
                            IconButton(
                              onPressed: () => _showShareDialog(_playlist!),
                              icon: const Icon(Icons.share_outlined, size: 22),
                              color: Colors.grey[400],
                              splashRadius: 20,
                              tooltip: 'Share playlist',
                            ),

                          if (!_playlist!.isSystem) const SizedBox(width: 16),

                          // More Options (only for non-system playlists)
                          if (!_playlist!.isSystem)
                            IconButton(
                              onPressed: () => _showPlaylistOptions(_playlist!),
                              icon: const Icon(Icons.more_horiz, size: 24),
                              color: Colors.grey[400],
                              splashRadius: 20,
                              tooltip: 'More options',
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // Song List
              if (songs.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else
                _buildSongList(songs, isMobile: true),

              const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
            ],
          ),

          _buildBottomPlayerBar(),
        ],
      ),
    );
  }

  Widget _buildBottomPlayerBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Consumer<MusicProvider>(
        builder: (context, provider, _) {
          if (provider.currentSong == null) return const SizedBox.shrink();
          return BottomPlayerBar(
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const PlayerScreen(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        final curvedAnimation = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOutCubic,
                        );
                        return FadeTransition(
                          opacity: curvedAnimation,
                          child: child,
                        );
                      },
                  transitionDuration: const Duration(milliseconds: 400),
                  reverseTransitionDuration: const Duration(milliseconds: 400),
                ),
              );
            },
          );
        },
      ),
    );
  }

  List<Widget> _buildDesktopSlivers(
    BuildContext context,
    List<PlaylistSong> songs,
  ) {
    // Determine the gradient color (subtle dark fill)
    final Color baseColor = _ambientColors.isNotEmpty
        ? _ambientColors.first
        : const Color(0xFF121212);

    // Responsive sizing based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize = screenWidth > 1400
        ? 56
        : screenWidth > 1100
        ? 40
        : 32;
    final double coverSize = screenWidth > 1100 ? 200 : 150;
    final double horizontalPadding = screenWidth > 1100 ? 32 : 20;

    return [
      SliverToBoxAdapter(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                baseColor.withOpacity(0.3), // Very subtle tint
                Colors.black,
              ],
              stops: const [0.0, 1.0],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top spacing (where nav row used to be)
                const SizedBox(height: 48),

                // Main Header Content
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Cover Art (Responsive size)
                    Container(
                      width: coverSize,
                      height: coverSize,
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 40,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        // Prefer coverImageUrls (full URLs from API)
                        child:
                            (_playlist!.coverImageUrls.isNotEmpty ||
                                _playlist!.coverImages.isNotEmpty)
                            ? PlaylistCoverMosaic(
                                coverImages:
                                    _playlist!.coverImageUrls.isNotEmpty
                                    ? _playlist!.coverImageUrls
                                    : _playlist!.coverImages,
                                size: coverSize,
                                borderRadius: 12,
                              )
                            : Container(
                                color: baseColor.withOpacity(0.5),
                                child: const Center(
                                  child: Icon(
                                    Icons.music_note,
                                    size: 80,
                                    color: Colors.white10,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    SizedBox(width: screenWidth > 1000 ? 32 : 20),

                    // Playlist Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _playlist!.isPublic
                                ? 'Public Playlist'
                                : 'Playlist',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _playlist!.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -1.5,
                              height: 1.1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),

                          // Metadata Row: Artist • Year • Duration
                          Row(
                            children: [
                              Text(
                                _username.isNotEmpty ? _username : 'User',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '•',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${_playlist!.createdAt.year}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                '•',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _getTotalFormattedDuration(songs),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),

                          // Action Buttons Row (1:1 Layout)
                          Row(
                            children: [
                              // Play/Pause Button (Dark Capsule)
                              Consumer<MusicProvider>(
                                builder: (context, provider, _) {
                                  final isThisPlaylist =
                                      provider.currentPlaylistId ==
                                      widget.playlistId;
                                  final isPlaying =
                                      isThisPlaylist && provider.isPlaying;

                                  return SizedBox(
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: () {
                                        if (isThisPlaylist) {
                                          provider.togglePlayPause();
                                        } else {
                                          _playAll();
                                        }
                                      },
                                      icon: Icon(
                                        isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      label: Text(
                                        isPlaying ? 'Pause' : 'Play',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF1E2329,
                                        ),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                          vertical: 0,
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 24),

                              // Shuffle
                              Consumer<MusicProvider>(
                                builder: (context, provider, _) {
                                  return IconButton(
                                    onPressed: _shufflePlay,
                                    icon: Icon(
                                      Icons.shuffle,
                                      color: provider.isShuffled
                                          ? const Color(0xFF1DB954)
                                          : Colors.grey[400],
                                      size: 24,
                                    ),
                                    tooltip: 'Shuffle',
                                  );
                                },
                              ),
                              const SizedBox(width: 16),

                              // Like
                              IconButton(
                                onPressed: _toggleLike,
                                icon: Icon(
                                  _isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: _isLiked
                                      ? const Color(0xFF1DB954)
                                      : Colors.grey[400],
                                  size: 24,
                                ),
                                tooltip: _isLiked ? 'Unlike' : 'Like',
                              ),
                              const SizedBox(width: 8),

                              // Download (with progress indicator)
                              IconButton(
                                onPressed: _isDownloading
                                    ? null
                                    : _downloadPlaylist,
                                icon: _isDownloading
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.grey[400],
                                          value: _totalDownloads > 0
                                              ? _downloadedCount /
                                                    _totalDownloads
                                              : null,
                                        ),
                                      )
                                    : Icon(
                                        _isPlaylistOffline
                                            ? Icons.download_done
                                            : Icons
                                                  .download_for_offline_outlined,
                                        color: _isPlaylistOffline
                                            ? const Color(0xFF1DB954)
                                            : Colors.grey[400],
                                        size: 24,
                                      ),
                                tooltip: _isDownloading
                                    ? 'Downloading $_downloadedCount/$_totalDownloads'
                                    : _isPlaylistOffline
                                    ? 'Downloaded for offline'
                                    : 'Download all songs',
                              ),

                              // Share (if not a system playlist)
                              if (!_playlist!.isSystem)
                                IconButton(
                                  onPressed: () => _showShareDialog(_playlist!),
                                  icon: Icon(
                                    Icons.share_outlined,
                                    color: Colors.grey[400],
                                    size: 22,
                                  ),
                                  tooltip: 'Share',
                                ),

                              // More Options (Edit, Delete, etc.)
                              if (!_playlist!.isSystem)
                                IconButton(
                                  onPressed: () =>
                                      _showPlaylistOptions(_playlist!),
                                  icon: Icon(
                                    Icons.more_horiz,
                                    color: Colors.grey[400],
                                    size: 24,
                                  ),
                                  tooltip: 'More Options',
                                ),

                              const Spacer(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),

      // Sticky Table Header
      SliverPersistentHeader(delegate: _TableHeadersDelegate(), pinned: true),

      // 3. Song List
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildDesktopSongRow(songs[index], index),
          childCount: songs.length,
        ),
      ),

      const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
    ];
  }

  Widget _buildDesktopSongRow(PlaylistSong song, int index) {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final isPlayingSong = provider.currentSong?.id == song.id;
    final isPlaying = isPlayingSong && provider.isPlaying;
    final isAvailable = song.isOfflineAvailable;

    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;

        return Opacity(
          opacity: isAvailable ? 1.0 : 0.4, // Grey out unavailable songs
          child: MouseRegion(
            onEnter: (_) => setState(() => isHovered = true),
            onExit: (_) => setState(() => isHovered = false),
            child: Container(
              decoration: BoxDecoration(
                color: isPlayingSong
                    ? Colors.white.withOpacity(0.05) // Subtler active state
                    : isHovered
                    ? Colors.white.withOpacity(0.04)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: InkWell(
                onTap: isAvailable ? () => _playSong(index) : null,
                onDoubleTap: isAvailable ? () => _playSong(index) : null,
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    // # Column (show download icon for unavailable)
                    SizedBox(
                      width: 40,
                      child: Center(
                        child: !isAvailable
                            ? const Icon(
                                Icons.cloud_off,
                                color: Colors.grey,
                                size: 16,
                              )
                            : isPlayingSong
                            ? (isPlaying
                                  ? _buildMiniEqualizer()
                                  : const Icon(
                                      Icons.pause,
                                      color: Color(0xFF1DB954),
                                      size: 16,
                                    ))
                            : isHovered
                            ? const Icon(
                                Icons.play_arrow,
                                color: Colors.white,
                                size: 16,
                              )
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Title Column (Expanded flex 6, NO COVER)
                    Expanded(
                      flex: 6,
                      child: Text(
                        song.title,
                        style: TextStyle(
                          color: isPlayingSong
                              ? const Color(0xFF1DB954)
                              : Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Artist Column (Expanded flex 4)
                    Expanded(
                      flex: 4,
                      child: Text(
                        song.artistName,
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Duration Column
                    SizedBox(
                      width: 60,
                      child: Text(
                        _formatDuration(song.durationMs ~/ 1000),
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 16),

                    // 3-dot Menu
                    SizedBox(
                      width: 36,
                      child: PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz,
                          color: Colors.grey[500],
                          size: 20,
                        ),
                        tooltip: 'More options',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: const Color(0xFF282828),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onSelected: (value) async {
                          switch (value) {
                            case 'queue':
                              AppSnackbar.show(
                                context,
                                message: 'Added "${song.title}" to queue',
                                icon: Icons.queue_music,
                              );
                              break;

                            case 'add_to_playlist':
                              showAddToPlaylistSheet(
                                context,
                                song.id,
                                song.title,
                                onPlaylistChanged: () => _loadPlaylist(),
                              );
                              break;

                            case 'remove':
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF282828),
                                  title: const Text(
                                    'Remove from Playlist',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    'Remove "${song.title}" from this playlist?',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text(
                                        'Remove',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true && mounted) {
                                final success = await _api
                                    .removeSongFromPlaylist(
                                      widget.playlistId,
                                      song.id,
                                    );
                                if (success && mounted) {
                                  AppSnackbar.show(
                                    context,
                                    message: 'Song removed',
                                    icon: Icons.check,
                                  );
                                  _loadPlaylist();
                                } else if (mounted) {
                                  AppSnackbar.show(
                                    context,
                                    message: 'Failed to remove song',
                                    icon: Icons.error,
                                  );
                                }
                              }
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'queue',
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.queue_music,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Add to Queue',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'add_to_playlist',
                            child: Row(
                              children: const [
                                Icon(
                                  Icons.playlist_add,
                                  color: Colors.grey,
                                  size: 20,
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Add to Playlist',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          if (!_playlist!.isSystem)
                            PopupMenuItem<String>(
                              value: 'remove',
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Remove from Playlist',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ), // Row
              ), // InkWell
            ), // Container
          ), // MouseRegion
        ); // Opacity
      },
    );
  }

  String _getTotalFormattedDuration(List<PlaylistSong> songs) {
    int totalMs = songs.fold(0, (sum, song) => sum + song.durationMs);
    int hours = totalMs ~/ 3600000;
    int minutes = (totalMs % 3600000) ~/ 60000;
    if (hours > 0) return 'about $hours hr $minutes min';
    return '$minutes min';
  }

  Widget _buildSongList(List<PlaylistSong> songs, {required bool isMobile}) {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildSongTile(songs[index], index),
        childCount: songs.length,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 64, color: Colors.grey[600]),
          const SizedBox(height: 16),
          const Text(
            'This playlist is empty',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0.5), Colors.grey[900]!],
        ),
      ),
      child: const Center(
        child: Icon(Icons.music_note, size: 80, color: Colors.white54),
      ),
    );
  }

  Widget _buildSongTile(PlaylistSong song, int index) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final isMobile = MediaQuery.of(context).size.width < 800;
        final isCurrentSong = provider.currentSong?.id == song.id;
        final isThisPlaylistPlaying =
            provider.currentPlaylistId == widget.playlistId;
        final isPlaying =
            isCurrentSong && isThisPlaylistPlaying && provider.isPlaying;
        final isCurrentlySelected = isCurrentSong && isThisPlaylistPlaying;
        final isAvailable = song.isOfflineAvailable;

        if (isMobile) {
          return Opacity(
            opacity: isAvailable ? 1.0 : 0.4,
            child: InkWell(
              onTap: isAvailable ? () => _playSong(index) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    // Rounded Square Cover (matching desktop)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: (song.coverUrl ?? song.coverPath) != null
                              ? Image.network(
                                  // Prefer coverUrl (full URL from API)
                                  song.coverUrl ??
                                      '${ApiService.baseUrl}/${song.coverPath}',
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
                        if (isCurrentlySelected)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: isPlaying
                                  ? _buildMiniEqualizer()
                                  : const Icon(
                                      Icons.pause,
                                      color: Color(0xFF1DB954),
                                      size: 24,
                                    ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),

                    // Title & Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            style: TextStyle(
                              color: isCurrentlySelected
                                  ? const Color(0xFF1DB954)
                                  : Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artistName,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Duration
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        _formatDuration(song.duration.inSeconds),
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    ),

                    // More options
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz, color: Colors.grey[600]),
                      color: const Color(0xFF282828),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      onSelected: (value) async {
                        switch (value) {
                          case 'queue':
                            if (mounted) {
                              // Capture provider before showing snackbar to avoid context issues
                              final provider = Provider.of<MusicProvider>(
                                context,
                                listen: false,
                              );
                              final songs = _playlist?.songs ?? [];
                              final playlistId = widget.playlistId;
                              final playlistName = _playlist?.name;

                              AppSnackbar.show(
                                context,
                                message: 'Added "${song.title}" to queue',
                                icon: Icons.queue_music,
                                actionLabel: 'Play Now',
                                onAction: () {
                                  // Play immediately using captured provider
                                  final songList = songs
                                      .map(
                                        (ps) => Song(
                                          id: ps.id,
                                          title: ps.title,
                                          artist: ps.artistName,
                                          album: ps.albumName,
                                          filePath: ps.streamUrl ?? '',
                                          streamUrl: ps.streamUrl,
                                          coverUrl: ps.coverUrl,
                                          artworkPath:
                                              ps.coverUrl ??
                                              (ps.coverPath != null
                                                  ? '${ApiService.baseUrl}/${ps.coverPath}'
                                                  : null),
                                          duration: ps.duration,
                                          source: ps.source,
                                        ),
                                      )
                                      .toList();
                                  provider.setPlaylist(
                                    songList,
                                    initialIndex: index,
                                    playlistId: playlistId,
                                    playlistName: playlistName,
                                  );
                                },
                              );
                            }
                            break;
                          case 'remove':
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: const Color(0xFF282828),
                                title: const Text(
                                  'Remove from Playlist',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: Text(
                                  'Remove "${song.title}" from this playlist?',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text(
                                      'Remove',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true && mounted) {
                              final success = await ApiService()
                                  .removeSongFromPlaylist(
                                    widget.playlistId,
                                    song.id,
                                  );
                              if (success) {
                                _loadPlaylist();
                                AppSnackbar.success(
                                  context,
                                  'Song removed from playlist',
                                );
                              }
                            }
                            break;
                          case 'artist':
                            AppSnackbar.show(
                              context,
                              message: 'Artist: ${song.artistName}',
                              icon: Icons.person,
                            );
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'queue',
                          child: Row(
                            children: [
                              Icon(
                                Icons.queue_music,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Add to Queue',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          child: Row(
                            children: [
                              Icon(
                                Icons.remove_circle_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Remove from Playlist',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'artist',
                          child: Row(
                            children: [
                              Icon(Icons.person, color: Colors.white, size: 20),
                              SizedBox(width: 12),
                              Text(
                                'View Artist',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Desktop Layout (Existing)
        return ListTile(
          onTap: () => _playSong(index),
          leading: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: (song.coverUrl ?? song.coverPath) != null
                    ? Image.network(
                        // Prefer coverUrl (full URL from API)
                        song.coverUrl ??
                            '${ApiService.baseUrl}/${song.coverPath}',
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
                        child: const Icon(Icons.music_note, color: Colors.grey),
                      ),
              ),
              // Equalizer overlay for currently playing song
              if (isCurrentlySelected)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: Colors.black.withOpacity(0.6),
                    child: Center(
                      child: isPlaying
                          ? _buildMiniEqualizer()
                          : const Icon(
                              Icons.pause,
                              color: Color(0xFF1DB954),
                              size: 24,
                            ),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            song.title,
            style: TextStyle(
              color: isCurrentlySelected
                  ? const Color(0xFF1DB954)
                  : Colors.white,
              fontWeight: isCurrentlySelected
                  ? FontWeight.bold
                  : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            song.artistName,
            style: TextStyle(
              color: isCurrentlySelected
                  ? Colors.white.withOpacity(0.8)
                  : Colors.grey[500],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatDuration(song.duration.inSeconds),
                style: TextStyle(color: Colors.grey[500], fontSize: 13),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                color: const Color(0xFF282828),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(Icons.remove_circle_outline, color: Colors.red),
                        SizedBox(width: 12),
                        Text(
                          'Remove from playlist',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
                onSelected: (value) async {
                  if (value == 'remove') {
                    final success = await _api.removeSongFromPlaylist(
                      widget.playlistId,
                      song.id,
                    );
                    if (success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Song removed')),
                      );
                      _loadPlaylist();
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _playSong(int index) {
    if (_playlist?.songs == null) return;

    final songs = _playlist!.songs!
        .map(
          (ps) => Song(
            id: ps.id,
            title: ps.title,
            artist: ps.artistName,
            album: ps.albumName,
            filePath: ps.streamUrl ?? '',
            streamUrl: ps.streamUrl,
            coverUrl: ps.coverUrl,
            artworkPath:
                ps.coverUrl ??
                (ps.coverPath != null
                    ? '${ApiService.baseUrl}/${ps.coverPath}'
                    : null),
            duration: ps.duration,
            genres: ps.genres,
            tags: ps.tags,
            source: ps.source,
          ),
        )
        .toList();

    Provider.of<MusicProvider>(context, listen: false).setPlaylist(
      songs,
      initialIndex: index,
      playlistId: widget.playlistId,
      playlistName: _playlist?.name,
    );
  }

  String _formatDuration(int durationSec) {
    final minutes = durationSec ~/ 60;
    final seconds = durationSec % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildMiniEqualizer() {
    return const _PlaylistMiniEqualizer(color: Color(0xFF1DB954), size: 16);
  }
}

/// Smooth sine-wave based equalizer animation
class _PlaylistMiniEqualizer extends StatefulWidget {
  final Color color;
  final double size;

  const _PlaylistMiniEqualizer({required this.color, required this.size});

  @override
  State<_PlaylistMiniEqualizer> createState() => _PlaylistMiniEqualizerState();
}

class _PlaylistMiniEqualizerState extends State<_PlaylistMiniEqualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (index) {
              // Generate oscillating heights with sine wave
              final t = _controller.value;
              final offset = index * 2.6;
              final val = sin((t * 2 * 3.14159 * (1.0 + index * 0.5)) + offset);
              final heightFactor = 0.3 + 0.6 * (0.5 + 0.5 * val);

              return Container(
                width: widget.size / 4.5,
                height: widget.size * heightFactor,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _TableHeadersDelegate extends SliverPersistentHeaderDelegate {
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.black, // Match the list background
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
      ),
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 40), // Match body padding
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const SizedBox(
            width: 40,
            child: Text(
              '#',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            flex: 6,
            child: Text(
              'TITLE',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
          ),
          const Expanded(
            flex: 4,
            child: Text(
              'ARTIST',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                letterSpacing: 1.0,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.access_time, size: 16, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 56), // spacer for options
        ],
      ),
    );
  }

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) =>
      false;
}

/// Helper class to hold download progress state for smooth overlay updates
class _DownloadProgress {
  final int current;
  final int total;
  final String speed;

  _DownloadProgress(this.current, this.total, this.speed);
}
