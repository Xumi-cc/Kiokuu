import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../widgets/upload_song_sheet.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/music_provider.dart';
import '../widgets/bottom_player_bar.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/playlist_cover_mosaic.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/ai_match_review_sheet.dart';
import '../widgets/desktop_queue_panel.dart';
import '../services/api_service.dart';
import '../services/friends_service.dart';
import '../services/analytics_service.dart';
import '../services/websocket_service.dart' as ws;
import '../services/import_watcher_service.dart';
import '../services/import_processor_service.dart';
import '../services/extension_manager_service.dart';
import '../services/offline_storage_service.dart';
import '../models/song.dart';
import 'player_screen.dart';
import 'auth_screen.dart';
import 'friends_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'artist_profile_screen.dart';
import 'explore_screen.dart';
import '../utils/snackbar_utils.dart';

// Helper function to create responsive transition for player screen
// Using fade transitions to enable proper FLIP/Hero animations
Route _createPlayerRoute() {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) =>
        const PlayerScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Use fade transition for all screens to allow Hero animations to fly
      // Hero handles its own position animation (FLIP technique)
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );

      return FadeTransition(opacity: curvedAnimation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 400),
    reverseTransitionDuration: const Duration(milliseconds: 400),
  );
}

class HomeScreen extends StatefulWidget {
  final bool isOfflineMode;

  const HomeScreen({super.key, this.isOfflineMode = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  final _storage = const FlutterSecureStorage();
  final _friendsService = FriendsService();
  final _wsService = ws.WebSocketService();
  final _analyticsService = AnalyticsService();

  // Scroll controllers for master-detail layout
  final _friendsScrollController = ScrollController();
  final _playlistScrollController = ScrollController();

  List<dynamic> _likedSongs = [];
  Map<String, dynamic>? _likedSongsData; // Full response with cover_images
  bool _isLoading = true;
  int _selectedNavIndex = 0; // 0: Home, 1: Search, 2: Library
  int _selectedIndex = 0; // For Hero Section carousel
  List<Color> _ambientColors = []; // Colors for ambient background
  bool _showAllPlaylists = false;
  String? _userPhotoUrl;
  String? _userName;

  // Analytics data
  List<SongStats> _topSongs = [];
  List<SongStats> _recentlyPlayed = [];
  List<PlaylistStats> _topPlaylists = [];
  bool _isAnalyticsLoading = true;

  // Shared friends activity state
  List<Friend> _friends = [];
  Map<String, ws.FriendActivity> _activities = {};
  bool _isFriendsLoading = true;
  List<StreamSubscription>? _wsSubscriptions;

  // Sidebar playlists state (for large screens)
  List<Map<String, dynamic>> _sidebarPlaylists = [];
  List<Map<String, dynamic>> _sidebarLikedPlaylists = []; // Liked playlists
  bool _isPlaylistsLoading = false;
  String? _selectedPlaylistId; // For master-detail: show playlist in main area
  String? _loadingPlaylistId; // Track which playlist is currently loading
  double _playlistScrollOffset = 0.0; // Track scroll for header title
  String? _selectedPlaylistName; // Playlist name for header

  // Artist profile state (for master-detail on large screens)
  String? _selectedArtistId;
  String? _selectedArtistName;
  String? _selectedArtistImage;

  // Recently played artists & albums (for sidebar)
  List<RecentArtist> _recentArtists = [];
  List<RecentAlbum> _recentAlbums = [];
  int _totalArtists = 0;
  int _totalAlbums = 0;
  bool _showAllArtists = false;
  bool _showAllAlbums = false;
  bool _isRecentArtistsAlbumsLoading = false;
  String _sidebarFilter = 'PLAYLIST'; // 'PLAYLIST', 'ALBUM', 'ARTIST'

  // Followed artists (for ARTIST sidebar filter)
  List<Map<String, dynamic>> _followedArtists = [];
  bool _isFollowedArtistsLoading = false;

  // Track previous screen size for responsive navigation
  bool? _wasLargeScreen;

  // Desktop queue panel visibility
  bool _showQueuePanel = false;

  // Import state
  List<ImportTask> _importTasks = [];
  bool _isImporting = false;
  bool _waitingForAI = false;

  // Offline mode state
  bool _isOfflineMode = false;
  Timer? _reconnectTimer; // Periodic check for server availability

  @override
  void initState() {
    super.initState();

    // Track offline mode
    _isOfflineMode = widget.isOfflineMode;

    // Initialize import services
    _initImportServices();

    // Set up API reconnection callback
    ApiService.onReconnected = () {
      if (mounted && _isOfflineMode) {
        _handleReconnection();
      }
    };

    // Defer data loading to avoid context access before build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Mark successful login for offline mode support
      _saveSuccessfulLoginTime();

      if (!_isOfflineMode) {
        _loadData();
        _loadUserProfile();
        _loadFriendsActivity();
        _loadAnalyticsData();
        _restorePlaybackState(); // Restore last session for seamless resume
      } else {
        // Offline mode: Load only cached/local data
        _loadOfflineModeData();
      }
    });
  }

