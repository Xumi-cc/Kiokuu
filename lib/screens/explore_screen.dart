// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/music_provider.dart';
import '../services/api_service.dart';
import '../utils/snackbar_utils.dart';
import 'artist_profile_screen.dart';
import 'playlist_screen.dart';

class ExploreScreen extends StatefulWidget {
  final bool isEmbedded;
  final void Function(String playlistId)? onAlbumSelected;
  final void Function(String artistId, String artistName, String? artistImage)?
  onArtistSelected;

  const ExploreScreen({
    super.key,
    this.isEmbedded = false,
    this.onAlbumSelected,
    this.onArtistSelected,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounceTimer;
  bool _isLoading = true;

  // 0=All, 1=Songs, 2=Artists, 3=Albums
  int _selectedFilter = 0;

  // Data
  List<Map<String, dynamic>> _songs = [];
  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _albums = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _api.getUserSongs(limit: 50),
        _api.getUserArtists(limit: 50),
        _api.getUserAlbums(limit: 50),
      ]);

      if (mounted) {
        setState(() {
          _songs = List<Map<String, dynamic>>.from(results[0]['songs'] ?? []);

          _artists = List<Map<String, dynamic>>.from(
            results[1]['artists'] ?? [],
          );

          _albums = List<Map<String, dynamic>>.from(results[2]['albums'] ?? []);

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading explore data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().isEmpty) {
        _loadInitialData();
      } else {
        _performSearch(query.trim());
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _api.searchUserSongs(query, limit: 50),
        _api.searchUserArtists(query, limit: 50),
        _api.searchUserAlbums(query, limit: 50),
      ]);

      if (mounted) {
        setState(() {
          _songs = List<Map<String, dynamic>>.from(results[0]['songs'] ?? []);

          _artists = List<Map<String, dynamic>>.from(
            results[1]['artists'] ?? [],
          );

          _albums = List<Map<String, dynamic>>.from(results[2]['albums'] ?? []);

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _playSong(int index) {
    if (_songs.isEmpty) return;
    final provider = Provider.of<MusicProvider>(context, listen: false);

    // Map songs to models
    final playlist = _songs.map((data) => _mapToSong(data)).toList();

    provider.setPlaylist(playlist, initialIndex: index, play: true);
  }

  Song _mapToSong(Map<String, dynamic> data) {
    final streamUrl = data['stream_url'] ?? '';
    return Song(
      id: data['id'],
      title: data['title'] ?? 'Unknown Title',
      artist: data['artist_name'] ?? 'Unknown Artist',
      album: data['album_name'] ?? 'Unknown Album',
      duration: Duration(seconds: _parseDuration(data['duration'])),
      source: 'upload',
      filePath: streamUrl, // MusicProvider uses filePath to stream
      streamUrl: streamUrl,
      coverUrl: data['cover_url'],
      artworkPath: data['cover_url'], // For album art display
    );
  }

  int _parseDuration(dynamic d) {
    if (d is int) return d;
    if (d is String) return int.tryParse(d) ?? 0;
    return 0;
  }

  void _openArtist(Map<String, dynamic> artist) {
    final artistId = artist['id']?.toString() ?? '';
    final artistName = artist['name'] ?? 'Unknown Artist';
    final artistImage = artist['image_url'];

    // On mobile, always use Navigator.push (callbacks only work on desktop)
    final isLargeScreen = MediaQuery.of(context).size.width >= 800;

    // Use callback if provided AND on large screen (desktop embedded mode)
    if (widget.onArtistSelected != null && isLargeScreen) {
      widget.onArtistSelected!(artistId, artistName, artistImage);
      return;
    }

    // Otherwise navigate to ArtistProfileScreen (mobile mode or no callback)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistProfileScreen(
          artistId: artistId,
          artistName: artistName,
          artistImage: artistImage,
        ),
      ),
    );
  }

  void _openAlbum(Map<String, dynamic> album) {
    final playlistId = album['playlist_id']?.toString() ?? '';

    if (playlistId.isEmpty) {
      // Album hasn't been migrated to playlist yet - show message
      AppSnackbar.show(
        context,
        message:
            'Album not available. Please restart the server to migrate albums.',
        icon: Icons.info,
      );
      return;
    }

    // On mobile, always use Navigator.push (callbacks only work on desktop)
    final isLargeScreen = MediaQuery.of(context).size.width >= 800;

    // Use callback if provided AND on large screen (desktop embedded mode)
    if (widget.onAlbumSelected != null && isLargeScreen) {
      widget.onAlbumSelected!(playlistId);
      return;
    }

    // Otherwise navigate to PlaylistDetailScreen (mobile mode or no callback)
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 800;

    Widget content = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          _searchFocusNode.unfocus();
        }
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // 1. Header & Search (Scrolls away)
          SliverToBoxAdapter(child: _buildSearchHeader(isMobile)),

          // 2. Filters (Pinned/Sticky)
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyHeaderDelegate(
              height: 60.0,
              child: _buildFilterHeader(),
            ),
          ),

