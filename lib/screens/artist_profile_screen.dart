import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../models/playlist.dart';
import '../providers/music_provider.dart';
import '../services/api_service.dart';
import '../widgets/song_list_item.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/skeleton_loader.dart';
import 'player_screen.dart';
import 'playlist_screen.dart';
import '../widgets/playlist_song_actions_menu.dart';

class ArtistProfileScreen extends StatefulWidget {
  final String artistId;
  final String artistName;
  final String? artistImage;
  final int? initialFollowers;
  final VoidCallback? onBackPressed; // Callback for embedded desktop navigation
  final void Function(String playlistId)?
  onAlbumSelected; // Callback for album navigation

  const ArtistProfileScreen({
    super.key,
    required this.artistName,
    this.artistId =
        '', // Optional if coming from somewhere without ID, but needed for API
    this.artistImage,
    this.initialFollowers,
    this.onBackPressed,
    this.onAlbumSelected,
  });

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  final _api = ApiService();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isFollowing = false;
  int _followers = 0;
  int _monthlyListeners = 0;
  List<Song> _popularSongs = [];
  List<Playlist> _albums = [];
  String? _headerImage;

  // For FLIP animation scroll tracking
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _followers = widget.initialFollowers ?? 0;
    _headerImage = widget.artistImage;
    _fetchArtistData();
    _checkFollowStatus();