  /// Save the timestamp when user successfully reaches home screen
  /// This enables offline login for subsequent sessions
  Future<void> _saveSuccessfulLoginTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'last_successful_login',
        DateTime.now().millisecondsSinceEpoch,
      );
      debugPrint('✅ Saved successful login timestamp for offline mode support');
    } catch (e) {
      debugPrint('Error saving login time: $e');
    }
  }

  /// Navigate to player screen and handle result (e.g., artist navigation)
  Future<void> _navigateToPlayer() async {
    final result = await Navigator.push(context, _createPlayerRoute());

    // Handle artist navigation from desktop player
    if (result != null && result is Map && result['action'] == 'openArtist') {
      final isLargeScreen = MediaQuery.of(context).size.width > 800;
      if (isLargeScreen) {
        setState(() {
          _selectedArtistId = result['artistId'];
          _selectedArtistName = result['artistName'];
          _selectedArtistImage = result['artistImage'];
          _selectedPlaylistId = null; // Clear playlist selection
        });
      } else {
        // On small screens, push the artist profile screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ArtistProfileScreen(
              artistId: result['artistId'],
              artistName: result['artistName'] ?? '',
              artistImage: result['artistImage'],
              initialFollowers: result['followerCount'],
            ),
          ),
        );
      }
    }
  }

  /// Load only locally available data for offline mode
  Future<void> _loadOfflineModeData() async {
    setState(() => _isLoading = true);

    try {
      // Load cached user profile
      final prefs = await SharedPreferences.getInstance();
      _userPhotoUrl = prefs.getString('user_photo_url');

      // Clean up any stale metadata first
      final offlineService = OfflineStorageService();
      await offlineService.cleanupStaleMetadata();

      // Get playlists with downloaded songs
      final downloadedPlaylistIds = await offlineService.getOfflinePlaylists();
      final downloadedSet = downloadedPlaylistIds.toSet();

      // Get all cached/browsed playlist IDs
      final cachedPlaylistIds = await offlineService.getAllCachedPlaylistIds();

      // Merge both - all playlists that were browsed or downloaded
      final allPlaylistIds = {...downloadedSet, ...cachedPlaylistIds};

      // Build sidebar playlist data
      final offlinePlaylists = <Map<String, dynamic>>[];
      int totalDownloadedSongs = 0;

      for (final playlistId in allPlaylistIds) {
        // Get downloaded songs for this playlist
        final downloadedSongs = await offlineService.getPlaylistSongs(
          playlistId,
        );

        // Get cached song list (all songs, for display)
        final cachedSongs = await offlineService.getCachedPlaylistSongs(
          playlistId,
        );

        // Get playlist name from cached prefs
        final playlistName =
            prefs.getString('playlist_name_$playlistId') ?? 'Playlist';

        // Determine song count and covers
        int songCount;
        List<String> coverImages;

        if (cachedSongs != null && cachedSongs.isNotEmpty) {
          // Use cached song count (total songs in playlist)
          songCount = cachedSongs.length;
          coverImages = cachedSongs
              .where((s) => s.coverPath != null)
              .take(4)
              .map((s) => s.coverPath!)
              .toList();
        } else if (downloadedSongs.isNotEmpty) {
          // Fallback to downloaded songs
          songCount = downloadedSongs.length;
          coverImages = downloadedSongs
              .where((s) => s.coverPath != null)
              .take(4)
              .map((s) => s.coverPath!)
              .toList();
        } else {
          // Skip empty playlists
          continue;
        }

        final hasDownloads = downloadedSongs.isNotEmpty;
        totalDownloadedSongs += downloadedSongs.length;

        offlinePlaylists.add({
          'id': playlistId,
          'name': hasDownloads
              ? '$playlistName (Offline)'
              : '$playlistName (Cached)',
          'song_count': songCount,
          'downloaded_count': downloadedSongs.length,
          'cover_images': coverImages,
          'is_offline': true,
          'has_downloads': hasDownloads,
        });
      }

      setState(() {
        _sidebarPlaylists = offlinePlaylists;
        _isLoading = false;
        _isFriendsLoading = false; // No friends data in offline mode
        _isAnalyticsLoading = false; // No analytics in offline mode
      });

      debugPrint(
        '📦 Loaded ${offlinePlaylists.length} offline/cached playlists with $totalDownloadedSongs downloaded songs',
      );

      // Show offline mode indicator
      if (mounted) {
        AppSnackbar.show(
          context,
          message:
              'Offline Mode - ${offlinePlaylists.length} playlists, $totalDownloadedSongs songs available',
          icon: Icons.wifi_off,
          duration: const Duration(seconds: 4),
        );
      }

      // Start periodic reconnect check
      _startReconnectTimer();
    } catch (e) {
      debugPrint('Error loading offline data: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Start periodic check for server availability
  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!_isOfflineMode) {
        _reconnectTimer?.cancel();
        return;
      }

      debugPrint('🔄 Checking server availability...');

      try {
        final isValid = await _api.validateSession();
        if (isValid && mounted) {
          debugPrint('✅ Server is back online! Reconnecting...');
          _reconnectTimer?.cancel();
          _handleReconnection();
        } else {
          debugPrint('⏳ Server still unavailable');
        }
      } catch (e) {
        debugPrint('⏳ Server check failed: $e');
      }
    });
  }

  /// Handle successful reconnection to server
  Future<void> _handleReconnection() async {
    // Exit offline mode
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offline_mode', false);

    if (mounted) {
      setState(() => _isOfflineMode = false);

      // Show reconnection notification
      AppSnackbar.show(
        context,
        message: 'Back online! Refreshing...',
        icon: Icons.wifi,
        duration: const Duration(seconds: 2),
      );

      // Reload all data (but don't restore playback - don't interrupt current song!)
      _loadData();
      _loadUserProfile();
      _loadFriendsActivity();
      _loadAnalyticsData();
      // Note: NOT calling _restorePlaybackState() to avoid interrupting current playback
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isLargeScreen = MediaQuery.of(context).size.width > 800;

    // If transitioning from large to small screen while viewing a playlist,
    // push the playlist detail as a full-screen route
    if (_wasLargeScreen == true &&
        !isLargeScreen &&
        _selectedPlaylistId != null) {
      final playlistId = _selectedPlaylistId!;
      // Clear the selection (it's now a pushed route)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _selectedPlaylistId = null;
          _selectedPlaylistName = null;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
          ),
        );
      });
    }

    _wasLargeScreen = isLargeScreen;
  }

  @override
  void dispose() {
    _friendsScrollController.dispose();
    _playlistScrollController.dispose();
    _wsService.disconnect();
    _wsSubscriptions?.forEach((s) => s.cancel());
    _reconnectTimer?.cancel();
    ImportWatcherService.instance.stopWatching();
    super.dispose();
  }

  void _initImportServices() {
    // Set up processor callbacks
    ImportProcessorService.instance.setCallbacks(
      onProgress: (tasks) {
        if (mounted) {
          setState(() {
            _importTasks = tasks;
            _isImporting = tasks.any(
              (t) =>
                  t.status == ImportStatus.extractingMetadata ||
                  t.status == ImportStatus.matchingWithAI ||
                  t.status == ImportStatus.uploading,
            );
            _waitingForAI = tasks.any(
              (t) => t.status == ImportStatus.waitingForAI,
            );
          });
        }
      },
      onComplete: (task, success) {
        if (mounted && success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Imported: ${task.title}')),
                ],
              ),
              backgroundColor: Colors.grey[900],
              behavior: SnackBarBehavior.floating,
            ),
          );
          // Refresh lists to show new song
          _loadData();
        }
      },
      onReviewNeeded: (task) {
        // Don't auto-show the review sheet - it's annoying
        // Just update state so we can show a badge on the import review page
        if (mounted) {
          setState(() {
            // Just trigger a rebuild for any UI that shows pending count
          });
        }
      },
    );

    // Start watching import folder
    ImportWatcherService.instance.startWatching(
      onFilesDetected: (files) {
        ImportProcessorService.instance.queueFiles(files);
      },
    );

    // Restore any tasks that were awaiting review on previous app session
    ImportProcessorService.instance.restorePersistedTasks();
  }

  void _showAIDownloadPrompt() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'AI Extension Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'To automatically identify and match your songs, you need to download the "Smart Import" AI extension.\n\nWithout it, files will remain in your import folder.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _downloadAIExtension();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
            ),
            child: const Text(
              'Download (85MB)',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Show the AI match review sheet for user to confirm or reject
  void _showAIMatchReview(ImportTask task) {
    AIMatchReviewSheet.show(
      context,
      fileName: task.fileName,
      extractedTitle: task.title,
      extractedArtist: task.artist,
      extractedAlbum: task.album,
      aiMatch: task.aiMatchResult,
      onAccept: (spotifyId, title, artist, album) {
        // User accepted the match, continue with upload
        ImportProcessorService.instance.acceptMatch(
          task,
          spotifyId: spotifyId,
          title: title,
          artist: artist,
          album: album,
        );
      },
      onReject: () {
        // User rejected the match
        ImportProcessorService.instance.rejectMatch(task);
      },
    );
  }

  Future<void> _downloadAIExtension() async {
    // Show downloading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Downloading AI Extension...'),
          ],
        ),
        duration: Duration(days: 1), // Indefinite until dismissed
      ),
    );

    // Start download
    final success = await ExtensionManagerService.instance.downloadExtension(
      'audio-fingerprint',
      onProgress: (progress) {
        // In a real UI we'd show a progress bar
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ AI Extension installed! Resuming imports...'),
            backgroundColor: Colors.green,
          ),
        );
        // Notify processor to resume
        ImportProcessorService.instance.onAIExtensionInstalled();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Download failed. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadFriendsActivity() async {
    setState(() => _isFriendsLoading = true);

    // Load friends list
    try {
      final friends = await _friendsService.getFriends();
      if (mounted) {
        setState(() {
          _friends = friends;
          _isFriendsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading friends: $e');
      if (mounted) setState(() => _isFriendsLoading = false);
    }

    // Setup WebSocket for real-time updates
    _setupWebSocket();

    // Load playlists for sidebar
    _loadSidebarPlaylists();
  }

  Future<void> _loadSidebarPlaylists({bool forceRefresh = false}) async {
    if (_isPlaylistsLoading && !forceRefresh) return;
    setState(() => _isPlaylistsLoading = true);

    try {
      final results = await Future.wait([
        _api.getPlaylists(),
        _api.getLikedPlaylists(),
      ]);

      if (mounted) {
        setState(() {
          _sidebarPlaylists = List<Map<String, dynamic>>.from(results[0]);
          _sidebarLikedPlaylists = List<Map<String, dynamic>>.from(results[1]);
          _isPlaylistsLoading = false;
        });

        // Cache playlist names for offline mode (background task)
        SharedPreferences.getInstance().then((prefs) {
          for (final pl in results[0]) {
            final id = pl['id'] as String?;
            final name = pl['name'] as String?;
            if (id != null && name != null) {
              prefs.setString('playlist_name_$id', name);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading playlists: $e');
      if (mounted) setState(() => _isPlaylistsLoading = false);
    }

    // Also load recently played artists & albums
    _loadRecentArtistsAndAlbums();
  }

  Future<void> _loadRecentArtistsAndAlbums({
    bool loadMore = false,
    bool resetShowFlags = false,
  }) async {
    // Prevent duplicate requests
    if (_isRecentArtistsAlbumsLoading) return;

    debugPrint(
      'Loading recently played artists and albums... (loadMore: $loadMore)',
    );
    setState(() => _isRecentArtistsAlbumsLoading = true);

    try {
      // Calculate offset based on current list length when loading more
      final artistOffset = loadMore ? _recentArtists.length : 0;
      final albumOffset = loadMore ? _recentAlbums.length : 0;

      // Always load 4 items at a time (like playlists)
      const limit = 4;

      // Load artists and albums separately
      final artistsResult = await _analyticsService.getRecentlyPlayedArtists(
        limit: limit,
        offset: artistOffset,
      );
      final albumsResult = await _analyticsService.getRecentlyPlayedAlbums(
        limit: limit,
        offset: albumOffset,
      );

      debugPrint(
        'Loaded ${artistsResult.artists.length} artists (total: ${artistsResult.total}) and ${albumsResult.albums.length} albums (total: ${albumsResult.total})',
      );

      if (mounted) {
        setState(() {
          if (loadMore) {
            // Append to existing list
            _recentArtists.addAll(artistsResult.artists);
            _recentAlbums.addAll(albumsResult.albums);
          } else {
            // Replace list
            _recentArtists = artistsResult.artists;
            _recentAlbums = albumsResult.albums;
            // Only reset show flags when explicitly requested (e.g., switching tabs)
            if (resetShowFlags) {
              _showAllArtists = false;
              _showAllAlbums = false;
            }
          }
          _totalArtists = artistsResult.total;
          _totalAlbums = albumsResult.total;
          _isRecentArtistsAlbumsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading recent artists/albums: $e');
      if (mounted) setState(() => _isRecentArtistsAlbumsLoading = false);
    }
  }

  Future<void> _loadFollowedArtists() async {
    if (_isFollowedArtistsLoading) return;

    setState(() => _isFollowedArtistsLoading = true);

    try {
      final artists = await _api.getFollowedArtists();
      if (mounted) {
        setState(() {
          _followedArtists = artists;
          _isFollowedArtistsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading followed artists: $e');
      if (mounted) setState(() => _isFollowedArtistsLoading = false);
    }
  }

  void _setupWebSocket() {
    if (!_wsService.isConnected) {
      _wsService.connect();
    }

    _wsSubscriptions = [
      _wsService.onActivityUpdate.listen((activity) {
        if (mounted) setState(() => _activities[activity.userId] = activity);
      }),
      _wsService.onFriendsActivity.listen((activities) {
        if (mounted) {
          setState(() {
            for (final a in activities) {
              _activities[a.userId] = a;
            }
          });
        }
      }),
      // Listen for HQ upgrade notifications
      _wsService.onHQUpgrade.listen((notification) {
        if (mounted) {
          AppSnackbar.hqUpgrade(context, songTitle: notification.songTitle);
        }
      }),
      // Listen for session invalidation (real-time kick)
      _wsService.onSessionInvalidated.listen((reason) {
        if (mounted) {
          _handleSessionKick(reason);
        }
      }),
      // When WebSocket reconnects after being offline, trigger full reconnection
      _wsService.onConnectionStateChange.listen((isConnected) {
        if (mounted && isConnected && _isOfflineMode) {
          _handleReconnection();
        }
      }),
    ];
  }

  /// Handle real-time session invalidation from server
  Future<void> _handleSessionKick(String reason) async {
    debugPrint('⚠️ Session kicked: $reason');

    // Clear stored credentials
    await _storage.delete(key: 'auth_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_successful_login');
    await prefs.setBool('offline_mode', false);

    if (mounted) {
      // Show dialog and redirect to login
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF282828),
          title: const Row(
            children: [
              Icon(Icons.logout, color: Colors.orange),
              SizedBox(width: 12),
              Text('Session Ended', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Text(reason, style: const TextStyle(color: Colors.grey)),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const AuthScreen()),
                  (route) => false,
                );
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // Shared helper to get display data for friends
  List<Map<String, dynamic>> get friendsDisplayData {
    return _friends.take(4).map((f) {
      final activity = _activities[f.id];
      final isLive = activity?.isPlaying ?? false;
      return {
        'id': f.id,
        'name': f.username,
        'song': isLive
            ? '${activity?.songTitle ?? ''} - ${activity?.artistName ?? ''}'
            : 'Offline',
        'image': f.photoUrl.isNotEmpty
            ? f.photoUrl
            : 'https://i.pravatar.cc/150?u=${f.id}',
        'albumCover': activity?.albumCover ?? f.photoUrl,
        'status': isLive ? 'live' : 'offline',
        'progress': activity?.progress ?? 0.0,
        'durationMs': activity?.durationMs ?? 0,
        'positionMs': activity?.positionMs ?? 0,
      };
    }).toList();
  }

  Future<void> _loadUserProfile() async {
    final photoUrl = await _storage.read(key: 'photo_url');
    final username = await _storage.read(key: 'username');

    if (mounted) {
      setState(() {
        if (photoUrl != null) _userPhotoUrl = photoUrl;
        if (username != null) _userName = username;
      });

      // Cache for offline mode
      final prefs = await SharedPreferences.getInstance();
      if (photoUrl != null) await prefs.setString('user_photo_url', photoUrl);
      if (username != null) await prefs.setString('username', username);
    }
  }

  Future<void> _loadData() async {
    try {
      final response = await _api.getLikedSongs();
      if (mounted && response != null) {
        setState(() {
          _likedSongsData = response;
          _likedSongs = (response['songs'] as List?) ?? [];
          _isLoading = false;
        });
        debugPrint('Liked songs fetched: ${_likedSongs.length}');
      }
      // Generate ambient colors from top 3 liked songs
      _generateAmbientColors();
    } catch (e) {
      debugPrint('Error fetching data: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Pull-to-refresh handler that resets loading states to show skeletons
  Future<void> _onPullToRefresh() async {
    // Reset loading states to show skeleton animations
    // Note: Don't pre-set _isPlaylistsLoading here as _loadSidebarPlaylists
    // has a guard that returns early if it's already true
    setState(() {
      _isLoading = true;
      _isFriendsLoading = true;
      _isAnalyticsLoading = true;
      _isPlaylistsLoading = true;
      _sidebarPlaylists = []; // Clear to show skeletons
    });

    // Refetch all data
    await Future.wait([
      _loadData(),
      _loadFriendsActivity(),
      _loadAnalyticsData(),
      _loadSidebarPlaylists(forceRefresh: true),
    ]);
  }

  Future<void> _loadAnalyticsData() async {
    try {
      // Load all analytics data in parallel
      final results = await Future.wait([
        _analyticsService.getTopSongs(limit: 10, period: 'week'),
        _analyticsService.getRecentlyPlayed(limit: 10), // Real recently played
        _analyticsService.getPlaylistStats(limit: 5),
      ]);

      if (mounted) {
        setState(() {
          _topSongs = results[0] as List<SongStats>;

          // Convert RecentSong to SongStats for compatibility
          final recent = results[1] as List<RecentSong>;
          _recentlyPlayed = recent
              .map(
                (r) => SongStats(
                  songId: r.songId,
                  title: r.title,
                  artistName: r.artistName,
                  coverPath: r.coverPath,
                  coverUrl: r.coverUrl, // Pass full URL from API
                  playCount: 0,
                  completionCount: 0,
                  skipCount: 0,
                  repeatCount: 0,
                  totalListenedMs: 0,
                  avgCompletionPct: 0,
                  lastPlayedAt: r.playedAt,
                ),
              )
              .toList();

          _topPlaylists = results[2] as List<PlaylistStats>;
          _isAnalyticsLoading = false;
        });
      }

      // Generate ambient colors from top songs if we have them
      if (_topSongs.isNotEmpty) {
        _generateAmbientColorsFromAnalytics();
      }
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      if (mounted) {
        setState(() => _isAnalyticsLoading = false);
      }
    }
  }

  Future<void> _generateAmbientColorsFromAnalytics() async {
    if (!mounted || _topSongs.isEmpty) return;

    List<Color> newColors = [];
    int count = min(3, _topSongs.length);

    for (int i = 0; i < count; i++) {
      try {
        // Prefer coverUrl (full URL from API) when available
        final coverUrl = _topSongs[i].coverUrl;
        final coverPath = _topSongs[i].coverPath;
        final imageUrl =
            coverUrl ??
            (coverPath.isNotEmpty ? '${ApiService.baseUrl}/$coverPath' : null);

        if (imageUrl != null) {
          final imageProvider = NetworkImage(imageUrl);
          final resizedImage = ResizeImage(imageProvider, width: 100);

          final paletteGenerator = await PaletteGenerator.fromImageProvider(
            resizedImage,
            maximumColorCount: 5,
          );

          Color? color =
              paletteGenerator.vibrantColor?.color ??
              paletteGenerator.dominantColor?.color ??
              paletteGenerator.mutedColor?.color;

          if (color != null) {
            newColors.add(color);
          }
        }
      } catch (e) {
        debugPrint('Error creating palette for top song $i: $e');
      }
    }

    if (mounted && newColors.isNotEmpty) {
      setState(() {
        _ambientColors = newColors;
      });
    }
  }

  Future<void> _generateAmbientColors() async {
    if (!mounted || _likedSongs.isEmpty) return;

    List<Color> newColors = [];
    int count = min(3, _likedSongs.length);

    for (int i = 0; i < count; i++) {
      try {
        // Prefer cover_url (full URL from API) when available
        String? coverUrl = _likedSongs[i]['cover_url'];
        String? coverPath = _likedSongs[i]['cover_path'];
        final imageUrl =
            coverUrl ??
            (coverPath != null ? '${ApiService.baseUrl}/$coverPath' : null);

        if (imageUrl != null) {
          final imageProvider = NetworkImage(imageUrl);
          // Use a smaller resize for faster palette generation
          final resizedImage = ResizeImage(imageProvider, width: 100);

          final paletteGenerator = await PaletteGenerator.fromImageProvider(
            resizedImage,
            maximumColorCount: 5,
          );

          // Get a vibrant or dominant color
          Color? color =
              paletteGenerator.vibrantColor?.color ??
              paletteGenerator.dominantColor?.color ??
              paletteGenerator.mutedColor?.color;

          if (color != null) {
            newColors.add(color);
          }
        }
      } catch (e) {
        debugPrint('Error creating palette for song $i: $e');
      }
    }

    if (mounted && newColors.isNotEmpty) {
      setState(() {
        _ambientColors = newColors;
      });
    }
  }

  Future<void> _logout() async {
    // Clear music playback state before logout
    final musicProvider = Provider.of<MusicProvider>(context, listen: false);
    musicProvider.clearPlaylist();
    await musicProvider.clearSavedPlaybackState();

    await _api.logout();
    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const AuthScreen()));
    }
  }

  void _openPlaylistLibrary() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PlaylistLibraryScreen()),
    );
  }

  Widget _buildSearchContent() {
    return ExploreScreen(
      isEmbedded: true,
      onAlbumSelected: (playlistId) {
        setState(() {
          _selectedPlaylistId = playlistId;
        });
      },
      onArtistSelected: (artistId, artistName, artistImage) {
        setState(() {
          _selectedArtistId = artistId;
          _selectedArtistName = artistName;
          _selectedArtistImage = artistImage;
        });
      },
    );
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
                            activeColor: Colors.white,
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
                                ),
                              );
                              // Refresh sidebar playlists
                              _loadSidebarPlaylists();
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

  void _playSong(int index) {
    final provider = Provider.of<MusicProvider>(context, listen: false);
    final playlistId = _likedSongsData?['id']; // Use actual playlist ID

    // Convert API songs to Song model
    final songs = _likedSongs.map((s) {
      return Song(
        id: s['id'],
        title: s['title'],
        artist: s['artist_name'] ?? 'Unknown Artist',
        album: s['album_name'],
        // stream_url from API is REQUIRED (no fallback - wrong server = wrong files)
        filePath: s['stream_url'] ?? '',
        streamUrl: s['stream_url'],
        coverUrl: s['cover_url'],
        artworkPath:
            s['cover_url'] ??
            (s['cover_path'] != null
                ? '${ApiService.baseUrl}/${s['cover_path']}'
                : null),
        duration: Duration(milliseconds: s['duration_ms'] ?? 0),
        genres: s['genres'] != null ? List<String>.from(s['genres']) : [],
        tags: s['tags'] != null ? List<String>.from(s['tags']) : [],
        source: s['source'] ?? 'user',
      );
    }).toList();

    provider.setPlaylist(
      songs,
      initialIndex: index,
      playlistId: playlistId,
      playlistName: 'Liked Songs',
    );
    _navigateToPlayer();
  }

  /// Restore playback state from last session (shows BottomPlayerBar with last song)
  Future<void> _restorePlaybackState() async {
    final provider = Provider.of<MusicProvider>(context, listen: false);

    try {
      // Get saved state from provider's playback state service
      final state = await provider.getSavedPlaybackState();
      if (state == null || state.songId == null) {
        debugPrint('📭 No saved playback state to restore');
        return;
      }

      debugPrint(
        '🔄 Restoring last session: songId=${state.songId}, position=${state.positionMs}ms',
      );

      List<Song> songs;
      String? playlistName = state.playlistName;
      String? playlistId = state.playlistId;
      int songIndex = 0;

      if (playlistId != null && playlistId.isNotEmpty) {
        // Load the playlist
        final playlistData = await _api.getPlaylist(playlistId);
        if (playlistData == null) {
          // Playlist was deleted - just load the single song
          playlistId = null;
          playlistName = null;
        } else {
          playlistName = playlistData['name'] as String?;
          final playlistSongs = (playlistData['songs'] as List?) ?? [];

          songs = playlistSongs
              .map(
                (s) => Song(
                  id: s['id'],
                  title: s['title'],
                  artist: s['artist_name'] ?? 'Unknown Artist',
                  album: s['album_name'],
                  filePath: s['stream_url'] ?? '',
                  streamUrl: s['stream_url'],
                  coverUrl: s['cover_url'],
                  artworkPath:
                      s['cover_url'] ??
                      (s['cover_path'] != null
                          ? '${ApiService.baseUrl}/${s['cover_path']}'
                          : null),
                  duration: Duration(milliseconds: s['duration_ms'] ?? 0),
                  genres: s['genres'] != null
                      ? List<String>.from(s['genres'])
                      : [],
                  tags: s['tags'] != null ? List<String>.from(s['tags']) : [],
                  source: s['source'] ?? 'user',
                ),
              )
              .toList();

          // Find the song in the playlist
          songIndex = songs.indexWhere((s) => s.id == state.songId);
          if (songIndex == -1) songIndex = 0;

          if (songs.isNotEmpty) {
            // Set playlist WITHOUT auto-playing (play: false)
            provider.setPlaylist(
              songs,
              initialIndex: songIndex,
              playlistId: playlistId,
              playlistName: playlistName,
              play: false,
            );

            // Seek to saved position after a delay for the player to be ready
            if (state.positionMs > 0) {
              await Future.delayed(const Duration(milliseconds: 500));
              await provider.seekTo(Duration(milliseconds: state.positionMs));
              debugPrint('⏩ Seeked to saved position: ${state.positionMs}ms');
            }

            debugPrint(
              '✅ Restored playlist state: ${songs.length} songs, index $songIndex',
            );
            return;
          }
        }
      }

      // Fallback: load just the single song
      final singleSong = await _api.getSong(state.songId!);
      if (singleSong != null) {
        songs = [
          Song(
            id: singleSong['id'],
            title: singleSong['title'],
            artist: singleSong['artist_name'] ?? 'Unknown Artist',
            album: singleSong['album_name'],
            filePath: singleSong['stream_url'] ?? '',
            streamUrl: singleSong['stream_url'],
            coverUrl: singleSong['cover_url'],
            artworkPath:
                singleSong['cover_url'] ??
                (singleSong['cover_path'] != null
                    ? '${ApiService.baseUrl}/${singleSong['cover_path']}'
                    : null),
            duration: Duration(milliseconds: singleSong['duration_ms'] ?? 0),
            source: singleSong['source'] ?? 'user',
          ),
        ];

        // Set playlist WITHOUT auto-playing (play: false)
        provider.setPlaylist(songs, initialIndex: 0, play: false);

        // Seek to saved position after a delay for the player to be ready
        if (state.positionMs > 0) {
          await Future.delayed(const Duration(milliseconds: 500));
          await provider.seekTo(Duration(milliseconds: state.positionMs));
          debugPrint('⏩ Seeked to saved position: ${state.positionMs}ms');
        }

        debugPrint('✅ Restored single song state: ${singleSong['title']}');
      }
    } catch (e) {
      debugPrint('❌ Error restoring playback state: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.of(context).size.width > 800;
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    Widget mainContent = Stack(
      children: [
        // Use Positioned.fill to ensure the content stretches to full screen size
        Positioned.fill(
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.stretch, // Ensure vertically fills
            children: [
              // Sidebar (Desktop only)
              if (isLargeScreen) SizedBox(width: 280, child: _buildSidebar()),

              // Main Content - switches based on nav selection
              // Priority: Playlist > Artist > Nav tabs (so album from artist can go back)
              Expanded(
                child: _selectedPlaylistId != null && isLargeScreen
                    ? _buildPlaylistDetailContent()
                    : _selectedArtistId != null && isLargeScreen
                    ? ArtistProfileScreen(
                        artistId: _selectedArtistId!,
                        artistName: _selectedArtistName ?? '',
                        artistImage: _selectedArtistImage,
                        onBackPressed: () {
                          setState(() {
                            _selectedArtistId = null;
                            _selectedArtistName = null;
                            _selectedArtistImage = null;
                          });
                        },
                        onAlbumSelected: (playlistId) {
                          setState(() {
                            // Keep artist selection so back returns here
                            _selectedPlaylistId = playlistId;
                          });
                        },
                      )
                    : _selectedNavIndex == 2
                    ? const PlaylistLibraryScreen(isEmbedded: true)
                    : _selectedNavIndex == 1
                    ? _buildSearchContent()
                    : Stack(
                        children: [
                          // Base Background
                          Container(color: Colors.black),

                          // Ambient Background (for home content)
                          if (_ambientColors.isNotEmpty) ...[
                            // Spot 1: Primary Color (Top Right)
                            Positioned(
                              top: -80,
                              right: -100,
                              width: 450,
                              height: 400,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _ambientColors[0].withOpacity(0.3),
                                ),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: 80,
                                    sigmaY: 80,
                                  ),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                            ),
                          ],
                          if (_ambientColors.length > 1) ...[
                            // Spot 2: Secondary Color (Left Center)
                            Positioned(
                              top: 150,
                              left: -80,
                              width: 350,
                              height: 350,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _ambientColors[1].withOpacity(0.25),
                                ),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: 100,
                                    sigmaY: 100,
                                  ),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                            ),
                          ],
                          if (_ambientColors.length > 2) ...[
                            // Spot 3: Third Color (Top Center/Bottom)
                            Positioned(
                              top: -120,
                              left: 100,
                              right: 100,
                              height: 350,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _ambientColors[2].withOpacity(0.2),
                                ),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: 120,
                                    sigmaY: 120,
                                  ),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                            ),
                          ],

                          // Fallback ambient if no colors extracted yet (e.g. initial load or failure)
                          if (_ambientColors.isEmpty) ...[
                            Positioned(
                              top: -100,
                              left: -50,
                              width: 500,
                              height: 400,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(
                                    0xFF400080,
                                  ).withOpacity(0.15),
                                ),
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: 100,
                                    sigmaY: 100,
                                  ),
                                  child: Container(color: Colors.transparent),
                                ),
                              ),
                            ),
                          ],

                          // Gradient Overlay to fade into black body
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height:
                                500, // Shortened height of overlay to match blobs
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.3),
                                    Colors.black.withOpacity(0.8),
                                    Colors.black, // Fade to full black
                                    Colors.black, // Solid black buffer
                                  ],
                                  stops: const [0.0, 0.4, 0.7, 1.0],
                                ),
                              ),
                            ),
                          ),

                          // Content - wrapped with RefreshIndicator for mobile
                          !isLargeScreen
                              ? RefreshIndicator(
                                  onRefresh: _onPullToRefresh,
                                  color: const Color(0xFF1DB954),
                                  backgroundColor: Colors.grey[900],
                                  child: CustomScrollView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    slivers: [
                                      // Header
                                      SliverToBoxAdapter(
                                        child: _buildHeader(isLargeScreen),
                                      ),

                                      // Sections
                                      SliverPadding(
                                        padding: const EdgeInsets.only(
                                          left: 24.0,
                                          right: 24.0,
                                          bottom: 24.0,
                                        ),
                                        sliver: SliverList(
                                          delegate: SliverChildListDelegate([
                                            // Hero Section (Highlights)
                                            _buildHeroSection(),

                                            if (!MediaQuery.of(context)
                                                    .size
                                                    .width
                                                    .clamp(0, double.infinity)
                                                    .isInfinite &&
                                                MediaQuery.of(
                                                      context,
                                                    ).size.width <
                                                    800) ...[
                                              const SizedBox(height: 16),
                                              _buildTopOfWeek(),
                                              const SizedBox(height: 32),
                                              _buildPlaylistsForYou(),
                                            ],

                                            const SizedBox(height: 32),

                                            if (MediaQuery.of(
                                                  context,
                                                ).size.width >
                                                800) ...[
                                              // User's Playlists (Desktop Only)
                                              _buildSectionTitle(
                                                'Your Playlists',
                                              ),
                                              const SizedBox(height: 16),
                                              _buildHorizontalGrid(),
                                              const SizedBox(height: 32),
                                            ],

                                            // Liked Songs (Actual Data)
                                            /* Split Section: Liked Songs & Recently Played */
                                            _buildSplitSection(),
                                          ]),
                                        ),
                                      ),

                                      const SliverPadding(
                                        padding: EdgeInsets.only(bottom: 120),
                                      ),
                                    ],
                                  ),
                                )
                              : CustomScrollView(
                                  slivers: [
                                    // Header
                                    SliverToBoxAdapter(
                                      child: _buildHeader(isLargeScreen),
                                    ),

                                    // Sections
                                    SliverPadding(
                                      padding: const EdgeInsets.only(
                                        left: 24.0,
                                        right: 24.0,
                                        bottom: 24.0,
                                      ),
                                      sliver: SliverList(
                                        delegate: SliverChildListDelegate([
                                          // Hero Section (Highlights)
                                          _buildHeroSection(),

                                          if (!MediaQuery.of(context).size.width
                                                  .clamp(0, double.infinity)
                                                  .isInfinite &&
                                              MediaQuery.of(
                                                    context,
                                                  ).size.width <
                                                  800) ...[
                                            const SizedBox(height: 16),
                                            _buildTopOfWeek(),
                                            const SizedBox(height: 32),
                                            _buildPlaylistsForYou(),
                                          ],

                                          const SizedBox(height: 32),

                                          if (MediaQuery.of(
                                                context,
                                              ).size.width >
                                              800) ...[
                                            // User's Playlists (Desktop Only)
                                            _buildSectionTitle(
                                              'Your Playlists',
                                            ),
                                            const SizedBox(height: 16),
                                            _buildHorizontalGrid(),
                                            const SizedBox(height: 32),
                                          ],

                                          // Liked Songs (Actual Data)
                                          /* Split Section: Liked Songs & Recently Played */
                                          _buildSplitSection(),
                                        ]),
                                      ),
                                    ),

                                    const SliverPadding(
                                      padding: EdgeInsets.only(bottom: 120),
                                    ),
                                  ],
                                ),
                        ], // Close Stack children
                      ), // Close Stack
              ), // Close Expanded
              // Desktop Queue Panel (slides in from right)
              if (isLargeScreen)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: _showQueuePanel ? 350 : 0,
                  child: _showQueuePanel
                      ? DesktopQueuePanel(
                          onClose: () {
                            setState(() {
                              _showQueuePanel = false;
                            });
                          },
                        )
                      : null,
                ),
            ],
          ),
        ),

        // Player Bar
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Consumer<MusicProvider>(
            builder: (context, provider, _) {
              if (provider.currentSong == null) return const SizedBox.shrink();

              // Use the same Hero-friendly route for both desktop and mobile
              return BottomPlayerBar(
                onTap: () {
                  _navigateToPlayer();
                },
                onQueueTap: isLargeScreen
                    ? () {
                        setState(() {
                          _showQueuePanel = !_showQueuePanel;
                        });
                      }
                    : null,
                showFullControls: isLargeScreen,
                showQueueActive: _showQueuePanel,
              );
            },
          ),
        ),
      ],
    );

    // Wrap with custom title bar on desktop
    if (isDesktop && isLargeScreen) {
      mainContent = Column(
        children: [
          const CustomTitleBar(height: 40, showTitle: true),
          Expanded(child: mainContent),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: mainContent,
      // Mobile Bottom Nav (only if small screen)
      bottomNavigationBar: !isLargeScreen
          ? BottomNavigationBar(
              currentIndex: _selectedNavIndex,
              onTap: (index) => setState(() => _selectedNavIndex = index),
              backgroundColor: const Color(0xFF121212),
              selectedItemColor: Colors.white,
              unselectedItemColor: Colors.grey,
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_filled),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music),
                  label: 'Library',
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildSidebar() {
    return Container(
      color: Colors.black,
      width: 280,
      child: Column(
        children: [
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Heading with logo
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 32),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SvgPicture.asset(
                            'assets/images/kiokuu_white.svg',
                            width: 38,
                            height: 38,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'KioKuu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Navigation
                    _buildSidebarNavItem(Icons.home_filled, 'Home', 0),
                    const SizedBox(height: 4),
                    _buildSidebarNavItem(Icons.explore_outlined, 'Explore', 1),

                    const SizedBox(height: 4),
                    _buildSidebarNavItem(
                      Icons.upload,
                      'Upload music',
                      -1,
                      onTap: _showUploadDialog,
                    ),

                    const SizedBox(height: 32),

                    // Playlists Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'PLAYLISTS',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  // Switch to search?
                                  setState(() => _selectedNavIndex = 1);
                                },
                                child: Icon(
                                  Icons.search,
                                  size: 18,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(width: 16),
                              InkWell(
                                onTap: _showCreatePlaylistDialog,
                                child: Icon(
                                  Icons.add,
                                  size: 20,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            'PLAYLIST',
                            _sidebarFilter == 'PLAYLIST',
                            onTap: () {
                              setState(() => _sidebarFilter = 'PLAYLIST');
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'ALBUM',
                            _sidebarFilter == 'ALBUM',
                            onTap: () {
                              setState(() => _sidebarFilter = 'ALBUM');
                              _loadRecentArtistsAndAlbums(resetShowFlags: true);
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'ARTIST',
                            _sidebarFilter == 'ARTIST',
                            onTap: () {
                              setState(() => _sidebarFilter = 'ARTIST');
                              _loadFollowedArtists();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    const SizedBox(height: 8),

                    // Show content based on selected filter
                    if (_sidebarFilter == 'PLAYLIST') ...[
                      // Dynamic Playlists
                      if (_isPlaylistsLoading && _sidebarPlaylists.isEmpty)
                        const SkeletonSidebarSection(
                          itemCount: 4,
                          isCircular: false,
                        )
                      else ...[
                        // First 4 playlists
                        ..._sidebarPlaylists.take(4).map((pl) {
                          final name = pl['name'] as String? ?? 'Playlist';
                          final songCount = pl['song_count'] as int? ?? 0;
                          final coverImages =
                              (pl['cover_images'] as List?)?.cast<String>() ??
                              [];
                          final coverImageUrls =
                              (pl['cover_image_urls'] as List?)
                                  ?.cast<String>() ??
                              [];
                          // Prefer full URLs from API
                          final effectiveCovers = coverImageUrls.isNotEmpty
                              ? coverImageUrls
                              : coverImages;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildSidebarPlaylistItem(
                              title: name,
                              subtitle: '$songCount songs',
                              coverImages: effectiveCovers,
                              playlistId: pl['id'] as String? ?? '',
                              isSelected:
                                  _selectedPlaylistId ==
                                  (pl['id'] as String? ?? ''),
                              onTap: () {
                                final playlistId = pl['id'] as String? ?? '';
                                setState(() {
                                  _selectedPlaylistId = playlistId;
                                  _selectedArtistId = null;
                                });
                              },
                            ),
                          );
                        }),

                        // Hidden Playlists
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          firstChild: const SizedBox(width: double.infinity),
                          secondChild: Column(
                            children: _sidebarPlaylists.skip(4).map((pl) {
                              final name = pl['name'] as String? ?? 'Playlist';
                              final songCount = pl['song_count'] as int? ?? 0;
                              final coverImages =
                                  (pl['cover_images'] as List?)
                                      ?.cast<String>() ??
                                  [];
                              final coverImageUrls =
                                  (pl['cover_image_urls'] as List?)
                                      ?.cast<String>() ??
                                  [];
                              // Prefer full URLs from API
                              final effectiveCovers = coverImageUrls.isNotEmpty
                                  ? coverImageUrls
                                  : coverImages;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildSidebarPlaylistItem(
                                  title: name,
                                  subtitle: '$songCount songs',
                                  coverImages: effectiveCovers,
                                  playlistId: pl['id'] as String? ?? '',
                                  isSelected:
                                      _selectedPlaylistId ==
                                      (pl['id'] as String? ?? ''),
                                  onTap: () {
                                    final playlistId =
                                        pl['id'] as String? ?? '';
                                    setState(() {
                                      _selectedPlaylistId = playlistId;
                                      _selectedArtistId = null;
                                    });
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                          crossFadeState: _showAllPlaylists
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                        ),

                        // View More Button
                        if (_sidebarPlaylists.length > 4)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _showAllPlaylists = !_showAllPlaylists;
                                });
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _showAllPlaylists
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color: Colors.grey[500],
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _showAllPlaylists
                                          ? 'Show Less'
                                          : 'Show ${_sidebarPlaylists.length - 4} More',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ] else if (_sidebarFilter == 'ALBUM') ...[
                      // Recently Played Albums
                      if (_isRecentArtistsAlbumsLoading &&
                          _recentAlbums.isEmpty)
                        const SkeletonSidebarSection(
                          itemCount: 4,
                          isCircular: false,
                        )
                      else if (_recentAlbums.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No recently played albums yet.\nPlay some music to see them here!',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else ...[
                        // First 4 albums
                        ...(_recentAlbums
                            .take(4)
                            .map(
                              (album) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _buildSidebarRecentItem(
                                  title: album.name,
                                  subtitle: album.artistName,
                                  imageUrl: album.imagePath.isNotEmpty
                                      ? album.imagePath
                                      : null,
                                  isCircular: false,
                                  isSelected:
                                      _selectedPlaylistId == album.playlistId,
                                  onTap: () {
                                    if (album.playlistId != null &&
                                        album.playlistId!.isNotEmpty) {
                                      setState(() {
                                        _selectedPlaylistId = album.playlistId;
                                      });
                                    }
                                  },
                                ),
                              ),
                            )),

                        // Show more albums (animated)
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 300),
                          firstChild: const SizedBox(width: double.infinity),
                          secondChild: Column(
                            children: _recentAlbums
                                .skip(4)
                                .map(
                                  (album) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _buildSidebarRecentItem(
                                      title: album.name,
                                      subtitle: album.artistName,
                                      imageUrl: album.imagePath.isNotEmpty
                                          ? album.imagePath
                                          : null,
                                      isCircular: false,
                                      isSelected:
                                          _selectedPlaylistId ==
                                          album.playlistId,
                                      onTap: () {
                                        if (album.playlistId != null &&
                                            album.playlistId!.isNotEmpty) {
                                          setState(() {
                                            _selectedPlaylistId =
                                                album.playlistId;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),

                          crossFadeState: _showAllAlbums
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                        ),

                        // Buttons for albums
                        if (_totalAlbums > 4)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0, top: 4.0),
                            child: Row(
                              children: [
                                // Show More / Show Less button (always visible)
                                InkWell(
                                  onTap: () => setState(
                                    () => _showAllAlbums = !_showAllAlbums,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 4,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _showAllAlbums
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: Colors.grey[500],
                                          size: 20,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _showAllAlbums
                                              ? 'Show Less'
                                              : 'Show ${(_totalAlbums - 4).clamp(0, _totalAlbums)} More',
                                          style: TextStyle(
                                            color: Colors.grey[500],
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Load More button (only when expanded and more available)
                                if (_showAllAlbums &&
                                    _recentAlbums.length < _totalAlbums) ...[
                                  const SizedBox(width: 12),
                                  InkWell(
                                    onTap: _isRecentArtistsAlbumsLoading
                                        ? null
                                        : () {
                                            _loadRecentArtistsAndAlbums(
                                              loadMore: true,
                                            );
                                          },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_isRecentArtistsAlbumsLoading)
                                            const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.grey,
                                              ),
                                            )
                                          else
                                            Icon(
                                              Icons.add,
                                              color: Colors.grey[500],
                                              size: 18,
                                            ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _isRecentArtistsAlbumsLoading
                                                ? 'Loading...'
                                                : 'Load ${(_totalAlbums - _recentAlbums.length).clamp(1, 4)} More',
                                            style: TextStyle(
                                              color: Colors.grey[500],
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ] else if (_sidebarFilter == 'ARTIST') ...[
                      // Followed Artists
                      if (_isFollowedArtistsLoading && _followedArtists.isEmpty)
                        const SkeletonSidebarSection(
                          itemCount: 4,
                          isCircular: true,
                        )
                      else if (_followedArtists.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No followed artists yet.\nFollow artists to see them here!',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ..._followedArtists.map((artist) {
                          final fullImageUrl = ApiService.getImageUrl(artist);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildSidebarRecentItem(
                              title: artist['name'] ?? 'Unknown',
                              subtitle:
                                  '${artist['follower_count'] ?? 0} followers',
                              imageUrl: fullImageUrl,
                              isCircular: true,
                              isSelected:
                                  _selectedArtistId == artist['artist_id'],
                              onTap: () {
                                setState(() {
                                  _selectedArtistId = artist['artist_id'];
                                  _selectedArtistName = artist['name'];
                                  _selectedArtistImage = fullImageUrl;
                                  _selectedPlaylistId = null;
                                });
                              },
                            ),
                          );
                        }),
                    ],

                    const SizedBox(height: 32),

                    // Friends Activity
                    _buildSidebarFriends(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarNavItem(
    IconData icon,
    String title,
    int index, {
    VoidCallback? onTap,
  }) {
    final isSelected =
        _selectedNavIndex == index &&
        _selectedPlaylistId == null &&
        index != -1;
    return InkWell(
      onTap:
          onTap ??
          () {
            setState(() {
              _selectedNavIndex = index;
              _selectedPlaylistId = null;
              _selectedArtistId = null; // Clear artist selection too
            });

            switch (index) {
              case 0:
                _loadData();
                _loadSidebarPlaylists();
                _loadAnalyticsData();
                break;
              case 1:
                // Search or Explore
                break;
              case 2:
                // Library
                break;
            }
          },
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white.withOpacity(0.5),
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withOpacity(0.5),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    bool isSelected, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE0E0E0) : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey[400],
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSidebarRecentItem({
    required String title,
    required String subtitle,
    String? imageUrl,
    bool isCircular = false,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: Colors.white.withOpacity(0.05),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isSelected ? Colors.white.withOpacity(0.1) : null,
        ),
        child: Row(
          children: [
            // Thumbnail (circular for artists, square for albums)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF282828),
                borderRadius: isCircular
                    ? BorderRadius.circular(22)
                    : BorderRadius.circular(4),
              ),
              child: imageUrl != null
                  ? ClipRRect(
                      borderRadius: isCircular
                          ? BorderRadius.circular(22)
                          : BorderRadius.circular(4),
                      child: Image.network(
                        imageUrl!.startsWith('http')
                            ? imageUrl
                            : '${ApiService.baseUrl}/$imageUrl',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          isCircular ? Icons.person : Icons.album,
                          color: Colors.grey[600],
                          size: 20,
                        ),
                      ),
                    )
                  : Icon(
                      isCircular ? Icons.person : Icons.album,
                      color: Colors.grey[600],
                      size: 20,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
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
    );
  }

  Widget _buildSidebarPlaylistItem({
    required String title,
    required String subtitle,
    IconData? icon,
    List<String>? coverImages,
    required VoidCallback onTap,
    String? playlistId,
    bool isSelected = false,
  }) {
    final musicProvider = Provider.of<MusicProvider>(context);
    final isPlaying =
        playlistId != null && musicProvider.currentPlaylistId == playlistId;
    final isHighlighted = isPlaying || isSelected;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: Colors.white.withOpacity(0.05),
      child: Container(
        decoration: BoxDecoration(
          color: isHighlighted
              ? Colors.white.withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: Row(
          children: [
            // Square Thumbnail with playing indicator - now uses mosaic
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF282828),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: coverImages != null && coverImages.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: PlaylistCoverMosaic(
                            coverImages: coverImages,
                            size: 48,
                            borderRadius: 4,
                          ),
                        )
                      : Icon(
                          icon ?? Icons.music_note,
                          color: Colors.grey[600],
                          size: 22,
                        ),
                ),
                // Playing indicator overlay
                if (isPlaying)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(child: _buildMiniEqualizer()),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isHighlighted
                          ? Colors.white
                          : Colors.white.withOpacity(0.6),
                      fontWeight: isHighlighted
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 12,
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
    );
  }

  Widget _buildTopOfWeek() {
    // Show skeleton while loading
    if (_isAnalyticsLoading) {
      return const SkeletonTopOfWeekGrid();
    }

    // Show empty state if no data
    if (_topSongs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Top of this week',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.music_note, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 8),
                  Text(
                    'Start listening to see your top songs!',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top of this week',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3.5, // Wide short rows
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: min(6, _topSongs.length),
          itemBuilder: (context, index) {
            final song = _topSongs[index];
            // Prefer coverUrl (full URL from API) when available
            final coverImage =
                song.coverUrl ??
                (song.coverPath.isNotEmpty
                    ? '${ApiService.baseUrl}/${song.coverPath}'
                    : null);

            return GestureDetector(
              onTap: () => _playTopSong(index),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: coverImage != null
                        ? NetworkImage(coverImage)
                        : null,
                    child: coverImage == null
                        ? const Icon(Icons.music_note, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          song.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.artistName,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Play count badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${song.playCount}×',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  void _playTopSong(int index) {
    if (_topSongs.isEmpty || index >= _topSongs.length) return;

    final provider = Provider.of<MusicProvider>(context, listen: false);
    final songs = _topSongs
        .map(
          (s) => Song(
            id: s.songId,
            title: s.title,
            artist: s.artistName,
            filePath: '${ApiService.baseUrl}/stream/${s.songId}',
            // Use coverUrl (full URL from API) when available
            artworkPath:
                s.coverUrl ??
                (s.coverPath.isNotEmpty
                    ? '${ApiService.baseUrl}/${s.coverPath}'
                    : null),
            duration: Duration(
              milliseconds: s.totalListenedMs ~/ max(1, s.playCount),
            ),
          ),
        )
        .toList();

    provider.setPlaylist(songs, initialIndex: index, playlistName: 'Top Songs');
    _navigateToPlayer();
  }

  Widget _buildPlaylistsForYou() {
    // Show skeleton while loading
    if (_isPlaylistsLoading && _sidebarPlaylists.isEmpty) {
      return const SkeletonSection(
        itemCount: 3,
        itemWidth: 160,
        itemHeight: 160,
      );
    }

    // Show empty state if no playlists
    if (_sidebarPlaylists.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Playlists',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.playlist_add, size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first playlist!',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _showCreatePlaylistDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('New Playlist'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Playlists',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                ui.PointerDeviceKind.touch,
                ui.PointerDeviceKind.mouse,
              },
            ),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: min(5, _sidebarPlaylists.length),
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final pl = _sidebarPlaylists[index];
                final coverImages =
                    (pl['cover_images'] as List?)?.cast<String>() ?? [];
                final coverImageUrls =
                    (pl['cover_image_urls'] as List?)?.cast<String>() ?? [];
                final name = pl['name'] as String? ?? 'Playlist';
                final songCount = pl['song_count'] as int? ?? 0;
                final playlistId = pl['id'] as String? ?? '';

                // Prefer full URLs from API, fallback to paths
                final effectiveCovers = coverImageUrls.isNotEmpty
                    ? coverImageUrls
                    : coverImages;

                return GestureDetector(
                  onTap: () {
                    // On large screens, use master-detail pattern
                    final isLargeScreen =
                        MediaQuery.of(context).size.width > 800;
                    if (isLargeScreen) {
                      setState(() {
                        _selectedPlaylistId = playlistId;
                        _selectedArtistId = null;
                      });
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              PlaylistDetailScreen(playlistId: playlistId),
                        ),
                      ).then((_) {
                        _loadSidebarPlaylists(); // Refresh playlist data
                        _loadData();
                      });
                    }
                  },
                  child: Container(
                    width: 160,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFF282828),
                    ),
                    child: Stack(
                      children: [
                        // Cover image or mosaic
                        if (effectiveCovers.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: effectiveCovers.length >= 4
                                ? PlaylistCoverMosaic(
                                    coverImages: effectiveCovers
                                        .take(4)
                                        .toList(),
                                    size: 160,
                                  )
                                : Image.network(
                                    // Use URL directly if starts with http, else construct
                                    effectiveCovers.first.startsWith('http')
                                        ? effectiveCovers.first
                                        : '${ApiService.baseUrl}/${effectiveCovers.first}',
                                    width: 160,
                                    height: 160,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Colors.grey[800],
                                      child: const Icon(
                                        Icons.music_note,
                                        size: 48,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                colors: [
                                  Colors.purple.shade700,
                                  Colors.blue.shade700,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.queue_music,
                                size: 48,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        // Gradient overlay with info
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.8),
                              ],
                              stops: const [0.4, 1.0],
                            ),
                          ),
                          alignment: Alignment.bottomLeft,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '$songCount songs',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 11,
                                ),
                              ),
                            ],
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
    );
  }

  Widget _buildPlaylistItem(
    String title, {
    IconData? icon,
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  gradient: color != null
                      ? LinearGradient(colors: [color.withOpacity(0.8), color])
                      : null,
                  color: color == null ? Colors.grey[800] : null,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Icon(icon, color: Colors.white, size: 16),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniEqualizer() {
    return SizedBox(
      width: 16,
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (i) => _MiniEqualizerBar(index: i)),
      ),
    );
  }

  void _playLikedSongs({int startIndex = 0, bool shuffle = false}) {
    if (_likedSongs.isEmpty) return;

    final provider = Provider.of<MusicProvider>(context, listen: false);
    final playlistId =
        _likedSongsData?['id'] ?? 'liked-songs'; // Use actual playlist ID

    final songs = _likedSongs
        .map(
          (s) => Song(
            id: s['id'],
            title: s['title'] ?? '',
            artist: s['artist_name'] ?? 'Unknown Artist',
            album: s['album_name'] ?? '',
            filePath: s['stream_url'] ?? '',
            streamUrl: s['stream_url'],
            coverUrl: s['cover_url'],
            artworkPath:
                s['cover_url'] ??
                (s['cover_path'] != null
                    ? '${ApiService.baseUrl}/${s['cover_path']}'
                    : null),
            duration: Duration(milliseconds: s['duration_ms'] ?? 0),
            genres: s['genres'] != null ? List<String>.from(s['genres']) : [],
            tags: s['tags'] != null ? List<String>.from(s['tags']) : [],
            source: s['source'] ?? 'user',
          ),
        )
        .toList();

    provider.setPlaylist(
      songs,
      initialIndex: startIndex,
      playlistId: playlistId,
      playlistName: 'Liked Songs',
    );

    if (shuffle && !provider.isShuffled) {
      provider.toggleShuffle();
    }
  }

  Widget _buildDynamicPlaylistItem(Map<String, dynamic> playlist) {
    final name = playlist['name'] ?? 'Untitled';
    final songCount = playlist['song_count'] ?? 0;
    final coverImages = playlist['cover_images'] as List<dynamic>? ?? [];
    final playlistId = playlist['id'] ?? '';
    final isSystem = playlist['is_system'] ?? false;
    final isLargeScreen = MediaQuery.of(context).size.width > 800;
    final isSelected = _selectedPlaylistId == playlistId;

    final isLoading = _loadingPlaylistId == playlistId;

    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        final isCurrentPlaylist = provider.currentPlaylistId == playlistId;
        final isPlaying = isCurrentPlaylist && provider.isPlaying;

        return InkWell(
          onTap: () async {
            if (isLargeScreen) {
              setState(() {
                _selectedPlaylistId = playlistId;
                _selectedPlaylistName = name;
                _playlistScrollOffset = 0.0;
                _loadingPlaylistId = playlistId;
                _selectedArtistId = null; // Clear artist selection
              });
              // Refresh sidebar to update song counts (silently)
              await _loadSidebarPlaylists();
              if (mounted) setState(() => _loadingPlaylistId = null);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
                ),
              ).then((_) {
                // Refresh when returning from playlist detail
                _loadSidebarPlaylists();
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12),
            child: Row(
              children: [
                // Cover art thumbnail with playing/loading indicator
                Stack(
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          decoration: BoxDecoration(
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                            // Only Liked Songs gets special gradient icon
                            gradient:
                                isSystem &&
                                    name == 'Liked Songs' &&
                                    coverImages.isEmpty
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF7B2FBB),
                                      Color(0xFF4A1A7A),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                // Other system playlists without covers get their own gradients
                                : isSystem &&
                                      coverImages.isEmpty &&
                                      name == 'Most Played'
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFFFF6B35),
                                      Color(0xFFFFA07A),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : isSystem &&
                                      coverImages.isEmpty &&
                                      name == 'Recently Played'
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF282828),
                                      Color(0xFF121212),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                          ),
                          // Only Liked Songs shows heart icon, others show cover or fallback icon
                          child:
                              isSystem &&
                                  name == 'Liked Songs' &&
                                  coverImages.isEmpty
                              ? const Center(
                                  child: Icon(
                                    Icons.favorite,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                )
                              : isSystem &&
                                    coverImages.isEmpty &&
                                    name == 'Most Played'
                              ? const Center(
                                  child: Icon(
                                    Icons.bar_chart,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                )
                              : isSystem &&
                                    coverImages.isEmpty &&
                                    name == 'Recently Played'
                              ? const Center(
                                  child: Icon(
                                    Icons.history,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                )
                              : PlaylistCoverMosaic(
                                  coverImages: coverImages.cast<String>(),
                                  borderRadius: isSelected ? 2 : 4,
                                ),
                        ),
                      ),
                    ),
                    // Loading indicator overlay
                    if (isLoading)
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    // Playing indicator overlay
                    else if (isCurrentPlaylist)
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: isPlaying
                              ? _buildSidebarEqualizer()
                              : const Icon(
                                  Icons.pause,
                                  color: Colors.white,
                                  size: 14,
                                ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: isCurrentPlaylist
                              ? Colors.white
                              : (isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.6)),
                          fontSize: 13,
                          fontWeight: isCurrentPlaylist || isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        isCurrentPlaylist ? 'Now Playing' : '$songCount songs',
                        style: TextStyle(
                          color: isCurrentPlaylist
                              ? Colors.white.withValues(alpha: 0.8)
                              : Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSidebarEqualizer() {
    return const _AnimatedEqualizer(color: Colors.white, size: 14);
  }

  /// Builds the playlist detail content for master-detail layout on large screens
  Widget _buildPlaylistDetailContent() {
    // Calculate title opacity based on scroll (fade in after 200px)
    final titleOpacity = (_playlistScrollOffset / 200).clamp(0.0, 1.0);

    return Stack(
      children: [
        // Playlist content with scroll listener
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                setState(() {
                  _playlistScrollOffset = notification.metrics.pixels;
                });
              }
              return false;
            },
            // All playlists (including system "Liked Songs") use PlaylistDetailScreen
            child: PlaylistDetailScreen(
              playlistId: _selectedPlaylistId!,
              isEmbedded: true,
              onBackPressed: () {
                setState(() {
                  _selectedPlaylistId = null;
                });
              },
            ),
          ),
        ),

        // Glass effect header - only shows when scrolled
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: titleOpacity < 0.1,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: titleOpacity > 0.1 ? 1.0 : 0.0,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(
                        0.5 + (titleOpacity * 0.3),
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withOpacity(0.05 * titleOpacity),
                          width: 1,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Center(
                        child: Text(
                          _selectedPlaylistName ?? 'Playlist',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(
                              0.5 + (titleOpacity * 0.5),
                            ),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(bool isLargeScreen) {
    // Get the safe area top padding (status bar height) for mobile
    final topPadding = isLargeScreen ? 0.0 : MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.only(
        left: isLargeScreen ? 24.0 : 16.0,
        right: isLargeScreen ? 24.0 : 16.0,
        top: isLargeScreen
            ? 16.0
            : (topPadding + 8.0), // Add status bar + small padding
        bottom: isLargeScreen ? 16.0 : 12.0,
      ),
      child: Row(
        children: [
          // Logo / Brand
          if (!isLargeScreen) ...[
            Row(
              children: [
                SvgPicture.asset(
                  'assets/images/kiokuu_white.svg',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(width: 10),
                const Text(
                  'KioKuu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],

          // Desktop: Search bar
          if (isLargeScreen) ...[
            SizedBox(
              width: 400,
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.search, color: Colors.black54, size: 18),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        textAlignVertical: TextAlignVertical.center,
                        decoration: const InputDecoration(
                          hintText: 'What do you want to listen to?',
                          border: InputBorder.none,
                          isDense: true,
                          hintStyle: TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                          ),
                          contentPadding: EdgeInsets.only(
                            bottom: 2,
                          ), // Visual nudge
                        ),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          height: 1.0,
                        ),
                        onSubmitted: (val) {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(), // Push right-side icons to end
          ],

          // Spacer for mobile to push icons to right
          if (!isLargeScreen) const Spacer(),

          // Right side icons
          if (isLargeScreen) ...[
            TextButton(
              onPressed: _showUploadDialog,
              child: const Text(
                'Upload',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Import Status Indicator
          if (_isImporting || _waitingForAI) ...[
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: _waitingForAI
                  ? IconButton(
                      onPressed: _showAIDownloadPrompt,
                      icon: const Icon(Icons.warning_amber_rounded),
                      color: Colors.orangeAccent,
                      tooltip: 'AI Extension Required',
                    )
                  : Tooltip(
                      message: 'Importing ${_importTasks.length} songs...',
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
            ),
          ],

          // Mobile: Action icons with proper spacing
          if (!isLargeScreen) ...[
            IconButton(
              onPressed: _showUploadDialog,
              icon: const Icon(Icons.add, size: 26),
              color: Colors.white,
              tooltip: 'Upload Music',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                setState(() => _selectedNavIndex = 1);
              },
              icon: const Icon(Icons.search, size: 24),
              color: Colors.white,
              tooltip: 'Search',
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
          ],

          // Desktop only: Refresh button (mobile uses pull-to-refresh)
          if (isLargeScreen)
            IconButton(
              onPressed: _onPullToRefresh,
              icon: const Icon(Icons.refresh),
              color: Colors.white,
              tooltip: 'Refresh',
              iconSize: 24,
            ),

          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            child: CircleAvatar(
              radius: isLargeScreen ? 18 : 17,
              backgroundImage: _userPhotoUrl != null
                  ? NetworkImage(_userPhotoUrl!)
                  : null,
              backgroundColor: Colors.grey[800],
              child: _userPhotoUrl == null
                  ? Icon(
                      Icons.person,
                      size: isLargeScreen ? 18 : 17,
                      color: Colors.grey[400],
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    // Check width to switch between Hero Carousel and Friends Activity
    final double width = MediaQuery.of(context).size.width;

    if (width < 800) {
      return FriendsActivitySection(
        friends: friendsDisplayData,
        isLoading: _isFriendsLoading,
        isEmpty: _friends.isEmpty,
      );
    }
    return _buildWelcomeHero();
  }

  Widget _buildWelcomeHero() {
    final hour = DateTime.now().hour;
    String greeting = 'Hello';
    if (hour < 5)
      greeting = 'Good evening';
    else if (hour < 12)
      greeting = 'Good morning';
    else if (hour < 18)
      greeting = 'Good afternoon';
    else
      greeting = 'Good evening';

    // Pick a featured item
    String title = 'Liked Songs';
    String subtitle = 'Your favorite tracks';
    String? imageUrl;
    String? playlistId;

    if (_sidebarPlaylists.isNotEmpty) {
      final index = DateTime.now().minute % _sidebarPlaylists.length;
      final pl = _sidebarPlaylists[index];
      title = pl['name'] as String? ?? 'Playlist';
      subtitle = '${pl['song_count'] ?? 0} songs • Playlist';
      playlistId = pl['id'] as String?;
      final urls = (pl['cover_image_urls'] as List?)?.cast<String>() ?? [];
      final imgs = (pl['cover_images'] as List?)?.cast<String>() ?? [];
      final effectiveCovers = urls.isNotEmpty ? urls : imgs;
      if (effectiveCovers.isNotEmpty) imageUrl = effectiveCovers.first;
    } else if (_likedSongs.isNotEmpty) {
      subtitle = '${_likedSongs.length} songs • Collection';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isCompact = width < 1000;

        // Dynamic sizing based on width
        final double bannerHeight = isCompact
            ? 210
            : 280; // Increased to prevent overflow
        final double greetingSize = isCompact ? 26 : 34;
        final double titleSize = isCompact ? 28 : 40;
        final double padding = isCompact ? 20 : 32;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, ${_userName ?? 'User'}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: greetingSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.6,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Welcome back',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            // Banner
            Container(
              height: bannerHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFF181818),
                image: imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(imageUrl),
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        colorFilter: ColorFilter.mode(
                          Colors.black.withOpacity(0.45),
                          BlendMode.darken,
                        ),
                      )
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    // Stronger gradient for text readability
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withOpacity(0.95),
                            Colors.black.withOpacity(0.6),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.45, 1.0],
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: EdgeInsets.all(padding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment:
                            MainAxisAlignment.center, // Centered vertically
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () {
                              if (playlistId != null) {
                                setState(() {
                                  _selectedPlaylistId = playlistId;
                                  _selectedArtistId = null;
                                });
                              } else {
                                _openLikedSongsPlaylist();
                              }
                            },
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 22,
                            ),
                            label: const Text(
                              'Explore Now',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, {VoidCallback? onViewAll}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View all',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalGrid() {
    // Calculate dynamic crossAxisCount (same as actual grid below)
    double width = MediaQuery.of(context).size.width;
    double contentWidth = width > 800 ? width - 250 : width;
    int crossAxisCount = (contentWidth / 220).floor();
    if (crossAxisCount < 2) crossAxisCount = 2;
    if (crossAxisCount > 8) crossAxisCount = 8;

    // Show skeleton while loading
    if (_isPlaylistsLoading && _sidebarPlaylists.isEmpty) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          crossAxisSpacing: 24,
          mainAxisSpacing: 24,
          childAspectRatio: 0.75,
        ),
        itemCount: 4, // Reasonable default for skeleton
        itemBuilder: (_, __) => const SkeletonPlaylistGridCard(),
      );
    }

    // No playlists - show empty state
    if (_sidebarPlaylists.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.queue_music, size: 64, color: Colors.grey[600]),
              const SizedBox(height: 16),
              Text(
                'No playlists yet',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _showCreatePlaylistDialog,
                icon: const Icon(Icons.add),
                label: const Text('Create Playlist'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
        childAspectRatio: 0.75,
      ),
      itemCount: min(_sidebarPlaylists.length, 8),
      itemBuilder: (context, index) {
        final pl = _sidebarPlaylists[index];
        final coverImages = (pl['cover_images'] as List?)?.cast<String>() ?? [];
        final coverImageUrls =
            (pl['cover_image_urls'] as List?)?.cast<String>() ?? [];
        final name = pl['name'] as String? ?? 'Playlist';
        final songCount = pl['song_count'] as int? ?? 0;
        final playlistId = pl['id'] as String? ?? '';

        // Prefer full URLs from API
        final effectiveCovers = coverImageUrls.isNotEmpty
            ? coverImageUrls
            : coverImages;

        return GestureDetector(
          onTap: () {
            // On large screens, use master-detail pattern
            final isLargeScreen = MediaQuery.of(context).size.width > 800;
            if (isLargeScreen) {
              setState(() {
                _selectedPlaylistId = playlistId;
                _selectedArtistId = null;
              });
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
                ),
              ).then((_) {
                _loadSidebarPlaylists();
                _loadData();
              });
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF181818),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: effectiveCovers.isNotEmpty
                        ? effectiveCovers.length >= 4
                              ? PlaylistCoverMosaic(
                                  coverImages: effectiveCovers.take(4).toList(),
                                )
                              : Image.network(
                                  effectiveCovers.first.startsWith('http')
                                      ? effectiveCovers.first
                                      : '${ApiService.baseUrl}/${effectiveCovers.first}',
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: Colors.grey[800],
                                    child: const Center(
                                      child: Icon(
                                        Icons.music_note,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                    ),
                                  ),
                                )
                        : Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors
                                      .primaries[index %
                                          Colors.primaries.length]
                                      .shade700,
                                  Colors
                                      .primaries[(index + 3) %
                                          Colors.primaries.length]
                                      .shade700,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.queue_music,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$songCount songs',
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSongList({int? limit}) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: limit != null
          ? (limit < _likedSongs.length ? limit : _likedSongs.length)
          : _likedSongs.length,
      itemBuilder: (context, index) {
        final song = _likedSongs[index];
        return _buildSongListItem(song, index);
      },
    );
  }

  Widget _buildSongListItem(dynamic song, int index) {
    bool isLargeScreen = MediaQuery.of(context).size.width > 800;

    return InkWell(
      onTap: () => _playSong(index),
      borderRadius: BorderRadius.circular(4),
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 0),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            if (isLargeScreen)
              SizedBox(
                width: 32,
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              ),

            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: (song['cover_url'] ?? song['cover_path']) != null
                  ? Image.network(
                      // Prefer cover_url (full URL from API)
                      song['cover_url'] ??
                          '${ApiService.baseUrl}/${song['cover_path']}',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 40,
                        height: 40,
                        color: Colors.grey[800],
                      ),
                    )
                  : Container(
                      width: 40,
                      height: 40,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note, color: Colors.white),
                    ),
            ),
            const SizedBox(width: 16),

            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song['title'] ?? 'Unknown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isLargeScreen)
                    Text(
                      song['artist_name'] ?? 'Unknown Artist',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            if (isLargeScreen) ...[
              Expanded(
                flex: 3,
                child: Text(
                  song['artist_name'] ?? 'Unknown Artist',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              Expanded(
                flex: 3,
                child: Text(
                  song['album_name'] ?? '--',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],

            if (isLargeScreen) ...[
              const Icon(Icons.favorite, color: Colors.white, size: 16),
              const SizedBox(width: 24),
            ],

            Text(
              _formatDuration(song['duration_ms'] ?? 0),
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),

            if (!isLargeScreen) ...[
              const SizedBox(width: 16),
              const Icon(Icons.more_vert, color: Colors.grey, size: 16),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(int ms) {
    if (ms == 0) return '--:--';
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildSidebarFriends() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'FRIENDS ACTIVITY',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FriendsScreen()),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View All',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Loading state
        if (_isFriendsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SkeletonFriendsActivity(itemCount: 3),
          )
        // Empty state
        else if (_friends.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('(っ◞‸◟c)', style: TextStyle(fontSize: 24)),
                  const SizedBox(height: 8),
                  Text(
                    "Such empty, much lonely",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        // Friends list with real-time activity
        else
          ...friendsDisplayData.map((friend) {
            final bool isLive = friend['status'] == 'live';
            final double progress = (friend['progress'] as double?) ?? 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isLive && progress > 0)
                          SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 2,
                              backgroundColor: Colors.transparent,
                              valueColor: const AlwaysStoppedAnimation(
                                Colors.white,
                              ),
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(2.5),
                          child: CircleAvatar(
                            backgroundImage: NetworkImage(
                              friend['image'] as String,
                            ),
                            backgroundColor: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friend['name'] as String,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (isLive) ...[
                              const _AnimatedEqualizer(
                                color: Colors.white,
                                size: 10,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                friend['song'] as String,
                                style: TextStyle(
                                  color: isLive
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off_rounded, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 12),
          Text('No liked songs yet', style: TextStyle(color: Colors.grey[400])),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _showUploadDialog,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white),
              foregroundColor: Colors.white,
            ),
            child: const Text('Upload Songs'),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = MediaQuery.of(context).size.width > 1000;

        if (!isLargeScreen) {
          return SizedBox(
            height: 420,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  ui.PointerDeviceKind.touch,
                  ui.PointerDeviceKind.mouse,
                },
              ),
              child: PageView(
                controller: PageController(viewportFraction: 0.92),
                padEnds: false,
                children: [
                  // Card 1: Liked Songs
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle(
                          'Liked Songs',
                          onViewAll: _openLikedSongsPlaylist,
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _isLoading
                              ? const SkeletonSongListCard(itemCount: 5)
                              : _likedSongs.isEmpty
                              ? _buildEmptyState()
                              : _buildMiniSongList(
                                  _likedSongs.take(5).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),

                  // Card 2: Recently Played (from analytics)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle(
                          'Recently Played',
                          onViewAll: _openRecentlyPlayedPlaylist,
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _isAnalyticsLoading
                              ? const SkeletonSongListCard(itemCount: 5)
                              : _recentlyPlayed.isEmpty
                              ? _buildRecentlyPlayedEmptyState()
                              : _buildRecentlyPlayedList(
                                  _recentlyPlayed.take(5).toList(),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Use a fixed height for both columns to ensure equal heights
        const double sectionHeight = 420; // 5 items * ~72px + title + padding

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Liked Songs Column
            Expanded(
              child: Container(
                height: sectionHeight,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(
                      'Liked Songs',
                      onViewAll: _openLikedSongsPlaylist,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _isLoading
                          ? const SkeletonSongListCard(itemCount: 5)
                          : _likedSongs.isEmpty
                          ? _buildEmptyState()
                          : _buildMiniSongList(_likedSongs.take(5).toList()),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 32),
            // Most Played Column (from analytics)
            Expanded(
              child: Container(
                height: sectionHeight,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF181818),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(
                      'Recently Played',
                      onViewAll: _openRecentlyPlayedPlaylist,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _isAnalyticsLoading
                          ? const SkeletonSongListCard(itemCount: 5)
                          : _recentlyPlayed.isEmpty
                          ? _buildRecentlyPlayedEmptyState()
                          : _buildRecentlyPlayedList(
                              _recentlyPlayed.take(5).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecentlyPlayedEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.headphones, size: 48, color: Colors.grey[600]),
          const SizedBox(height: 12),
          Text(
            'Play some songs to see your\nmost played tracks here!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[400]),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              setState(() => _isAnalyticsLoading = true);
              _loadAnalyticsData();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Refresh'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              backgroundColor: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Widget _buildRecentlyPlayedList(List<SongStats> songs) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: songs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final song = songs[index];
        return InkWell(
          onTap: () => _playRecentlyPlayed(index),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: (song.coverUrl ?? song.coverPath).isNotEmpty
                      ? Image.network(
                          // Use coverUrl (full URL with domain from DB) if available
                          song.coverUrl ??
                              '${ApiService.baseUrl}/${song.coverPath}',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[800],
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.music_note,
                              color: Colors.white54,
                            ),
                          ),
                        )
                      : Container(
                          color: Colors.grey[800],
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.music_note,
                            color: Colors.white54,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.artistName,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Play count badge or Time badge
                if (song.playCount > 0 || song.lastPlayedAt != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      song.playCount > 0
                          ? '${song.playCount} plays'
                          : _formatTimeAgo(song.lastPlayedAt!),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _playRecentlyPlayed(int index) {
    if (_recentlyPlayed.isEmpty || index >= _recentlyPlayed.length) return;

    final provider = Provider.of<MusicProvider>(context, listen: false);
    final songs = _recentlyPlayed
        .map(
          (s) => Song(
            id: s.songId,
            title: s.title,
            artist: s.artistName,
            filePath: '${ApiService.baseUrl}/stream/${s.songId}',
            // Use coverUrl (full URL from API) when available
            artworkPath:
                s.coverUrl ??
                (s.coverPath.isNotEmpty
                    ? '${ApiService.baseUrl}/${s.coverPath}'
                    : null),
            duration: Duration(
              milliseconds: s.totalListenedMs ~/ max(1, s.playCount),
            ),
          ),
        )
        .toList();

    provider.setPlaylist(
      songs,
      initialIndex: index,
      playlistName: 'Most Played',
    );
    _navigateToPlayer();
  }

  Future<void> _openRecentlyPlayedPlaylist() async {
    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.black,
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Syncing Recently Played...',
              style: TextStyle(color: Colors.black),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        duration: Duration(seconds: 2),
      ),
    );

    // Sync and get playlist ID
    final playlistId = await _analyticsService.syncRecentlyPlayedPlaylist();

    if (!mounted) return;

    if (playlistId == null) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No play history yet. Listen to some songs first!',
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.white,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    // On large screens, use master-detail pattern (keep sidebar visible)
    final isLargeScreen = MediaQuery.of(context).size.width > 800;
    if (isLargeScreen) {
      setState(() {
        _selectedPlaylistId = playlistId;
        _selectedArtistId = null;
      });
    } else {
      // On mobile, navigate to full screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlaylistDetailScreen(playlistId: playlistId),
        ),
      ).then((_) {
        // Refresh analytics when returning
        _loadAnalyticsData();
        _loadData();
      });
    }
  }

  void _openLikedSongsPlaylist() {
    // Find the Liked Songs system playlist from sidebar playlists
    final likedSongsPlaylist = _sidebarPlaylists.firstWhere(
      (p) => p['is_system'] == true,
      orElse: () => <String, dynamic>{},
    );

    if (likedSongsPlaylist.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Liked Songs playlist not found',
            style: TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.white,
        ),
      );
      return;
    }

    final playlistId = likedSongsPlaylist['id'] as String?;
    if (playlistId == null) return;

    // On large screens, use master-detail pattern (keep sidebar visible)
    final isLargeScreen = MediaQuery.of(context).size.width > 800;
    if (isLargeScreen) {
      setState(() {
        _selectedPlaylistId = playlistId;
        _selectedArtistId = null;
      });
    } else {
      // On mobile, navigate to full screen
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlaylistDetailScreen(playlistId: playlistId),
        ),
      ).then((_) {
        // Refresh data (liked status might have changed)
        _loadData();
        _loadSidebarPlaylists(); // Update counts
      });
    }
  }

  Widget _buildMiniSongList(List<dynamic> songs) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: songs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final song = songs[index];
        return InkWell(
          onTap: () => _playSong(
            index,
          ), // Note: indices might need adjustment if using different lists
          borderRadius: BorderRadius.circular(4),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: (song['cover_url'] ?? song['cover_path']) != null
                      ? Image.network(
                          // Use cover_url (full URL with domain from DB) if available
                          song['cover_url'] ??
                              '${ApiService.baseUrl}/${song['cover_path']}',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey[800],
                            width: 48,
                            height: 48,
                          ),
                        )
                      : Container(
                          color: Colors.grey[800],
                          width: 48,
                          height: 48,
                          child: const Icon(Icons.music_note),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song['title'] ?? 'Unknown',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song['artist_name'] ?? 'Unknown Artist',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDuration(song['duration_ms'] ?? 0),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(width: 12),
                const Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUploadDialog() async {
    await UploadSongSheet.show(
      context,
      onSuccess: () {
        _loadData();
        _loadSidebarPlaylists();
      },
    );
  }
}

class HeroCardItem {
  final String title;
  final String subtitle;
  final String imageUrl;
  final String? localImagePath;
  final String? assetPath; // For bundled assets
  final Color baseColor;

  const HeroCardItem({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    this.localImagePath,
    this.assetPath,
    required this.baseColor,
  });
}

class ExpandingHeroSection extends StatefulWidget {
  const ExpandingHeroSection({super.key});

  @override
  State<ExpandingHeroSection> createState() => _ExpandingHeroSectionState();
}

class _ExpandingHeroSectionState extends State<ExpandingHeroSection> {
  int _selectedIndex = 0;

  final List<HeroCardItem> _items = const [
    HeroCardItem(
      title: 'Khalid - Free Spirit',
      subtitle: 'The upcoming second studio album by Khalid',
      imageUrl: '',
      assetPath: 'assets/images/hero_free_spirit.png',
      baseColor: Color(0xFFCA9D42),
    ),
    HeroCardItem(
      title: 'Daily Mix 1',
      subtitle: 'Made for you',
      imageUrl: '',
      assetPath: 'assets/images/hero_daily_mix.png',
      baseColor: Color(0xFF1DB954),
    ),
    HeroCardItem(
      title: 'Top Hits',
      subtitle: 'Global favorites',
      imageUrl: '',
      assetPath: 'assets/images/hero_top_hits.png',
      baseColor: Color(0xFF1565C0),
    ),
    HeroCardItem(
      title: 'Chill Vibes',
      subtitle: 'Relax and unwind',
      imageUrl: '',
      assetPath: 'assets/images/hero_chill_vibes.png',
      baseColor: Color(0xFFE65100),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // If screen is small (mobile/tablet), use a PageView instead of the expanding row
        if (totalWidth < 800) {
          return SizedBox(
            height: 180, // Reduced height for sleeker look
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  ui.PointerDeviceKind.touch,
                  ui.PointerDeviceKind.mouse,
                },
              ),
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.85),
                padEnds: false, // Align first item to start (Left)
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(
                      right: 8.0,
                    ), // Gap between items
                    child: _buildBannerCard(_items[index]),
                  );
                },
              ),
            ),
          );
        }

        // Desktop: Expanding Row
        // Reduce height slightly for better medium screen fit
        return SizedBox(
          height: 280,
          child: Row(
            children: _items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isSelected = _selectedIndex == index;

              // Correctly account for the 8px margin (4L + 4R) per item
              final totalMargins = _items.length * 8.0;
              final availableWidth =
                  totalWidth -
                  totalMargins -
                  2.0; // Subtract 2.0 buffer for rounding safety

              double width;
              if (isSelected) {
                width = availableWidth * 0.55; // 55% for selected
              } else {
                width = (availableWidth * 0.45) / (_items.length - 1);
              }

              if (width < 0) width = 0;

              return _buildItemWidget(item, isSelected, width, index);
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildBannerCard(HeroCardItem item) {
    ImageProvider imageProvider;
    if (item.assetPath != null && item.assetPath!.isNotEmpty) {
      imageProvider = AssetImage(item.assetPath!);
    } else if (item.localImagePath != null && item.localImagePath!.isNotEmpty) {
      imageProvider = FileImage(File(item.localImagePath!));
    } else {
      imageProvider = NetworkImage(item.imageUrl);
    }

    return Container(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
              image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
            ),
          ),

          // Gradient Overlay
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.8),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),

          // Text Content (Bottom Left)
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.subtitle.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemWidget(
    HeroCardItem item,
    bool isSelected,
    double width,
    int index,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _selectedIndex = index),
      child: MouseRegion(
        onEnter: (_) => setState(() => _selectedIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutQuart,
          width: width,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isSelected
                ? Border.all(color: Colors.white, width: 2)
                : Border.all(color: Colors.transparent, width: 0),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                  color: item.baseColor.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Parallax Background
                Positioned.fill(
                  child: Container(
                    color: item.baseColor,
                    child: Stack(
                      children: [
                        AnimatedAlign(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.easeOutQuart,
                          alignment: isSelected
                              ? Alignment.center
                              : const Alignment(-0.5, 0.0),
                          child: SizedBox(
                            width: 1000,
                            height: double.infinity,
                            child:
                                (item.assetPath != null &&
                                    item.assetPath!.isNotEmpty)
                                ? Image.asset(
                                    item.assetPath!,
                                    fit: BoxFit.cover,
                                    color: Colors.black.withOpacity(
                                      isSelected ? 0.0 : 0.4,
                                    ),
                                    colorBlendMode: BlendMode.darken,
                                  )
                                : (item.localImagePath != null &&
                                      item.localImagePath!.isNotEmpty)
                                ? Image.file(
                                    File(item.localImagePath!),
                                    fit: BoxFit.cover,
                                    color: Colors.black.withOpacity(
                                      isSelected ? 0.0 : 0.4,
                                    ),
                                    colorBlendMode: BlendMode.darken,
                                  )
                                : Image.network(
                                    item.imageUrl,
                                    fit: BoxFit.cover,
                                    color: Colors.black.withOpacity(
                                      isSelected ? 0.3 : 0.6,
                                    ),
                                    colorBlendMode: BlendMode.darken,
                                    errorBuilder: (_, __, ___) =>
                                        Container(color: item.baseColor),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Content Layer
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Subtitle
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          child: Text(
                            isSelected ? item.subtitle.toUpperCase() : '',
                          ),
                        ),

                        SizedBox(height: isSelected ? 8 : 0),

                        // Title
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSelected ? 32 : 18,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                          maxLines: isSelected ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          child: Text(item.title),
                        ),

                        // Play Button
                        if (isSelected) ...[
                          const SizedBox(height: 16),
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 400),
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 10 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DB954),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
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
}

class FriendsActivitySection extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final bool isLoading;
  final bool isEmpty;

  const FriendsActivitySection({
    super.key,
    required this.friends,
    required this.isLoading,
    required this.isEmpty,
  });

  @override
  State<FriendsActivitySection> createState() => _FriendsActivitySectionState();
}

class _FriendsActivitySectionState extends State<FriendsActivitySection> {
  // -1 means nothing is expanded
  int _expandedIndex = -1;

  // Timer for smooth time interpolation (just triggers rebuild)
  Timer? _interpolationTimer;

  // Track baseline for each friend: when we received the data and what position it was
  Map<String, int> _baselineTimestamp =
      {}; // When we received the server update
  Map<String, int> _baselinePosition = {}; // Server position at that time

  @override
  void initState() {
    super.initState();
    _startInterpolation();
  }

  @override
  void dispose() {
    _interpolationTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(FriendsActivitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When new data comes in, update our baseline
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final friend in widget.friends) {
      final id = friend['id'] as String;
      final positionMs = friend['positionMs'] as int? ?? 0;
      final isLive = friend['status'] == 'live';

      if (isLive && positionMs > 0) {
        // Only update baseline if we have new data (position changed)
        final oldBaseline = _baselinePosition[id] ?? 0;
        if (positionMs != oldBaseline) {
          _baselineTimestamp[id] = now;
          _baselinePosition[id] = positionMs;
        }
      } else {
        // Not live anymore, clear interpolation
        _baselineTimestamp.remove(id);
        _baselinePosition.remove(id);
      }
    }
  }

  void _startInterpolation() {
    _interpolationTimer?.cancel();
    // Just trigger rebuilds every second for smooth time updates
    _interpolationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      // Check if any friend is live and needs interpolation
      final hasLiveFriends = widget.friends.any((f) => f['status'] == 'live');
      if (hasLiveFriends) {
        setState(() {});
      }
    });
  }

  // Get interpolated position for a friend (calculated on-demand)
  int _getInterpolatedPosition(String id, int serverPosition, int durationMs) {
    final baseline = _baselinePosition[id];
    final timestamp = _baselineTimestamp[id];

    if (baseline == null || timestamp == null) {
      return serverPosition;
    }

    // Calculate how much time has passed since we got the server update
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - timestamp;

    // Interpolated position = baseline + elapsed time
    final interpolated = baseline + elapsed;

    // Don't exceed duration
    if (durationMs > 0 && interpolated > durationMs) {
      return durationMs;
    }

    return interpolated;
  }

  // Get interpolated progress (0.0 to 1.0) for smooth progress ring
  double _getInterpolatedProgress(
    String id,
    double serverProgress,
    int durationMs,
  ) {
    if (durationMs <= 0) return serverProgress;
    final interpolatedPos = _getInterpolatedPosition(id, 0, durationMs);
    return (interpolatedPos / durationMs).clamp(0.0, 1.0);
  }

  // Get display friends from props
  List<Map<String, dynamic>> get displayFriends => widget.friends;

  // Format milliseconds to mm:ss
  String _formatTime(int ms) {
    if (ms <= 0) return '--:--';
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Friends Activity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              );
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'View All',
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show loading with skeleton animation
    if (widget.isLoading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          // Horizontal row of circular avatars (matching actual friends display)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                // Avatar circles - spread across full width
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    4,
                    (index) => const SkeletonLoader(
                      width: 60,
                      height: 60,
                      isCircle: true,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Name labels below avatars
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    4,
                    (index) => SizedBox(
                      width: 60,
                      child: Center(
                        child: SkeletonLoader(
                          width: 35 + (index * 5) % 15,
                          height: 10,
                          borderRadius: 4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show empty state
    if (widget.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text('( ´•̥̥̥ω•̥̥̥` )', style: TextStyle(fontSize: 32)),
                const SizedBox(height: 12),
                Text(
                  "No fwiends listening rn...",
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  "add some or stay lonely ig 💔",
                  style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),

        LayoutBuilder(
          builder: (context, constraints) {
            final double totalWidth = constraints.maxWidth;

            // Dimensions
            const double circleSize = 60.0;
            const double expandedGap = 8.0;
            const double maxCollapsedGap =
                16.0; // Maximum gap between avatars when collapsed

            // If all collapsed, calculate gap to distribute evenly across width
            // Formula: (Total - (N * Width)) / (N - 1), but clamped to maxCollapsedGap
            final double calculatedGap = displayFriends.length > 1
                ? (totalWidth - (displayFriends.length * circleSize)) /
                      (displayFriends.length - 1)
                : 0;
            final double collapsedGap = calculatedGap.clamp(0, maxCollapsedGap);

            // Determine current gap based on state
            final double currentGap = _expandedIndex == -1
                ? collapsedGap
                : expandedGap;

            // Calculate width for the single expanded item
            // Available = Total - (N-1 collapsed items) - (Total Gaps)
            final double expandedWidth =
                totalWidth -
                ((displayFriends.length - 1) * circleSize) -
                ((displayFriends.length - 1) * expandedGap);

            return Column(
              children: [
                SizedBox(
                  height: circleSize,
                  child: Row(
                    children: List.generate(displayFriends.length, (index) {
                      final bool isExpanded = index == _expandedIndex;
                      final friend = displayFriends[index];
                      final bool isLive = friend['status'] == 'live';
                      // Use interpolated progress for smooth animation
                      final double progress = _getInterpolatedProgress(
                        friend['id'] as String,
                        (friend['progress'] as double?) ?? 0.0,
                        friend['durationMs'] as int? ?? 0,
                      );

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_expandedIndex == index) {
                              _expandedIndex = -1; // Collapse if clicking same
                            } else {
                              _expandedIndex = index; // Expand new
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          // Width is either expanded width OR fixed circle size
                          width: isExpanded ? expandedWidth : circleSize,
                          // Animate margin to smooth out the distribution change
                          margin: EdgeInsets.only(
                            right: index < displayFriends.length - 1
                                ? currentGap
                                : 0,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF202020),
                            borderRadius: BorderRadius.circular(circleSize / 2),
                            border: isExpanded && isLive
                                ? Border.all(
                                    color: const Color(
                                      0xFF1DB954,
                                    ).withOpacity(0.3),
                                  )
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(circleSize / 2),
                            child: Stack(
                              alignment: Alignment.centerLeft,
                              children: [
                                // Glassmorphism background with album art (only when expanded and live)
                                if (isExpanded && isLive)
                                  Positioned.fill(
                                    child: Stack(
                                      children: [
                                        // Blurred album art background
                                        Positioned.fill(
                                          child: Image.network(
                                            (friend['albumCover'] as String?) ??
                                                friend['image'] as String,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox(),
                                          ),
                                        ),
                                        // Dark overlay for glass effect
                                        Positioned.fill(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                                colors: [
                                                  Colors.black.withOpacity(
                                                    0.85,
                                                  ),
                                                  Colors.black.withOpacity(0.6),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Frosted glass overlay
                                        Positioned.fill(
                                          child: BackdropFilter(
                                            filter: ui.ImageFilter.blur(
                                              sigmaX: 20,
                                              sigmaY: 20,
                                            ),
                                            child: Container(
                                              color: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                Row(
                                  // Center content if collapsed (circle), Start if expanded
                                  mainAxisAlignment: isExpanded
                                      ? MainAxisAlignment.start
                                      : MainAxisAlignment.center,
                                  children: [
                                    // Avatar Section
                                    SizedBox(
                                      width: circleSize,
                                      height: circleSize,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Progress Ring
                                          if (isLive && progress > 0)
                                            SizedBox(
                                              width: circleSize - 4,
                                              height: circleSize - 4,
                                              child: CircularProgressIndicator(
                                                value: progress,
                                                strokeWidth: 2.5,
                                                backgroundColor: Colors.white10,
                                                valueColor:
                                                    const AlwaysStoppedAnimation(
                                                      Color(0xFF1DB954),
                                                    ),
                                                strokeCap: StrokeCap.round,
                                              ),
                                            ),

                                          CircleAvatar(
                                            radius: (circleSize - 14) / 2,
                                            backgroundImage: NetworkImage(
                                              friend['image'] as String,
                                            ),
                                            backgroundColor: Colors.grey[800],
                                          ),

                                          // "Live" indicator overlay when NOT expanded (small icon on avatar)
                                          if (isLive && !isExpanded)
                                            Container(
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(
                                                  0.5,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              width: circleSize - 14,
                                              height: circleSize - 14,
                                              child: const Center(
                                                child: _AnimatedEqualizer(
                                                  color: Color(0xFF1DB954),
                                                  size: 14,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),

                                    // Text Info (only visible when expanded)
                                    if (isExpanded)
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 4.0,
                                            right: 12.0,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                friend['name'] as String,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  if (isLive) ...[
                                                    const _AnimatedEqualizer(
                                                      color: Color(0xFF1DB954),
                                                      size: 12,
                                                    ),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      friend['song'] as String,
                                                      style: TextStyle(
                                                        color: isLive
                                                            ? Colors.white70
                                                            : Colors.grey[400],
                                                        fontSize: 12,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  // Show time for live friends (interpolated for smooth updates)
                                                  if (isLive &&
                                                      (friend['positionMs']
                                                              as int) >
                                                          0) ...[
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      _formatTime(
                                                        _getInterpolatedPosition(
                                                          friend['id']
                                                              as String,
                                                          friend['positionMs']
                                                              as int,
                                                          friend['durationMs']
                                                                  as int? ??
                                                              0,
                                                        ),
                                                      ),
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF1DB954,
                                                        ),
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // Usernames Row (Only visible when NO item is expanded)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _expandedIndex == -1 ? 1.0 : 0.0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: List.generate(displayFriends.length, (index) {
                        return Container(
                          width: circleSize,
                          margin: EdgeInsets.only(
                            right: index < displayFriends.length - 1
                                ? collapsedGap
                                : 0,
                          ),
                          child: Text(
                            (displayFriends[index]['name'] as String)
                                .split(' ')
                                .first,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                // Height animation for the labels is tricky, simpler to just fade them out and zero height?
                // For now, let's keep the space but fade out text to avoid layout jumps.
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AnimatedEqualizer extends StatefulWidget {
  final Color color;
  final double size;

  const _AnimatedEqualizer({required this.color, required this.size});

  @override
  State<_AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<_AnimatedEqualizer>
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
              // Generate oscillating heights
              final t = _controller.value;
              final offset = index * 2.6;
              // Mix sine waves for varied movement
              final val = sin((t * 2 * pi * (1.0 + index * 0.5)) + offset);
              final heightFactor = 0.3 + 0.6 * (0.5 + 0.5 * val);

              return Container(
                width: widget.size / 4.0,
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

/// Smaller equalizer bar for sidebar playlist items
class _SidebarEqualizerBar extends StatefulWidget {
  final int index;

  const _SidebarEqualizerBar({required this.index});

  @override
  State<_SidebarEqualizerBar> createState() => _SidebarEqualizerBarState();
}

class _SidebarEqualizerBarState extends State<_SidebarEqualizerBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 300 + (widget.index * 80)),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 3,
      end: 10,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    Future.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 2,
          height: _animation.value,
          margin: const EdgeInsets.symmetric(horizontal: 0.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}

/// Mini equalizer bar for liked songs list
class _MiniEqualizerBar extends StatefulWidget {
  final int index;
  const _MiniEqualizerBar({required this.index});

  @override
  State<_MiniEqualizerBar> createState() => _MiniEqualizerBarState();
}

class _MiniEqualizerBarState extends State<_MiniEqualizerBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 400 + (widget.index * 100)),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 3,
          height: 6 + (_controller.value * 8),
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      },
    );
  }
}

/// Wrapper to trigger a callback when the widget is initialized
class _LifecycleWrapper extends StatefulWidget {
  final VoidCallback onInit;
  final Widget child;

  const _LifecycleWrapper({required this.onInit, required this.child});

  @override
  State<_LifecycleWrapper> createState() => _LifecycleWrapperState();
}

class _LifecycleWrapperState extends State<_LifecycleWrapper> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