          // 3. Content
          if (_isLoading)
            _buildLoadingSlivers(isMobile)
          else if (_songs.isEmpty && _artists.isEmpty && _albums.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())
          else
            ..._buildContentSlivers(isMobile),

          // Bottom Padding
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );

    if (widget.isEmbedded) {
      // If embedded, usage typically handles scaffolding
      // We wrap in Material to ensure proper ink effects
      return Material(color: Colors.black, child: content);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: content),
    );
  }

  Widget _buildSearchHeader(bool isMobile) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 32,
        24,
        isMobile ? 16 : 32,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Explore',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.search,
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) _performSearch(val.trim());
            },
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search your library...',
              hintStyle: TextStyle(color: Colors.grey[400]),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () {
                        setState(() {
                          _searchController.clear();
                        });
                        _searchFocusNode.unfocus();
                        _loadInitialData();
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    final filters = ['All', 'Songs', 'Artists', 'Albums'];

    return Container(
      color: Colors.black, // Opaque background
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: filters.asMap().entries.map((entry) {
                final index = entry.key;
                final label = entry.value;
                final isSelected = _selectedFilter == index;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedFilter = index);
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Subtle divider
          Container(height: 1, color: Colors.white.withOpacity(0.05)),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildLoadingSlivers(bool isMobile) {
    // Just a simple consistent loader for simplicity and performance
    return const SliverToBoxAdapter(
      child: SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }

  List<Widget> _buildContentSlivers(bool isMobile) {
    final padding = EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32);

    // Filter: SONGS
    if (_selectedFilter == 1) {
      if (_songs.isEmpty) return [_buildNoResultsSliver("No songs found")];
      return [
        SliverPadding(
          padding: padding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SongTile(
                song: _songs[index],
                index: index,
                onTap: () => _playSong(index),
              ),
              childCount: _songs.length,
            ),
          ),
        ),
      ];
    }

    // Filter: ARTISTS
    if (_selectedFilter == 2) {
      if (_artists.isEmpty) return [_buildNoResultsSliver("No artists found")];
      return [
        SliverPadding(
          padding: padding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isMobile ? 2 : 5,
              childAspectRatio: 0.8,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _GridCard(
                item: _artists[index],
                type: 'artist',
                onTap: () => _openArtist(_artists[index]),
              ),
              childCount: _artists.length,
            ),
          ),
        ),
      ];
    }

    // Filter: ALBUMS
    if (_selectedFilter == 3) {
      if (_albums.isEmpty) return [_buildNoResultsSliver("No albums found")];
      return [
        SliverPadding(
          padding: padding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isMobile ? 2 : 5,
              childAspectRatio: 0.8,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _GridCard(
                item: _albums[index],
                type: 'album',
                onTap: () => _openAlbum(_albums[index]),
              ),
              childCount: _albums.length,
            ),
          ),
        ),
      ];
    }

    // Filter: ALL
    return _buildAllContent(isMobile, padding);
  }

  List<Widget> _buildAllContent(bool isMobile, EdgeInsets padding) {
    final List<Widget> slivers = [];

    // 1. Songs Section
    if (_songs.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: padding.copyWith(top: 24, bottom: 16),
            child: _SectionHeader(
              title: 'Songs',
              action: 'View All',
              onTap: () => setState(() => _selectedFilter = 1),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: padding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SongTile(
                song: _songs[index],
                index: index,
                onTap: () => _playSong(index),
              ),
              childCount: _songs.length > 5 ? 5 : _songs.length,
            ),
          ),
        ),
      );
    }

    // 2. Artists Section
    if (_artists.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: padding.copyWith(top: 32, bottom: 16),
            child: _SectionHeader(
              title: 'Artists',
              action: 'View All',
              onTap: () => setState(() => _selectedFilter = 2),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 220,
            child: ListView.separated(
              padding: padding,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _artists.length > 10 ? 10 : _artists.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) => SizedBox(
                width: 160,
                child: _GridCard(
                  item: _artists[index],
                  type: 'artist',
                  onTap: () => _openArtist(_artists[index]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 3. Albums Section
    if (_albums.isNotEmpty) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: padding.copyWith(top: 32, bottom: 16),
            child: _SectionHeader(
              title: 'Albums',
              action: 'View All',
              onTap: () => setState(() => _selectedFilter = 3),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: SizedBox(
            height: 220,
            child: ListView.separated(
              padding: padding,
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _albums.length > 10 ? 10 : _albums.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) => SizedBox(
                width: 160,
                child: _GridCard(
                  item: _albums[index],
                  type: 'album',
                  onTap: () => _openAlbum(_albums[index]),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  Widget _buildNoResultsSliver(String message) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Your library is empty',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          Text(
            'Upload songs to see them here',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Helper Components
// ----------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onTap;

  const _SectionHeader({required this.title, this.action, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Text(
              action!,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  _StickyHeaderDelegate({required this.child, required this.height});
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) => true;
}

class _SongTile extends StatefulWidget {
  final Map<String, dynamic> song;
  final int index;
  final VoidCallback onTap;

  const _SongTile({
    Key? key,
    required this.song,
    required this.index,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_SongTile> createState() => _SongTileState();
}

class _SongTileState extends State<_SongTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.song['title'] ?? 'Unknown';
    final artist = widget.song['artist_name'] ?? 'Unknown Artist';
    final coverUrl = widget.song['cover_url'];
    final duration = _formatDuration(widget.song['duration']);
    final isMobile = MediaQuery.of(context).size.width < 800;

    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final isPlaying = provider.currentSong?.id == widget.song['id'];

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent, // Handled by container
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              decoration: BoxDecoration(
                color: _isHovering
                    ? Colors.white.withOpacity(0.08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Index or Play Button
                  SizedBox(
                    width: 40,
                    child: Center(
                      child: (isPlaying || (_isHovering && !isMobile))
                          ? Icon(
                              isPlaying && provider.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 20,
                            )
                          : Text(
                              (widget.index + 1).toString(),
                              style: const TextStyle(color: Colors.grey),
                            ),
                    ),
                  ),

                  // Cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey[900],
                      child: coverUrl != null && coverUrl.isNotEmpty
                          ? Image.network(
                              coverUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note,
                                color: Colors.grey,
                              ),
                            )
                          : const Icon(Icons.music_note, color: Colors.grey),
                    ),
                  ),

                  const SizedBox(width: 16),

                  // Title & Artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isPlaying
                                ? Colors.greenAccent
                                : Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Desktop: Album
                  if (!isMobile) ...[
                    Expanded(
                      child: Text(
                        widget.song['album_name'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],

                  // Duration
                  Text(
                    duration,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),

                  const SizedBox(width: 16),

                  // Menu
                  if (_isHovering || isMobile)
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onPressed: () {
                        AppSnackbar.show(
                          context,
                          message: 'Added to queue',
                          icon: Icons.queue_music,
                        );
                      },
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDuration(dynamic d) {
    // Backend returns duration in seconds (duration_ms / 1000)
    int s = 0;
    if (d is int) {
      s = d;
    } else if (d is String) {
      s = int.tryParse(d) ?? 0;
    }
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }
}

class _GridCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final String type; // 'artist' or 'album'
  final VoidCallback onTap;

  const _GridCard({
    Key? key,
    required this.item,
    required this.type,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final isArtist = widget.type == 'artist';
    final name = widget.item['name'] ?? 'Unknown';
    final subText = isArtist
        ? 'Artist'
        : (widget.item['artist_name'] ?? 'Unknown Artist');
    // Important: Use correct keys for image
    final imageUrl = isArtist
        ? widget.item['image_url']
        : widget.item['cover_url'];

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _isHovering
                ? Colors.white.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: isArtist
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      transform: _isHovering
                          ? (Matrix4.identity()..scale(1.05))
                          : Matrix4.identity(),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(isArtist ? 100 : 4),
                        child: Container(
                          color: Colors.grey[900],
                          child: imageUrl != null && imageUrl.isNotEmpty
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    isArtist ? Icons.person : Icons.album,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                )
                              : Icon(
                                  isArtist ? Icons.person : Icons.album,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isArtist ? TextAlign.center : TextAlign.start,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isArtist ? TextAlign.center : TextAlign.start,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
