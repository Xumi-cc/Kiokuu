import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:audio_session/audio_session.dart' as as_lib;
import '../models/song.dart';
import '../services/audio_handler.dart';
import '../services/discord_rpc_service.dart';
import '../services/friends_service.dart';
import '../services/analytics_service.dart';
import '../services/playback_state_service.dart';
import '../services/offline_storage_service.dart';
import '../services/api_service.dart';

enum RepeatMode { off, all, one }

class MusicProvider extends ChangeNotifier {
  final Player _player;
  final MediaKitAudioHandler? _audioHandler;
  List<Song> _playlist = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isShuffled = false;
  List<int> _shuffleIndices = [];
  RepeatMode _repeatMode = RepeatMode.off;
  bool _isLoading = false;
  double _volume = 100.0; // Volume 0.0 to 100.0
  String? _currentPlaylistId; // Track which playlist is currently playing
  String? _currentPlaylistName; // Name of the currently playing playlist

  // Dynamic UI Properties
  Color? _backgroundColor;
  String _deviceName = 'This Device';
  as_lib.AudioDeviceType? _deviceType;

  // Cached auth token to avoid slow secure storage reads
  String? _cachedAuthToken;
  static const _storage = FlutterSecureStorage();

  // Prefetching: secondary player for next song
  Player? _prefetchPlayer;
  int? _prefetchedIndex;
  bool _isPrefetching = false;
  bool _usingPrefetchPlayer = false; // Track which player is active

  // Stream subscriptions for proper cleanup
  final List<StreamSubscription> _mainPlayerSubscriptions = [];
  List<StreamSubscription> _prefetchPlayerSubscriptions = [];

  // Flag to prevent callbacks after disposal (hot restart fix)
  bool _disposed = false;

  // Activity broadcasting for friends
  final _friendsService = FriendsService();

  // Analytics tracking
  final _analyticsService = AnalyticsService();
  Timer? _activityTimer;

  // Playback state persistence
  final _playbackStateService = PlaybackStateService();
  Timer? _saveStateTimer;
  String _deviceId = '';

  // Loading timeout to prevent stuck loading screen in background
  Timer? _loadingTimeoutTimer;
  static const _loadingTimeout = Duration(seconds: 30);

  // Retry mechanism for background fetch failures
  int? _pendingRetryIndex;
  bool _isInBackground = false;

  // API service for subscription checks
  final _apiService = ApiService();

  // Callback for subscription required errors (to show snackbar in UI)
  void Function(String message)? onSubscriptionRequired;

  // Get the currently active player
  Player get _activePlayer => _usingPrefetchPlayer && _prefetchPlayer != null
      ? _prefetchPlayer!
      : _player;

  // Getters
  List<Song> get playlist => _playlist;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration {
    // Prefer song metadata duration (more accurate for HLS streams)
    final song = currentSong;
    if (song != null && song.duration.inMilliseconds > 0) {
      return song.duration;
    }
    // Fallback to player-reported duration
    return _totalDuration;
  }

  bool get isShuffled => _isShuffled;
  RepeatMode get repeatMode => _repeatMode;
  bool get isLoading => _isLoading;
  double get volume => _volume;
  Color? get backgroundColor => _backgroundColor;
  String get deviceName => _deviceName;
  as_lib.AudioDeviceType? get deviceType => _deviceType;
  String? get currentPlaylistId => _currentPlaylistId;
  String? get currentPlaylistName => _currentPlaylistName;
  Song? get currentSong =>
      _currentIndex >= 0 && _currentIndex < _playlist.length
      ? _playlist[_currentIndex]
      : null;

  // Override to prevent crashes during hot restart
  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  MusicProvider(this._player, this._audioHandler) {
    _init();
    _setupAudioHandler();
    _fetchDeviceName();
    _cacheAuthToken();
    _setupAutoSave();
    _generateDeviceId();
    _loadSavedVolume(); // Restore volume from last session
  }

  // Cache auth token on startup for faster song switching
  Future<void> _cacheAuthToken() async {
    _cachedAuthToken = await _storage.read(key: 'auth_token');
  }

  // Refresh cached token (call after login)
  Future<void> refreshAuthToken() async {
    _cachedAuthToken = await _storage.read(key: 'auth_token');
  }

  void _setupAudioHandler() {
    if (_audioHandler != null) {
      // Use _activePlayer getter to ensure we always operate on the current player
      _audioHandler!.onPlay = () async => await _activePlayer.play();
      _audioHandler!.onPause = () async => await _activePlayer.pause();
      _audioHandler!.onSkipToNext = () async => await playNext();
      _audioHandler!.onSkipToPrevious = () async => await playPrevious();
      _audioHandler!.onSeek = (position) async =>
          await _activePlayer.seek(position);
    }
  }