    // Listen for scroll changes
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    final offset = _scrollController.offset;
    // Update on every scroll for smooth FLIP animation
    setState(() => _scrollOffset = offset);
  }

  @override
  void didUpdateWidget(ArtistProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistId != widget.artistId) {
      _followers = widget.initialFollowers ?? 0;
      _headerImage = widget.artistImage;
      _fetchArtistData();
      _checkFollowStatus();
    }
  }

  Future<void> _checkFollowStatus() async {
    if (widget.artistId.isEmpty) return;
    try {
      final isFollowing = await _api.checkArtistFollowStatus(widget.artistId);
      if (mounted) {
        setState(() => _isFollowing = isFollowing);
      }
    } catch (e) {
      debugPrint('Error checking follow status: $e');
    }
  }

  Future<void> _toggleFollow() async {
    if (widget.artistId.isEmpty) return;

    // Optimistic update
    setState(() => _isFollowing = !_isFollowing);

    try {
      final (success, newCount) = _isFollowing
          ? await _api.followArtist(widget.artistId)
          : await _api.unfollowArtist(widget.artistId);

      if (success && newCount != null && mounted) {
        setState(() => _followers = newCount);
      } else if (!success && mounted) {
        // Revert on failure
        setState(() => _isFollowing = !_isFollowing);
      }
    } catch (e) {
      if (mounted) setState(() => _isFollowing = !_isFollowing);
    }
  }

  Future<void> _fetchArtistData() async {
    if (widget.artistId.isEmpty) {
      // If we don't have an ID, we can't fetch detailed data easily yet
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Fetch Artist Details
      final artistData = await _api.getArtist(widget.artistId);
      if (artistData != null) {
        if (mounted) {
          setState(() {
            _followers = artistData['follower_count'] ?? _followers;
            _monthlyListeners = artistData['monthly_listeners'] ?? 0;
            // Use image_url (full URL with domain from DB) if available, else fallback to image_path
            if (artistData['image_url'] != null &&
                artistData['image_url'].toString().isNotEmpty) {
              _headerImage = artistData['image_url'];
            } else if (artistData['image_path'] != null &&
                artistData['image_path'].toString().isNotEmpty) {
              _headerImage = artistData['image_path'];
            }
          });
        }
      }

      // 2. Fetch Artist Songs
      final songsData = await _api.getArtistSongs(widget.artistId);
      final songs = songsData.map((data) {
        final songId = data['id'] ?? '';
        final artworkPath = data['artworkPath'] ?? '';
        final streamUrl = data['stream_url'];
        final coverUrl = data['cover_url'];
        return Song(
          id: songId,
          title: data['title'] ?? 'Unknown',
          artist: data['artist'] ?? 'Unknown Artist',
          album: data['album'],
          // stream_url from API is REQUIRED (no fallback)
          filePath: streamUrl ?? '',
          streamUrl: streamUrl,
          coverUrl: coverUrl,
          duration: Duration(milliseconds: data['duration'] ?? 0),
          artworkPath:
              coverUrl ??
              (artworkPath.isNotEmpty
                  ? (artworkPath.startsWith('http')
                        ? artworkPath
                        : '${ApiService.baseUrl}/$artworkPath')
                  : null),
          isOwned: data['isOwned'] ?? true,
          playCount: data['play_count'] ?? 0,
          source: data['source'] ?? 'user',
          uploadedBy: data['uploaded_by'],
        );
      }).toList();

      // 3. Fetch Artist Albums
      final albumsData = await _api.getArtistAlbums(widget.artistId);
      final albums = albumsData.map((data) {
        // Map album data to Playlist model
        // Use playlist_id as the id for navigation to PlaylistDetailScreen
        final playlistId = data['playlist_id']?.toString() ?? '';
        return Playlist(
          id: playlistId.isNotEmpty
              ? playlistId
              : data['id'], // Use playlist_id for navigation
          name: data['name'],
          coverImages: List<String>.from(data['cover_images'] ?? []),
          coverImageUrls: List<String>.from(data['cover_image_urls'] ?? []),
          createdAt:
              DateTime.tryParse(data['release_date'] ?? '') ?? DateTime.now(),
          songCount: data['play_count'] ?? 0, // Use play_count for display
          description: '',
          albumId: data['id'], // Store original album ID
        );
      }).toList();

      if (mounted) {
        setState(() {
          _popularSongs = songs;
          _albums = albums;

          // Fallback image if still needed
          if (_headerImage == null && _popularSongs.isNotEmpty) {
            _headerImage = _popularSongs.first.artworkPath;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching artist data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatMonthlyListeners(int count) {
    if (count == 0) return 'No listeners yet';
    if (count == 1) return '1 monthly listener';
    if (count < 1000) return '$count monthly listeners';
    if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K monthly listeners';
    }
    return '${(count / 1000000).toStringAsFixed(1)}M monthly listeners';
  }

  String _formatPlayCount(int count) {
    if (count == 0) return '0';
    if (count < 1000) return count.toString();
    if (count < 1000000) {
      final formatted = (count / 1000).toStringAsFixed(count < 10000 ? 1 : 0);
      return '${formatted}K';
    }
    if (count < 1000000000) {
      final formatted = (count / 1000000).toStringAsFixed(
        count < 10000000 ? 1 : 0,
      );
      return '${formatted}M';
    }
    final formatted = (count / 1000000000).toStringAsFixed(1);
    return '${formatted}B';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<MusicProvider>();
    // Use LayoutBuilder or MediaQuery. MediaQuery is fine here as it triggers rebuild on resize.
    final isDesktop = MediaQuery.of(context).size.width > 600;

    if (!isDesktop) {
      return _buildMobileView(context, provider);
    }

    return _buildDesktopView(context, provider);
  }

  Widget _buildDesktopView(BuildContext context, MusicProvider provider) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header Area
          SliverAppBar(
            expandedHeight: 400.0,
            floating: false,
            pinned: true,
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (widget.onBackPressed != null) {
                  widget.onBackPressed!();
                } else {
                  Navigator.of(context).pop();
                }
              },
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_horiz, color: Colors.white),
                onPressed: () {},
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.grey[900]!, Colors.black],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Artist Image
                            Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[800],
                                image: _headerImage != null
                                    ? DecorationImage(
                                        image: NetworkImage(
                                          _headerImage!.startsWith('http')
                                              ? _headerImage!
                                              : '${ApiService.baseUrl}/$_headerImage',
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 40,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: _headerImage == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 80,
                                      color: Colors.white24,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 32),

                            // Artist Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Verified Badge
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.verified,
                                        color: Colors.blueAccent,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Verified Artist',
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 14,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Name
                                  Text(
                                    widget.artistName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 64, // Large prominent text
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.0,
                                      height: 1.1,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 16),

                                  // Listeners
                                  Text(
                                    _formatMonthlyListeners(_monthlyListeners),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 32),

                                  // Buttons
                                  Row(
                                    children: [
                                      // Play Button
                                      Material(
                                        color: Colors.white,
                                        shape: const CircleBorder(),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: () {
                                            // Only play songs user has access to
                                            final ownedSongs = _popularSongs
                                                .where((s) => s.isOwned)
                                                .toList();
                                            if (ownedSongs.isNotEmpty) {
                                              provider.setPlaylist(ownedSongs);
                                            }
                                          },
                                          child: Container(
                                            width: 56,
                                            height: 56,
                                            alignment: Alignment.center,
                                            child: const Icon(
                                              Icons.play_arrow_rounded,
                                              color: Colors.black,
                                              size: 32,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 24),

                                      // Follow Button
                                      Material(
                                        color: Colors.transparent,
                                        shape: CircleBorder(
                                          side: BorderSide(
                                            color: Colors.white.withOpacity(
                                              0.3,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          onTap: _toggleFollow,
                                          child: Container(
                                            width: 56,
                                            height: 56,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              _isFollowing
                                                  ? Icons.favorite
                                                  : Icons.favorite_border,
                                              color: _isFollowing
                                                  ? Colors.white
                                                  : Colors.white,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                      ),

                                      const SizedBox(width: 24),

                                      IconButton(
                                        icon: const Icon(Icons.more_horiz),
                                        color: Colors.white.withOpacity(0.6),
                                        iconSize: 32,
                                        onPressed: () {},
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
                ),
              ),
            ),
          ),

          // Content
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Popular Section
                const Text(
                  'Popular',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),

                // Songs List
                if (_isLoading)
                  const SkeletonArtistSongs(itemCount: 8, showNumbers: true)
                else if (_popularSongs.isEmpty)
                  Text(
                    'No songs found',
                    style: TextStyle(color: Colors.white.withOpacity(0.5)),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _popularSongs.length,
                    itemBuilder: (context, index) {
                      final song = _popularSongs[index];
                      final isCurrent = provider.currentSong?.id == song.id;
                      final isOwned = song.isOwned;

                      return SongListItem(
                        song: song,
                        index: index,
                        isCurrent: isCurrent && isOwned,
                        isPlaying: isCurrent && provider.isPlaying && isOwned,
                        isDisabled: !isOwned,
                        subtitle: _formatPlayCount(
                          song.playCount,
                        ), // Show stream count instead of artist
                        onTap: () {
                          // Only play songs user owns - filter out unowned ones
                          final ownedSongs = _popularSongs
                              .where((s) => s.isOwned)
                              .toList();
                          final ownedIndex = ownedSongs.indexWhere(
                            (s) => s.id == song.id,
                          );
                          if (ownedIndex >= 0) {
                            provider.setPlaylist(
                              ownedSongs,
                              initialIndex: ownedIndex,
                            );
                          }
                        },
                        onLike: null,
                        onMenuTap: () async {
                          final currentUserId = await ApiService().userId;
                          if (context.mounted) {
                            PlaylistSongActionsMenu.show(
                              context,
                              songId: song.id,
                              songTitle: song.title,
                              uploadedBy: song.uploadedBy,
                              currentUserId: currentUserId,
                              onSongDeleted: () => _fetchArtistData(),
                              menuPosition:
                                  null, // Shows as modal on mobile, or context menu if we had position
                            );
                          }
                        },
                      );
                    },
                  ),

                const SizedBox(height: 48),

                // Discography Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Discography',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        'Show all',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ]),
            ),
          ),

          // Albums Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            sliver: _isLoading
                ? SliverToBoxAdapter(
                    child: SkeletonArtistAlbumsGrid(
                      itemCount: 5,
                      crossAxisCount: 5,
                    ),
                  )
                : _albums.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'No albums found',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    ),
                  )
                : SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 24,
                          mainAxisSpacing: 24,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final album = _albums[index];
                      return InkWell(
                        onTap: () {
                          // Navigate to album playlist
                          if (album.id.isNotEmpty) {
                            final isLargeScreen =
                                MediaQuery.of(context).size.width >= 800;
                            // Use callback on desktop, Navigator.push on mobile
                            if (widget.onAlbumSelected != null &&
                                isLargeScreen) {
                              widget.onAlbumSelected!(album.id);
                            } else {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PlaylistDetailScreen(
                                    playlistId: album.id,
                                  ),
                                ),
                              );
                            }
                          }
                        },

                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child:
                                      (album.coverImageUrls.isNotEmpty ||
                                          album.coverImages.isNotEmpty)
                                      ? Image.network(
                                          album.coverImageUrls.isNotEmpty
                                              ? album.coverImageUrls[0]
                                              : (album.coverImages[0]
                                                        .startsWith('http')
                                                    ? album.coverImages[0]
                                                    : '${ApiService.baseUrl}/${album.coverImages[0]}'),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                                color: Colors.grey[800],
                                                child: const Center(
                                                  child: Icon(
                                                    Icons.album,
                                                    color: Colors.grey,
                                                    size: 48,
                                                  ),
                                                ),
                                              ),
                                        )
                                      : const Center(
                                          child: Icon(
                                            Icons.album,
                                            color: Colors.grey,
                                            size: 48,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              album.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${album.createdAt.year} • Album',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    }, childCount: _albums.length),
                  ),
          ),

          const SliverPadding(padding: EdgeInsets.only(bottom: 50)),
        ],
      ),
    );
  }

  Widget _buildMobileView(BuildContext context, MusicProvider provider) {
    final screenWidth = MediaQuery.of(context).size.width;
    final expandedHeight = screenWidth; // Square header
    final collapsedHeight = kToolbarHeight + MediaQuery.of(context).padding.top;

    // FLIP Animation calculations
    // Calculate scroll progress (0 = fully expanded, 1 = fully collapsed)
    final scrollRange = expandedHeight - collapsedHeight;
    final scrollProgress = (_scrollOffset / scrollRange).clamp(0.0, 1.0);

    // Text properties - interpolate between large and small
    final largeFontSize = 48.0;
    final smallFontSize = 18.0;
    final currentFontSize = lerpDouble(
      largeFontSize,
      smallFontSize,
      scrollProgress,
    )!;

    // Position - from bottom-left of header to LEFT side of app bar (after back button)
    final statusBarHeight = MediaQuery.of(context).padding.top;

    // Large position: bottom of expanded header, left aligned
    final largeBottom = 20.0;
    final largeLeft = 16.0;
    final largeTop =
        expandedHeight - largeBottom - largeFontSize - _scrollOffset;

    // Small position: left side of app bar (after back button ~56px), vertically centered in toolbar
    final smallTop = statusBarHeight + (kToolbarHeight - smallFontSize) / 2;
    final smallLeft = 56.0; // After back button

    // Interpolate position - keep left aligned!
    final currentTop = lerpDouble(
      largeTop.clamp(smallTop, double.infinity),
      smallTop,
      scrollProgress,
    )!;
    final currentLeft = lerpDouble(largeLeft, smallLeft, scrollProgress)!;

    // Opacity for the positioned text (becomes 0 when fully in app bar since app bar title takes over)
    final textOpacity = scrollProgress < 0.95 ? 1.0 : 0.0;
    // App bar title opacity (appears when collapsed)
    final appBarTitleOpacity = scrollProgress > 0.9
        ? ((scrollProgress - 0.9) / 0.1).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // 1. Expanded Header with Image
              SliverAppBar(
                expandedHeight: expandedHeight,
                floating: false,
                pinned: true,
                backgroundColor: Colors.black,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                // App bar title (appears when fully collapsed) - LEFT aligned
                title: Opacity(
                  opacity: appBarTitleOpacity,
                  child: Text(
                    widget.artistName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                centerTitle: false, // LEFT aligned!
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (widget.onBackPressed != null) {
                          widget.onBackPressed!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: CircleAvatar(
                      backgroundColor: Colors.black54,
                      child: IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        onPressed: () {},
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_headerImage != null)
                        Image.network(
                          _headerImage!.startsWith('http')
                              ? _headerImage!
                              : '${ApiService.baseUrl}/$_headerImage',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(color: Colors.grey[900]),
                        )
                      else
                        Container(color: Colors.grey[900]),
                      // Gradient
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.0),
                              Colors.black.withOpacity(0.5),
                              Colors.black,
                            ],
                            stops: const [0.0, 0.5, 0.8, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Stats and Buttons
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _formatMonthlyListeners(_monthlyListeners),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Action Row
                      Row(
                        children: [
                          // Following / Follow
                          OutlinedButton(
                            onPressed: _toggleFollow,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.white.withOpacity(0.4),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              foregroundColor: Colors.white,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 0,
                              ),
                            ),
                            child: Text(_isFollowing ? 'Following' : 'Follow'),
                          ),

                          const SizedBox(width: 8),
                          // Three Dots
                          IconButton(
                            onPressed: () {},
                            icon: Icon(
                              Icons.more_vert,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),

                          const Spacer(),

                          // Shuffle
                          IconButton(
                            onPressed: () {
                              // Shuffle Play - only owned songs
                              final ownedSongs = _popularSongs
                                  .where((s) => s.isOwned)
                                  .toList();
                              if (ownedSongs.isNotEmpty) {
                                ownedSongs.shuffle();
                                provider.setPlaylist(ownedSongs);
                              }
                            },
                            icon: const Icon(
                              Icons.shuffle,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),

                          const SizedBox(width: 8),

                          // Play Button
                          GestureDetector(
                            onTap: () {
                              // Only play songs user has access to
                              final ownedSongs = _popularSongs
                                  .where((s) => s.isOwned)
                                  .toList();
                              if (ownedSongs.isNotEmpty) {
                                provider.setPlaylist(ownedSongs);
                              }
                            },
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Popular Songs Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: const Text(
                    'Popular',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // 4. Content
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 0),
                    child: SkeletonArtistSongs(itemCount: 5, showNumbers: true),
                  ),
                )
              else if (_popularSongs.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      "No songs found",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final song = _popularSongs[index];
                      final isCurrent = provider.currentSong?.id == song.id;
                      final isOwned = song.isOwned;

                      // Show max 5
                      return SongListItem(
                        song: song,
                        index: index, // 0-based, widget adds 1
                        isCurrent: isCurrent && isOwned,
                        isPlaying: isCurrent && provider.isPlaying && isOwned,
                        isDisabled: !isOwned,
                        subtitle: _formatPlayCount(
                          song.playCount,
                        ), // Show stream count instead of artist
                        onTap: () {
                          final ownedSongs = _popularSongs
                              .where((s) => s.isOwned)
                              .toList();
                          final ownedIndex = ownedSongs.indexWhere(
                            (s) => s.id == song.id,
                          );
                          if (ownedIndex >= 0) {
                            provider.setPlaylist(
                              ownedSongs,
                              initialIndex: ownedIndex,
                            );
                          }
                        },
                        onMenuTap: () async {
                          final currentUserId = await ApiService().userId;
                          if (context.mounted) {
                            PlaylistSongActionsMenu.show(
                              context,
                              songId: song.id,
                              songTitle: song.title,
                              uploadedBy: song.uploadedBy,
                              currentUserId: currentUserId,
                              onSongDeleted: () => _fetchArtistData(),
                              menuPosition: null,
                            );
                          }
                        },
                      );
                    },
                    childCount: _popularSongs.length > 5
                        ? 5
                        : _popularSongs.length,
                  ),
                ),

              // "See more" if needed... ignoring for simplicity unless requested.
              const SliverPadding(padding: EdgeInsets.symmetric(vertical: 12)),

              // 5. Popular Releases (Albums)
              if (_isLoading) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Popular releases',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: null,
                          child: Text(
                            'Show all',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SkeletonArtistAlbumsList(itemCount: 3),
                ),
              ] else if (_albums.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Popular releases',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            // Show all logic
                          },
                          child: Text(
                            'Show all',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final album = _albums[index];
                    return InkWell(
                      onTap: () {
                        // Navigate to album playlist
                        if (album.id.isNotEmpty) {
                          final isLargeScreen =
                              MediaQuery.of(context).size.width >= 800;
                          // Use callback on desktop, Navigator.push on mobile
                          if (widget.onAlbumSelected != null && isLargeScreen) {
                            widget.onAlbumSelected!(album.id);
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    PlaylistDetailScreen(playlistId: album.id),
                              ),
                            );
                          }
                        }
                      },

                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            // Album Cover
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                width: 64,
                                height: 64,
                                color: Colors.grey[800],
                                // Prefer coverImageUrls (full URLs from API)
                                child:
                                    (album.coverImageUrls.isNotEmpty ||
                                        album.coverImages.isNotEmpty)
                                    ? Image.network(
                                        album.coverImageUrls.isNotEmpty
                                            ? album.coverImageUrls[0]
                                            : (album.coverImages[0].startsWith(
                                                    'http',
                                                  )
                                                  ? album.coverImages[0]
                                                  : '${ApiService.baseUrl}/${album.coverImages[0]}'),
                                        fit: BoxFit.cover,
                                        width: 64,
                                        height: 64,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: Colors.grey[800],
                                          child: const Icon(
                                            Icons.album,
                                            color: Colors.white24,
                                          ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.album,
                                        color: Colors.white24,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    album.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${album.createdAt.year} • Album",
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.more_vert,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: _albums.length),
                ),
              ],

              const SliverPadding(padding: EdgeInsets.only(bottom: 140)),
            ],
          ),

          // FLIP Animated Artist Name Overlay - LEFT ALIGNED
          if (textOpacity > 0)
            Positioned(
              top: currentTop,
              left: currentLeft,
              right:
                  16, // Use full available width minus padding to allow Align to work
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.artistName,
                  textAlign: TextAlign.start,
                  style: TextStyle(
                    color: Colors.white.withOpacity(textOpacity),
                    fontSize: currentFontSize,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    letterSpacing: lerpDouble(-1.0, -0.5, scrollProgress),
                    shadows: [
                      Shadow(
                        color: Colors.black54.withOpacity(1.0 - scrollProgress),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // Player Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Consumer<MusicProvider>(
              builder: (context, provider, _) {
                if (provider.currentSong == null)
                  return const SizedBox.shrink();
                return BottomPlayerBar(
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, _, __) => const PlayerScreen(),
                        transitionsBuilder: (_, a, __, c) =>
                            FadeTransition(opacity: a, child: c),
                      ),
                    );
                  },
                  showFullControls: false,
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (index) {
          if (index == 0) {
            // Pop back to home
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
        backgroundColor: const Color(0xFF121212),
        selectedItemColor: Colors.grey, // Don't highlight strict home
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music),
            label: 'Library',
          ),
        ],
      ),
    );
  }
}