  /// Handle app lifecycle changes for background fetch retry
  /// Call this from main.dart's WidgetsBindingObserver.didChangeAppLifecycleState
  void onAppLifecycleStateChange(AppLifecycleState state) {
    if (_disposed) return;

    final wasInBackground = _isInBackground;
    _isInBackground =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden;

    debugPrint(
      '📱 App lifecycle: $state (wasInBackground: $wasInBackground, isNow: $_isInBackground)',
    );

    // Retry pending song fetch when coming back to foreground
    if (wasInBackground && !_isInBackground && _pendingRetryIndex != null) {
      final retryIndex = _pendingRetryIndex!;
      _pendingRetryIndex = null;
      debugPrint('🔄 Retrying pending song fetch for index $retryIndex');
      playSongAtIndex(retryIndex);
    }

    // If we're stuck loading and coming back to foreground, restart the fetch
    if (wasInBackground &&
        !_isInBackground &&
        _isLoading &&
        _currentIndex >= 0) {
      debugPrint(
        '⚠️ App returned from background while loading - restarting fetch',
      );
      // Give a moment for network to stabilize, then retry
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_isLoading && !_disposed && _currentIndex >= 0) {
          playSongAtIndex(_currentIndex);
        }
      });
    }
  }

  void _init() {
    // Listen to player state changes
    _mainPlayerSubscriptions.add(
      _player.stream.playing.listen((playing) {
        if (_disposed) return; // Guard against hot restart
        debugPrint(
          '🎮 Main player state changed: playing=$playing, usingPrefetch=$_usingPrefetchPlayer',
        );
        if (!_usingPrefetchPlayer) {
          _isPlaying = playing;
          notifyListeners();

          // Broadcast activity to friends
          if (playing) {
            _startActivityBroadcast();
          } else {
            _stopActivityBroadcast();
          }
        }
      }),
    );

    // Listen to position changes
    _mainPlayerSubscriptions.add(
      _player.stream.position.listen((position) {
        if (_disposed) return; // Guard against hot restart
        if (!_usingPrefetchPlayer) {
          _currentPosition = position;

          // Clear loading when we get actual position updates (after first second)
          if (_isLoading && position.inMilliseconds > 100) {
            _loadingTimeoutTimer?.cancel();
            _isLoading = false;
          }

          notifyListeners();

          // Prefetch next song when we're 10 seconds in
          if (position.inSeconds >= 10 &&
              !_isPrefetching &&
              _prefetchedIndex == null) {
            _prefetchNextSong();
          }
        }
      }),
    );

    // Listen to duration changes
    _mainPlayerSubscriptions.add(
      _player.stream.duration.listen((duration) {
        if (_disposed) return; // Guard against hot restart
        if (!_usingPrefetchPlayer) {
          _totalDuration = duration;

          // Clear loading when we get valid duration (audio is ready)
          if (_isLoading && duration.inMilliseconds > 0) {
            debugPrint(
              '✅ Loading complete - duration received: ${duration.inSeconds}s',
            );
            _loadingTimeoutTimer?.cancel();
            _isLoading = false;
          }

          notifyListeners();
        }
      }),
    );

    // Listen to completion
    _mainPlayerSubscriptions.add(
      _player.stream.completed.listen((completed) {
        if (_disposed) return; // Guard against hot restart
        if (completed && !_usingPrefetchPlayer) {
          _handleSongCompleted();
        }
      }),
    );
  }

  void _handleSongCompleted() {
    if (_repeatMode == RepeatMode.one) {
      _activePlayer.seek(Duration.zero);
      _activePlayer.play();
    } else if (_repeatMode == RepeatMode.all) {
      playNext();
    } else {
      // If not repeating, and not shuffled, stop at the end of the playlist
      if (!_isShuffled && _currentIndex == _playlist.length - 1) {
        _activePlayer.pause();
        _activePlayer.seek(Duration.zero);
        _isPlaying = false;
        notifyListeners();
      } else {
        playNext();
      }
    }
  }

  // Get the next song index based on shuffle/repeat mode
  int? _getNextIndex() {
    if (_playlist.isEmpty) return null;

    if (_isShuffled) {
      if (_shuffleIndices.isEmpty) return null;
      int currentShufflePos = _shuffleIndices.indexOf(_currentIndex);
      if (currentShufflePos >= _shuffleIndices.length - 1) {
        if (_repeatMode == RepeatMode.all) {
          return _shuffleIndices[0];
        }
        return null;
      }
      return _shuffleIndices[currentShufflePos + 1];
    } else {
      if (_currentIndex >= _playlist.length - 1) {
        if (_repeatMode == RepeatMode.all) {
          return 0;
        }
        return null;
      }
      return _currentIndex + 1;
    }
  }

  // Prefetch the next song in background
  Future<void> _prefetchNextSong() async {
    final nextIndex = _getNextIndex();
    if (nextIndex == null || nextIndex == _prefetchedIndex) return;

    _isPrefetching = true;

    try {
      final song = _playlist[nextIndex];

      // Check for offline file first, but verify source matches (HD upgrade check)
      final offlineService = OfflineStorageService();
      final offlineSong = await offlineService.getSong(song.id);

      String mediaUrl;
      Map<String, String>? headers;

      String? localPath;
      if (offlineSong != null) {
        // Check if the song has been upgraded to HD on the server
        if (song.source != offlineSong.source && song.source == 'tidal') {
          debugPrint('⬆️ Prefetch: HD upgrade detected for ${song.title}');
          localPath = null;
        } else {
          localPath = offlineSong.localPath;
        }
      }

      if (localPath != null) {
        // Use local offline file
        mediaUrl = localPath;
        headers = null;
        debugPrint('📦 Prefetching offline: ${song.title}');
      } else {
        // Stream from server with prefetch flag
        mediaUrl = song.filePath.contains('?')
            ? '${song.filePath}&prefetch=true'
            : '${song.filePath}?prefetch=true';
        headers = _cachedAuthToken != null
            ? {'Authorization': 'Bearer $_cachedAuthToken'}
            : null;
        debugPrint('🌐 Prefetching stream: ${song.title}');
      }

      if (_usingPrefetchPlayer) {
        // Currently playing from _prefetchPlayer, so use _player for next prefetch
        // Don't dispose _prefetchPlayer since it's actively playing!
        await _player.open(Media(mediaUrl, httpHeaders: headers), play: false);
        _prefetchedIndex = nextIndex;
        debugPrint('✅ Prefetched song (to main player): ${song.title}');
      } else {
        // Currently playing from _player, so use _prefetchPlayer for next prefetch
        await _prefetchPlayer?.dispose();
        _prefetchPlayer = Player();

        await _prefetchPlayer!.open(
          Media(mediaUrl, httpHeaders: headers),
          play: false,
        );
        _prefetchedIndex = nextIndex;
        debugPrint('✅ Prefetched song (to prefetch player): ${song.title}');
      }
    } catch (e) {
      debugPrint('Error prefetching: $e');
      if (!_usingPrefetchPlayer) {
        _prefetchPlayer?.dispose();
        _prefetchPlayer = null;
      }
      _prefetchedIndex = null;
    }

    _isPrefetching = false;
  }

  // Clear prefetch state
  void _clearPrefetch() {
    // Cancel subscriptions first to prevent callbacks on disposed player
    for (var sub in _prefetchPlayerSubscriptions) {
      sub.cancel();
    }
    _prefetchPlayerSubscriptions.clear();

    _prefetchPlayer?.dispose();
    _prefetchPlayer = null;
    _prefetchedIndex = null;
    _isPrefetching = false;
  }

  Future<void> _fetchDeviceName() async {
    // Skip on web - Platform APIs not available
    if (kIsWeb) {
      _deviceName = 'Web Browser';
      notifyListeners();
      return;
    }

    // Initial fetch of host/model name as fallback
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceName = iosInfo.name;
      } else {
        _deviceName = Platform.localHostname;
      }
      notifyListeners();

      // Now try to get the actual audio output device
      await _initAudioSession();
    } catch (e) {
      debugPrint('Error fetching device name: $e');
    }
  }

  // Track if we were playing before an interruption (to resume after)
  bool _wasPlayingBeforeInterruption = false;

  Future<void> _initAudioSession() async {
    try {
      final session = await as_lib.AudioSession.instance;
      await session.configure(const as_lib.AudioSessionConfiguration.music());

      // Initial check
      await _updateAudioDeviceName(session);

      // Listen for device changes
      session.devicesChangedEventStream.listen((event) {
        _updateAudioDeviceName(session);
      });

      // Listen for audio interruptions (phone calls, other apps taking audio focus)
      session.interruptionEventStream.listen((event) {
        if (_disposed) return;

        if (event.begin) {
          // Interruption started (e.g., incoming call)
          debugPrint('🔇 Audio interruption started: ${event.type}');
          _wasPlayingBeforeInterruption = _isPlaying;
          if (_isPlaying) {
            _activePlayer.pause();
          }
        } else {
          // Interruption ended (e.g., call ended)
          debugPrint('🔊 Audio interruption ended: ${event.type}');
          // Only resume if we were playing before and it's safe to do so
          if (_wasPlayingBeforeInterruption &&
              event.type != as_lib.AudioInterruptionType.unknown) {
            _activePlayer.play();
          }
          _wasPlayingBeforeInterruption = false;
        }
      });

      // Handle becoming noisy (e.g., headphones unplugged)
      session.becomingNoisyEventStream.listen((_) {
        if (_disposed) return;
        debugPrint('🔇 Audio becoming noisy (headphones unplugged?)');
        if (_isPlaying) {
          _activePlayer.pause();
        }
      });
    } catch (e) {
      debugPrint('Error initializing audio session: $e');
    }
  }

  Future<void> _updateAudioDeviceName(as_lib.AudioSession session) async {
    try {
      final devices = await session.getDevices();
      // Filter for output devices
      final outputs = devices.where((d) => d.isOutput).toList();

      // Priority: Bluetooth > Wired > Built-in
      as_lib.AudioDevice? bestDevice;

      try {
        bestDevice = outputs.firstWhere(
          (d) =>
              d.type == as_lib.AudioDeviceType.bluetoothA2dp ||
              d.type == as_lib.AudioDeviceType.bluetoothSco ||
              d.type == as_lib.AudioDeviceType.bluetoothLe,
        );
      } catch (_) {
        try {
          bestDevice = outputs.firstWhere(
            (d) =>
                d.type == as_lib.AudioDeviceType.wiredHeadset ||
                d.type == as_lib.AudioDeviceType.wiredHeadphones,
          );
        } catch (_) {
          try {
            bestDevice = outputs.firstWhere(
              (d) => d.type == as_lib.AudioDeviceType.builtInSpeaker,
            );
          } catch (_) {
            if (outputs.isNotEmpty) {
              bestDevice = outputs.first;
            }
          }
        }
      }

      if (bestDevice != null) {
        // On Android, name might be generic like "Headphones" or specific like "Realfit F3"
        // depending on permissions and OS version.
        _deviceType = bestDevice.type;
        if (bestDevice.name.isNotEmpty) {
          _deviceName = bestDevice.name;
        } else {
          // Fallback to type description if name is empty
          _deviceName = _getDeviceTypeDescription(bestDevice.type);
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating audio device name: $e');
    }
  }

  String _getDeviceTypeDescription(as_lib.AudioDeviceType type) {
    switch (type) {
      case as_lib.AudioDeviceType.bluetoothA2dp:
      case as_lib.AudioDeviceType.bluetoothSco:
      case as_lib.AudioDeviceType.bluetoothLe:
        return 'Bluetooth Audio';
      case as_lib.AudioDeviceType.wiredHeadset:
      case as_lib.AudioDeviceType.wiredHeadphones:
        return 'Wired Headphones';
      case as_lib.AudioDeviceType.builtInSpeaker:
        return 'Phone Speaker';
      default:
        return 'Audio Device';
    }
  }

  Future<void> _updatePalette() async {
    final song = currentSong;
    if (song?.artworkPath != null) {
      try {
        debugPrint('Generating palette for ${song!.title}...');

        ImageProvider imageProvider;
        if (song.artworkPath!.startsWith('http')) {
          // Network image
          imageProvider = ResizeImage(
            NetworkImage(song.artworkPath!),
            width: 100,
          );
        } else {
          // Local file
          imageProvider = ResizeImage(
            FileImage(File(song.artworkPath!)),
            width: 100,
          );
        }

        final paletteGenerator =
            await PaletteGenerator.fromImageProvider(
              imageProvider,
              maximumColorCount: 20,
            ).timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                throw TimeoutException('Palette generation timed out');
              },
            );

        // Prefer dominant color, fallback to muted/vibrant
        _backgroundColor =
            paletteGenerator.dominantColor?.color ??
            paletteGenerator.mutedColor?.color ??
            paletteGenerator.vibrantColor?.color;
        debugPrint('Palette generated: $_backgroundColor');
      } catch (e) {
        debugPrint('Error generating palette: $e');
        _backgroundColor = null;
      }
    } else {
      _backgroundColor = null;
    }
    notifyListeners();
  }

  // Start broadcasting activity to friends
  void _startActivityBroadcast() {
    debugPrint('🎵 Starting activity broadcast');
    _activityTimer?.cancel();
    // Send update every 5 seconds while playing
    _activityTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isPlaying && currentSong != null) {
        _sendActivityUpdate();
      }
    });
    // Send initial update immediately
    _sendActivityUpdate();
  }

  // Stop broadcasting activity
  void _stopActivityBroadcast() {
    debugPrint('⏸️ Stopping activity broadcast');
    _activityTimer?.cancel();
    _activityTimer = null;
    // Clear activity when paused/stopped
    _friendsService.clearActivity();
    // Clear Discord Rich Presence
    DiscordRpcService.instance.clearActivity();
  }

  // Send current activity to server
  Future<void> _sendActivityUpdate() async {
    final song = currentSong;
    if (song == null) {
      debugPrint('⚠️ Activity update skipped - no current song');
      return;
    }

    debugPrint('📡 Sending activity: ${song.title} by ${song.artist}');

    // Update Discord Rich Presence
    DiscordRpcService.instance.updateNowPlaying(
      title: song.title,
      artist: song.artist,
      album: song.album,
      albumArtUrl: song.artworkPath,
      isPlaying: _isPlaying,
      durationMs: _totalDuration.inMilliseconds,
      positionMs: _currentPosition.inMilliseconds,
    );

    try {
      // Determine context based on what's playing
      String? context;
      if (_currentPlaylistId != null) {
        context = 'playlist';
      } else {
        context = 'library';
      }

      // Convert repeat mode to string
      String repeatModeStr;
      switch (_repeatMode) {
        case RepeatMode.one:
          repeatModeStr = 'one';
          break;
        case RepeatMode.all:
          repeatModeStr = 'all';
          break;
        default:
          repeatModeStr = 'off';
      }

      final success = await _friendsService.updateActivity(
        songId: song.id,
        songTitle: song.title,
        artistName: song.artist,
        albumCover: song.artworkPath,
        progress: _totalDuration.inMilliseconds > 0
            ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
            : 0.0,
        durationMs: _totalDuration.inMilliseconds,
        positionMs: _currentPosition.inMilliseconds,
        isPlaying: _isPlaying,
        // Analytics context
        playlistId: _currentPlaylistId,
        context: context,
        shuffleOn: _isShuffled,
        repeatMode: repeatModeStr,
      );
      debugPrint('📡 Activity sent: ${success ? "✅" : "❌"}');
    } catch (e) {
      debugPrint('❌ Error sending activity: $e');
    }
  }

  // Set playlist from API
  void setPlaylist(
    List<Song> songs, {
    int initialIndex = 0,
    String? playlistId,
    String? playlistName,
    bool play = true,
  }) {
    _playlist = songs;
    _currentPlaylistId = playlistId;
    _currentPlaylistName = playlistName;
    if (_isShuffled) {
      _generateShuffleIndices();
    } else {
      _shuffleIndices.clear();
    }

    if (initialIndex >= 0 && initialIndex < _playlist.length) {
      playSongAtIndex(initialIndex, play: play);
    } else {
      _currentIndex = -1;
      _player.stop();
      notifyListeners();
    }
  }

  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 100.0);
    notifyListeners();
    await _player.setVolume(_volume);
    if (_prefetchPlayer != null) {
      await _prefetchPlayer!.setVolume(_volume);
    }
    // Save volume locally for persistence across restarts
    await _storage.write(key: 'volume', value: _volume.toString());
  }

  /// Load saved volume from local storage
  Future<void> _loadSavedVolume() async {
    try {
      final savedVolume = await _storage.read(key: 'volume');
      if (savedVolume != null) {
        final volume = double.tryParse(savedVolume);
        if (volume != null) {
          _volume = volume.clamp(0.0, 100.0);
          await _player.setVolume(_volume);
          debugPrint('🔊 Restored volume: $_volume');
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error loading saved volume: $e');
    }
  }

  // Add songs to playlist
  Future<void> addSongsToPlaylist() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp3',
          'flac',
          'wav',
          'ogg',
          'm4a',
          'aac',
          'opus',
          'wma',
          'm3u8',
          'm3u',
        ],
        allowMultiple: true,
      );

      if (result != null) {
        final tempDir = await getTemporaryDirectory();

        for (var file in result.files) {
          if (file.path != null) {
            String title = _extractTitle(file.name);
            String artist = 'Unknown Artist';
            String? album;
            String? artworkPath;
            Duration duration = Duration.zero;

            try {
              final metadata = readMetadata(File(file.path!), getImage: true);

              if (metadata.title != null && metadata.title!.isNotEmpty) {
                title = metadata.title!;
              }

              if (metadata.artist != null && metadata.artist!.isNotEmpty) {
                artist = metadata.artist!;
              }

              if (metadata.album != null) {
                album = metadata.album;
              }

              if (metadata.duration != null) {
                duration = metadata.duration!;
              }

              // Handle Artwork (first picture from the list)
              if (metadata.pictures.isNotEmpty) {
                final picture = metadata.pictures.first;
                final artFile = File(
                  '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_art.jpg',
                );
                await artFile.writeAsBytes(picture.bytes);
                artworkPath = artFile.path;
              }
            } catch (e) {
              debugPrint('Error reading metadata for ${file.name}: $e');
            }

            final song = Song(
              id: DateTime.now().millisecondsSinceEpoch.toString() + file.name,
              title: title,
              artist: artist,
              album: album,
              filePath: file.path!,
              duration: duration,
              artworkPath: artworkPath,
            );
            _playlist.add(song);
          }
        }
        if (_isShuffled) {
          _generateShuffleIndices();
        }

        // Auto-select first song if nothing is playing
        if (_currentIndex == -1 && _playlist.isNotEmpty) {
          await playSongAtIndex(0, play: false);
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }

  // Add song from URL
  void addSongFromUrl(String url) {
    final song = Song(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Stream URL',
      artist: 'Network Stream',
      filePath: url,
      duration: Duration.zero,
    );
    _playlist.add(song);
    if (_isShuffled) {
      _generateShuffleIndices();
    }

    // Auto-select if nothing is playing
    if (_currentIndex == -1) {
      playSongAtIndex(0, play: false);
    } else {
      notifyListeners();
    }
  }

  String _extractTitle(String filename) {
    String title = filename.replaceAll(RegExp(r'\.[^.]+$'), '');
    title = title.replaceAll(RegExp(r'[_-]'), ' ');
    return title;
  }

  // Play song at index
  Future<void> playSongAtIndex(int index, {bool play = true}) async {
    if (index < 0 || index >= _playlist.length) return;

    // Cancel any previous loading timeout
    _loadingTimeoutTimer?.cancel();

    // Set loading state immediately
    _isLoading = true;
    final isPrefetched = _prefetchedIndex == index;
    debugPrint('🔄 Loading song at index $index (prefetched: $isPrefetched)');

    // Start loading timeout to prevent stuck loading state in background
    _loadingTimeoutTimer = Timer(_loadingTimeout, () {
      if (_isLoading && !_disposed) {
        debugPrint('⚠️ Loading timeout reached - clearing loading state');
        _isLoading = false;
        // Store as pending retry for when app comes back to foreground
        if (_isInBackground) {
          _pendingRetryIndex = index;
          debugPrint('📌 Stored pending retry for index $index');
        }
        notifyListeners();
      }
    });

    try {
      _currentIndex = index;
      final song = _playlist[index];

      // Update UI immediately for snappy feel (also triggers loading animation)
      notifyListeners();

      // Update audio service notification (don't await)
      _audioHandler?.updateNowPlaying(
        title: song.title,
        artist: song.artist,
        album: song.album,
        duration: song.duration,
        artworkPath: song.artworkPath,
      );

      // Update background color async (don't block playback)
      _updatePalette();

      // Check if this song was prefetched
      if (isPrefetched) {
        if (_usingPrefetchPlayer) {
          // We're currently playing from _prefetchPlayer, and next song is in _player
          debugPrint('⚡ Using main player for instant playback (swapped)');

          // Stop prefetch player
          await _prefetchPlayer?.stop();

          // Switch to main player
          _usingPrefetchPlayer = false;
          _audioHandler?.setActivePlayer(_player);

          // Play from main player
          if (play) {
            await _player.play();
          }
          await _player.setVolume(_volume);
        } else {
          // We're currently playing from _player, and next song is in _prefetchPlayer
          debugPrint('⚡ Using prefetched player for instant playback');

          // Stop main player
          await _player.stop();

          // Switch to prefetch player
          _usingPrefetchPlayer = true;
          _audioHandler?.setActivePlayer(_prefetchPlayer!);

          // Play from prefetch player
          if (play) {
            await _prefetchPlayer!.play();
          }

          // Setup listeners for prefetch player
          _setupPrefetchPlayerListeners();
          await _prefetchPlayer!.setVolume(_volume);
        }

        // Clear prefetch state
        _prefetchedIndex = null;
        _isPrefetching = false;
      } else {
        // Not prefetched - clear prefetch and load fresh
        _clearPrefetch();
        _usingPrefetchPlayer = false;
        _audioHandler?.setActivePlayer(_player);

        // Check for offline file first, but verify source matches (HD upgrade check)
        String mediaPath = song.filePath;
        final offlineService = OfflineStorageService();
        final offlineSong = await offlineService.getSong(song.id);
        String? localPath;

        if (offlineSong != null) {
          // Check if the song has been upgraded to HD on the server
          // If server source is 'tidal' but offline has 'user', skip offline and stream HD
          if (song.source != offlineSong.source && song.source == 'tidal') {
            debugPrint(
              '⬆️ HD upgrade detected! Server: ${song.source}, Offline: ${offlineSong.source} - streaming HD version',
            );
            // Don't use offline cache, will stream from server
            localPath = null;
            // Trigger background update to replace the offline file with the HD version
            _updateOfflineCache(song);
          } else {
            localPath = offlineSong.localPath;
          }
        }

        if (localPath != null) {
          mediaPath = localPath;
          debugPrint('🔌 Playing offline: $localPath');
        } else {
          debugPrint('🌐 Streaming from server: ${song.filePath}');

          // Check subscription access before streaming
          final (hasAccess, errorMessage) = await _apiService.checkStreamAccess(
            song.id,
          );
          if (!hasAccess) {
            debugPrint('❌ Stream access denied: $errorMessage');
            _loadingTimeoutTimer?.cancel();
            _isLoading = false;
            notifyListeners();

            // Trigger subscription snackbar if it's a subscription error
            if (errorMessage != null &&
                errorMessage.startsWith('SUBSCRIPTION_REQUIRED:')) {
              final msg = errorMessage.substring(
                'SUBSCRIPTION_REQUIRED:'.length,
              );
              debugPrint('🔔 Triggering onSubscriptionRequired callback...');
              if (onSubscriptionRequired != null) {
                debugPrint('✅ Callback is set, calling with: $msg');
                onSubscriptionRequired!(msg);
              } else {
                debugPrint('❌ onSubscriptionRequired callback is null');
              }
            }
            return;
          }
        }

        // Use cached token for faster loading (only needed for streaming)
        final headers = (localPath == null && _cachedAuthToken != null)
            ? {'Authorization': 'Bearer $_cachedAuthToken'}
            : null;

        // Open and play - this is the main async operation
        await _player.open(Media(mediaPath, httpHeaders: headers), play: play);

        // Apply current volume setting to new media
        await _player.setVolume(_volume);
      }

      // Track the play via analytics API (needed for both prefetched and non-prefetched)
      // This is the single source of truth for play tracking
      if (play && song.id.isNotEmpty) {
        _analyticsService.trackPlay(
          songId: song.id,
          playlistId: _currentPlaylistId,
          context: _currentPlaylistId != null ? 'playlist' : 'library',
        );
      }

      if (_isShuffled) {
        _generateShuffleIndices();
      }
    } catch (e) {
      debugPrint('Error playing song: $e');
      // Clear loading timeout
      _loadingTimeoutTimer?.cancel();
      // Clear loading state on error
      if (_isLoading) {
        _isLoading = false;
        // Store as pending retry if in background
        if (_isInBackground) {
          _pendingRetryIndex = index;
          debugPrint('📌 Stored pending retry for index $index after error');
        }
        notifyListeners();
      }
    }
  }

  // Setup listeners for prefetched player when we use it
  void _setupPrefetchPlayerListeners() {
    if (_prefetchPlayer == null || _disposed) return;

    // Cancel any existing prefetch subscriptions first
    for (var sub in _prefetchPlayerSubscriptions) {
      sub.cancel();
    }
    _prefetchPlayerSubscriptions.clear();

    _prefetchPlayerSubscriptions.add(
      _prefetchPlayer!.stream.playing.listen((playing) {
        if (_disposed) return;
        if (_usingPrefetchPlayer) {
          _isPlaying = playing;
          notifyListeners();

          // Broadcast activity to friends
          if (playing) {
            _startActivityBroadcast();
          } else {
            _stopActivityBroadcast();
          }
        }
      }),
    );

    _prefetchPlayerSubscriptions.add(
      _prefetchPlayer!.stream.position.listen((position) {
        if (_disposed) return;
        if (_usingPrefetchPlayer) {
          _currentPosition = position;

          // Clear loading when we get actual position updates
          if (_isLoading && position.inMilliseconds > 100) {
            _loadingTimeoutTimer?.cancel();
            _isLoading = false;
          }

          notifyListeners();

          // Trigger prefetch for next song
          if (position.inSeconds >= 10 &&
              !_isPrefetching &&
              _prefetchedIndex == null) {
            _prefetchNextSong();
          }
        }
      }),
    );

    _prefetchPlayerSubscriptions.add(
      _prefetchPlayer!.stream.duration.listen((duration) {
        if (_disposed) return;
        if (_usingPrefetchPlayer) {
          _totalDuration = duration;

          // Clear loading when we get valid duration (audio is ready)
          if (_isLoading && duration.inMilliseconds > 0) {
            _loadingTimeoutTimer?.cancel();
            _isLoading = false;
          }

          notifyListeners();
        }
      }),
    );

    _prefetchPlayerSubscriptions.add(
      _prefetchPlayer!.stream.completed.listen((completed) {
        if (_disposed) return;
        if (completed && _usingPrefetchPlayer) {
          _handleSongCompleted();
        }
      }),
    );
  }

  // Play/Pause toggle
  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _activePlayer.pause();
    } else {
      if (_currentIndex == -1 && _playlist.isNotEmpty) {
        await playSongAtIndex(0);
      } else {
        await _activePlayer.play();
      }
    }
  }

  // Play next song
  Future<void> playNext() async {
    if (_playlist.isEmpty) return;

    if (_repeatMode == RepeatMode.one) {
      await _activePlayer.seek(Duration.zero);
      await _activePlayer.play();
      return;
    }

    int nextIndex;
    if (_isShuffled) {
      if (_shuffleIndices.isEmpty) _generateShuffleIndices();

      int currentShufflePos = _shuffleIndices.indexOf(_currentIndex);
      if (currentShufflePos == -1 ||
          currentShufflePos >= _shuffleIndices.length - 1) {
        // End of shuffle list
        if (_repeatMode == RepeatMode.all) {
          // Reshuffle for a new loop, but maybe start with a random one?
          // Or just loop the current shuffle list? Looping is more predictable.
          nextIndex = _shuffleIndices[0];
        } else {
          return; // Stop
        }
      } else {
        nextIndex = _shuffleIndices[currentShufflePos + 1];
      }
    } else {
      // Normal order
      if (_currentIndex >= _playlist.length - 1) {
        if (_repeatMode == RepeatMode.all) {
          nextIndex = 0;
        } else {
          return; // Stop
        }
      } else {
        nextIndex = _currentIndex + 1;
      }
    }

    await playSongAtIndex(nextIndex);
  }

  // Play previous song
  Future<void> playPrevious() async {
    if (_playlist.isEmpty) return;

    // If more than 3 seconds in, restart song
    if (_currentPosition.inSeconds > 3) {
      await _activePlayer.seek(Duration.zero);
      return;
    }

    int prevIndex;
    if (_isShuffled) {
      if (_shuffleIndices.isEmpty) _generateShuffleIndices();

      int currentShufflePos = _shuffleIndices.indexOf(_currentIndex);
      if (currentShufflePos <= 0) {
        // Start of shuffle list
        if (_repeatMode == RepeatMode.all) {
          prevIndex = _shuffleIndices[_shuffleIndices.length - 1];
        } else {
          prevIndex = _shuffleIndices[0]; // Or stop/restart?
        }
      } else {
        prevIndex = _shuffleIndices[currentShufflePos - 1];
      }
    } else {
      // Normal order
      if (_currentIndex <= 0) {
        if (_repeatMode == RepeatMode.all) {
          prevIndex = _playlist.length - 1;
        } else {
          prevIndex = 0;
        }
      } else {
        prevIndex = _currentIndex - 1;
      }
    }

    await playSongAtIndex(prevIndex);
  }

  // Seek to position
  Future<void> seekTo(Duration position) async {
    await _activePlayer.seek(position);
  }

  // Toggle Shuffle
  void toggleShuffle() {
    _isShuffled = !_isShuffled;
    if (_isShuffled) {
      _generateShuffleIndices();
    } else {
      _shuffleIndices.clear();
    }
    // Clear prefetch since order changed
    _clearPrefetch();
    notifyListeners();
  }

  /// Reorder songs in the playlist (for queue drag-and-drop)
  void reorderPlaylist(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _playlist.length) return;
    if (newIndex < 0 || newIndex > _playlist.length) return;

    // ReorderableListView passes newIndex after removal, so adjust
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // Get the song being moved
    final song = _playlist.removeAt(oldIndex);
    _playlist.insert(newIndex, song);

    // Update current index to keep playing the same song
    if (_currentIndex == oldIndex) {
      // The currently playing song was moved
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      // Song moved from before current to after current
      _currentIndex -= 1;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      // Song moved from after current to before current
      _currentIndex += 1;
    }

    // Clear prefetch since order changed
    _clearPrefetch();

    // Regenerate shuffle indices if shuffled
    if (_isShuffled) {
      _generateShuffleIndices();
    }

    notifyListeners();
  }

  void _generateShuffleIndices() {
    _shuffleIndices = List.generate(_playlist.length, (i) => i);
    _shuffleIndices.shuffle();
    // Ensure current song is first in the new shuffle list if playing
    if (_currentIndex != -1 && _playlist.isNotEmpty) {
      _shuffleIndices.remove(_currentIndex);
      _shuffleIndices.insert(0, _currentIndex);
    }
  }

  // Toggle Repeat
  void toggleRepeat() {
    if (_repeatMode == RepeatMode.off) {
      _repeatMode = RepeatMode.all;
    } else if (_repeatMode == RepeatMode.all) {
      _repeatMode = RepeatMode.one;
    } else {
      _repeatMode = RepeatMode.off;
    }
    notifyListeners();
  }

  // Remove song from playlist
  void removeSong(int index) {
    if (index < 0 || index >= _playlist.length) return;

    // If the removed song is the current one
    if (index == _currentIndex) {
      _player.stop();
      _currentIndex = -1;
      _backgroundColor = null; // Reset color
    } else if (index < _currentIndex) {
      // If a song before the current one is removed, adjust current index
      _currentIndex--;
    }

    // Remove from playlist
    _playlist.removeAt(index);

    // Update shuffle indices if shuffling
    if (_isShuffled) {
      // Remove the index from shuffleIndices
      _shuffleIndices.remove(index);
      // Adjust any indices in _shuffleIndices that are greater than the removed index
      _shuffleIndices = _shuffleIndices
          .map((i) => i > index ? i - 1 : i)
          .toList();
      // If the playlist becomes empty or current song is gone, regenerate if needed
      if (_playlist.isEmpty || _currentIndex == -1) {
        _shuffleIndices.clear();
      } else if (_shuffleIndices.isEmpty && _playlist.isNotEmpty) {
        _generateShuffleIndices(); // Regenerate if it somehow became empty but playlist isn't
      }
    }

    notifyListeners();
  }

  // Clear playlist
  void clearPlaylist() {
    _player.stop();
    _clearPrefetch();
    _playlist.clear();
    _shuffleIndices.clear();
    _currentIndex = -1;
    _backgroundColor = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Set disposed flag FIRST to immediately block all callbacks
    _disposed = true;

    // Save final playback state before disposing
    _savePlaybackState();

    // Stop activity broadcasting
    _activityTimer?.cancel();
    _saveStateTimer?.cancel();
    _loadingTimeoutTimer?.cancel();
    _friendsService.clearActivity();

    // Cancel all subscriptions to prevent callbacks on disposed players
    for (var sub in _mainPlayerSubscriptions) {
      sub.cancel();
    }
    _mainPlayerSubscriptions.clear();

    for (var sub in _prefetchPlayerSubscriptions) {
      sub.cancel();
    }
    _prefetchPlayerSubscriptions.clear();

    _player.dispose();
    _prefetchPlayer?.dispose();
    super.dispose();
  }

  // =============================
  // Playback State Persistence
  // =============================

  /// Generate a unique device ID for this installation
  Future<void> _generateDeviceId() async {
    final stored = await _storage.read(key: 'device_id');
    if (stored != null) {
      _deviceId = stored;
    } else {
      _deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
      await _storage.write(key: 'device_id', value: _deviceId);
    }
  }

  /// Setup auto-save timer (save state every 30 seconds while playing)
  void _setupAutoSave() {
    _saveStateTimer?.cancel();
    _saveStateTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isPlaying && currentSong != null) {
        _savePlaybackState();
      }
    });
  }

  /// Save current playback state to local storage and cloud
  Future<void> _savePlaybackState() async {
    if (_disposed) return;
    if (currentSong == null) return;

    final repeatModeStr = switch (_repeatMode) {
      RepeatMode.one => 'one',
      RepeatMode.all => 'all',
      RepeatMode.off => 'off',
    };

    final state = PlaybackState.fromPlayerState(
      currentSong: currentSong,
      playlistId: _currentPlaylistId,
      playlistName: _currentPlaylistName,
      position: _currentPosition,
      duration: _totalDuration,
      queueIndex: _currentIndex,
      shuffleOn: _isShuffled,
      repeatMode: repeatModeStr,
      queue: _playlist,
      isPlaying: _isPlaying,
      deviceId: _deviceId,
      deviceName: _deviceName,
    );

    await _playbackStateService.saveState(state);
  }

  /// Restore playback state from storage (call on app startup)
  /// Returns true if state was restored successfully
  Future<bool> restorePlaybackState() async {
    try {
      debugPrint('🔄 Attempting to restore playback state...');

      final state = await _playbackStateService.getLatestState();
      if (state == null || state.songId == null) {
        debugPrint('📭 No saved playback state found');
        return false;
      }

      debugPrint(
        '📦 Found saved state: songId=${state.songId}, position=${state.positionMs}ms',
      );

      // Restore shuffle and repeat mode
      _isShuffled = state.shuffleOn;
      _repeatMode = switch (state.repeatMode) {
        'one' => RepeatMode.one,
        'all' => RepeatMode.all,
        _ => RepeatMode.off,
      };

      // Restore playlist context
      _currentPlaylistId = state.playlistId;
      _currentPlaylistName = state.playlistName;

      // Restore the queue if available
      if (state.queueSongIds.isNotEmpty) {
        debugPrint(
          '📋 Restoring queue with ${state.queueSongIds.length} songs',
        );
        // Note: We can't directly restore Song objects from IDs here
        // The caller should handle fetching songs if needed
      }

      // Notify listeners about restored state
      notifyListeners();

      debugPrint(
        '✅ Playback state restored (shuffle: ${state.shuffleOn}, repeat: ${state.repeatMode})',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error restoring playback state: $e');
      return false;
    }
  }

  /// Get the saved playback state without applying it
  /// Useful for showing "Continue listening" UI
  Future<PlaybackState?> getSavedPlaybackState() async {
    return await _playbackStateService.getLatestState();
  }

  /// Resume playback from saved state with provided songs
  /// [songs] - The full song list (e.g., from a playlist or library)
  /// [seekToPosition] - Whether to seek to the saved position
  Future<bool> resumeFromSavedState(
    List<Song> songs, {
    bool seekToPosition = true,
  }) async {
    try {
      final state = await _playbackStateService.getLatestState();
      if (state == null || state.songId == null) {
        return false;
      }

      // Find the song in the provided list
      final songIndex = songs.indexWhere((s) => s.id == state.songId);
      if (songIndex == -1) {
        debugPrint('⚠️ Saved song not found in provided list');
        return false;
      }

      // Set the playlist
      _playlist = songs;
      _currentPlaylistId = state.playlistId;
      _currentPlaylistName = state.playlistName;

      // Restore shuffle mode
      _isShuffled = state.shuffleOn;
      if (_isShuffled) {
        _generateShuffleIndices();
      }

      // Restore repeat mode
      _repeatMode = switch (state.repeatMode) {
        'one' => RepeatMode.one,
        'all' => RepeatMode.all,
        _ => RepeatMode.off,
      };

      // Play the song (paused initially)
      await playSongAtIndex(songIndex, play: false);

      // Seek to saved position if requested
      if (seekToPosition && state.positionMs > 0) {
        // Small delay to ensure player is ready
        await Future.delayed(const Duration(milliseconds: 300));
        await seekTo(Duration(milliseconds: state.positionMs));
      }

      debugPrint(
        '✅ Resumed from saved state: ${currentSong?.title} at ${state.positionMs}ms',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error resuming from saved state: $e');
      return false;
    }
  }

  /// Clear saved playback state
  Future<void> clearSavedPlaybackState() async {
    await _playbackStateService.clearLocalState();
    await _playbackStateService.clearCloudState();
  }

  Future<void> _updateOfflineCache(Song song) async {
    debugPrint('🔄 Auto-updating offline cache for ${song.id} to HD...');
    final songsDir = await OfflineStorageService.getSongsDir();
    final result = await _apiService.downloadSong(song.id, song.id, songsDir);

    if (result != null) {
      final offlineService = OfflineStorageService();
      await offlineService.updateSong(
        OfflineSong(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: song.album ?? '',
          localPath: result,
          coverPath: song.artworkPath,
          durationMs: song.duration.inMilliseconds,
          downloadedAt: DateTime.now(),
          source: song.source,
        ),
      );
      debugPrint('✅ Offline cache updated for ${song.id}');
    } else {
      debugPrint('❌ Failed to auto-update offline cache for ${song.id}');
    }
  }
}
