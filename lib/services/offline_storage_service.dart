import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'import_folder_service.dart';

/// Manages offline song storage - centralized song storage with playlist mapping
///
/// Structure:
/// Android: {app-specific}/Offline/ or {user-selected-folder}/Offline/
/// iOS: {documents}/Offline/
/// Desktop: ~/KioKuu/Offline/
///
/// Subdirectories:
/// ├── songs/{song_id}/          <- Audio files (one copy per song)
/// │   ├── playlist.m3u8
/// │   └── segments...
/// ├── covers/{song_id}.jpg      <- Cover images
/// └── .offline_metadata.json    <- Maps songs to playlists
class OfflineStorageService {
  static final OfflineStorageService _instance =
      OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  // Song metadata (keyed by song ID)
  Map<String, OfflineSong> _songs = {};

  // Playlist -> Song IDs mapping (a song can be in multiple playlists)
  Map<String, Set<String>> _playlistSongs = {};

  bool _isLoaded = false;

  /// Get the base offline directory
  /// On Android, uses app-specific storage by default (no permissions needed).
  /// If user has selected a custom folder via SAF, that folder is used instead.
  /// On Desktop, uses the default ~/KioKuu folder.
  static Future<String> getOfflineDir() async {
    // Web doesn't support offline storage
    if (kIsWeb) {
      throw UnsupportedError('Offline storage not supported on web');
    }

    if (Platform.isAndroid) {
      // Use the user-selected SAF folder from ImportFolderService
      final importFolder = ImportFolderService.instance.importFolderPath;
      if (importFolder != null && importFolder.isNotEmpty) {
        // Create Offline subdirectory within the user-selected folder
        final offlineDir = '$importFolder/Offline';
        final dir = Directory(offlineDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return offlineDir;
      }

      // Fallback to app-specific storage if no folder selected
      // This works without any special permissions
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final fallbackDir = '${directory.path}/Offline';
        final dir = Directory(fallbackDir);
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return fallbackDir;
      }

      throw StateError(
        'No accessible storage directory on Android. Please select a folder in Settings.',
      );
    } else if (Platform.isIOS) {
      // iOS: Use app documents directory
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/Offline';
    } else if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/KioKuu/Offline';
    } else {
      final home = Platform.environment['USERPROFILE'] ?? '';
      return '$home/Music/KioKuu/Offline';
    }
  }

  /// Get songs directory
  static Future<String> getSongsDir() async {
    final base = await getOfflineDir();
    return '$base/songs';
  }

  /// Get covers directory
  static Future<String> getCoversDir() async {
    final base = await getOfflineDir();
    return '$base/covers';
  }

  /// Get the metadata file path
  Future<String> get _metadataPath async {
    final dir = await getOfflineDir();
    return '$dir/.offline_metadata.json';
  }

  /// Load offline songs metadata from disk
  Future<void> load() async {
    if (_isLoaded) return;

    // Web doesn't support offline storage
    if (kIsWeb) {
      _isLoaded = true;
      return;
    }

    try {
      final path = await _metadataPath;
      final file = File(path);
      if (await file.exists()) {
        final json = await file.readAsString();
        final data = jsonDecode(json) as Map<String, dynamic>;

        // Load songs
        final songsData = data['songs'] as Map<String, dynamic>? ?? {};
        _songs = songsData.map((k, v) => MapEntry(k, OfflineSong.fromJson(v)));

        // Load playlist mappings
        final playlistsData = data['playlists'] as Map<String, dynamic>? ?? {};
        _playlistSongs = playlistsData.map(
          (k, v) => MapEntry(k, (v as List).cast<String>().toSet()),
        );

        debugPrint(
          '📦 Loaded ${_songs.length} offline songs in ${_playlistSongs.length} playlists',
        );
      }
      _isLoaded = true;
    } catch (e) {
      debugPrint('⚠️ Failed to load offline metadata: $e');
      _songs = {};
      _playlistSongs = {};
      _isLoaded = true;
    }
  }

  /// Save metadata to disk
  Future<void> _save() async {
    try {
      final path = await _metadataPath;
      final file = File(path);
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final data = {
        'songs': _songs.map((k, v) => MapEntry(k, v.toJson())),
        'playlists': _playlistSongs.map((k, v) => MapEntry(k, v.toList())),
      };

      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('⚠️ Failed to save offline metadata: $e');
    }
  }

  /// Add a song to offline storage and associate with a playlist
  Future<void> addSong(OfflineSong song, String playlistId) async {
    await load();

    // Add/update song metadata
    _songs[song.id] = song;

    // Add to playlist mapping
    _playlistSongs.putIfAbsent(playlistId, () => {}).add(song.id);

    await _save();
  }

  /// Update an existing song's metadata without changing playlist associations
  Future<void> updateSong(OfflineSong song) async {
    await load();
    // Only update if it already exists or we want to allow detached songs
    _songs[song.id] = song;
    await _save();
  }

  /// Remove a song completely (if not in any other playlist)
  Future<void> removeSong(String songId) async {
    await load();

    // Check if song is in any playlist
    bool inAnyPlaylist = _playlistSongs.values.any(
      (songs) => songs.contains(songId),
    );

    if (!inAnyPlaylist) {
      final song = _songs.remove(songId);
      if (song != null) {
        // Delete the audio files
        final songDir = Directory('${await getSongsDir()}/$songId');
        if (await songDir.exists()) {
          await songDir.delete(recursive: true);
        }
        // Delete cover
        final coverFile = File('${await getCoversDir()}/$songId.jpg');
        if (await coverFile.exists()) {
          await coverFile.delete();
        }
      }
    }

    await _save();
  }

  /// Remove a song from a specific playlist (keeps song if in other playlists)
  Future<void> removeSongFromPlaylist(String songId, String playlistId) async {
    await load();

    _playlistSongs[playlistId]?.remove(songId);

    // Clean up empty playlists
    if (_playlistSongs[playlistId]?.isEmpty ?? false) {
      _playlistSongs.remove(playlistId);
    }

    // Remove song if not in any playlist
    await removeSong(songId);
  }

  /// Check if a song is available offline (verifies file exists on disk!)
  Future<bool> isAvailable(String songId) async {
    await load();
    final song = _songs[songId];
    if (song == null) return false;

    // IMPORTANT: Actually verify the file exists on disk!
    final file = File(song.localPath);
    if (!await file.exists()) {
      debugPrint(
        '⚠️ Song $songId metadata exists but file missing: ${song.localPath}',
      );
      return false;
    }
    return true;
  }

  /// Get the local path for a song (or null if not offline)
  Future<String?> getLocalPath(String songId) async {
    await load();
    final song = _songs[songId];
    if (song == null) return null;

    final file = File(song.localPath);
    if (await file.exists()) return song.localPath;

    // File missing - clean up stale metadata
    debugPrint('⚠️ Cleaning stale metadata for song $songId');
    _songs.remove(songId);
    for (final playlist in _playlistSongs.values) {
      playlist.remove(songId);
    }
    await _save();

    return null;
  }

  /// Get offline song metadata
  Future<OfflineSong?> getSong(String songId) async {
    await load();
    final song = _songs[songId];
    if (song == null) return null;

    // Verify file exists
    if (!await File(song.localPath).exists()) {
      return null;
    }
    return song;
  }

  /// Get all offline songs (verified to exist on disk)
  Future<List<OfflineSong>> getAllSongs() async {
    await load();
    final verified = <OfflineSong>[];

    for (final song in _songs.values) {
      if (await File(song.localPath).exists()) {
        verified.add(song);
      }
    }

    return verified;
  }

  /// Get offline songs for a playlist (verified to exist)
  Future<List<OfflineSong>> getPlaylistSongs(String playlistId) async {
    await load();

    final songIds = _playlistSongs[playlistId] ?? {};
    final songs = <OfflineSong>[];

    for (final id in songIds) {
      final song = _songs[id];
      if (song != null && await File(song.localPath).exists()) {
        songs.add(song);
      }
    }

    return songs;
  }

  /// Get all playlists that have offline songs
  Future<List<String>> getOfflinePlaylists() async {
    await load();
    return _playlistSongs.keys.toList();
  }

  /// Check if entire playlist is available offline (all songs verified)
  Future<bool> isPlaylistOffline(
    String playlistId,
    int expectedSongCount,
  ) async {
    await load();

    final songIds = _playlistSongs[playlistId] ?? {};
    if (songIds.length < expectedSongCount) return false;

    for (final id in songIds) {
      final song = _songs[id];
      if (song == null || !await File(song.localPath).exists()) {
        return false;
      }
    }

    return songIds.isNotEmpty;
  }

  /// Get count of available songs in a playlist
  Future<int> getPlaylistSongCount(String playlistId) async {
    await load();

    final songIds = _playlistSongs[playlistId] ?? {};
    int count = 0;

    for (final id in songIds) {
      final song = _songs[id];
      if (song != null && await File(song.localPath).exists()) {
        count++;
      }
    }

    return count;
  }

  /// Clean up stale metadata (songs where files no longer exist)
  Future<int> cleanupStaleMetadata() async {
    await load();
    int removed = 0;

    final toRemove = <String>[];
    for (final entry in _songs.entries) {
      if (!await File(entry.value.localPath).exists()) {
        toRemove.add(entry.key);
      }
    }

    for (final id in toRemove) {
      _songs.remove(id);
      for (final playlist in _playlistSongs.values) {
        playlist.remove(id);
      }
      removed++;
    }

    if (removed > 0) {
      await _save();
      debugPrint('🧹 Cleaned up $removed stale offline song entries');
    }

    return removed;
  }
}

/// Represents a song stored offline
class OfflineSong {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String localPath;
  final String? coverPath;
  final int durationMs;
  final DateTime downloadedAt;
  final String source; // Audio source when downloaded: "user", "tidal", etc.

  OfflineSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.localPath,
    this.coverPath,
    required this.durationMs,
    required this.downloadedAt,
    this.source = 'user', // Default for backward compatibility
  });

  factory OfflineSong.fromJson(Map<String, dynamic> json) {
    return OfflineSong(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      album: json['album'],
      localPath: json['localPath'],
      coverPath: json['coverPath'],
      durationMs: json['durationMs'],
      downloadedAt: DateTime.parse(json['downloadedAt']),
      source: json['source'] ?? 'user',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'localPath': localPath,
    'coverPath': coverPath,
    'durationMs': durationMs,
    'downloadedAt': downloadedAt.toIso8601String(),
    'source': source,
  };
}

/// Cached playlist metadata for showing all songs (even unavailable ones) in offline mode
class CachedPlaylistSong {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? coverPath;
  final int durationMs;

  CachedPlaylistSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.coverPath,
    required this.durationMs,
  });

  factory CachedPlaylistSong.fromJson(Map<String, dynamic> json) {
    return CachedPlaylistSong(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      album: json['album'],
      coverPath: json['coverPath'],
      durationMs: json['durationMs'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'coverPath': coverPath,
    'durationMs': durationMs,
  };
}

/// Extension to cache playlist song lists
extension PlaylistCacheExtension on OfflineStorageService {
  /// Get cached playlists file path
  Future<String> get _playlistCachePath async {
    final dir = await OfflineStorageService.getOfflineDir();
    return '$dir/.playlist_cache.json';
  }

  /// Cache a playlist's full song list (for showing unavailable songs as disabled)
  Future<void> cachePlaylistSongs(
    String playlistId,
    List<CachedPlaylistSong> songs,
  ) async {
    try {
      final path = await _playlistCachePath;
      final file = File(path);

      Map<String, dynamic> cache = {};
      if (await file.exists()) {
        cache = jsonDecode(await file.readAsString());
      }

      cache[playlistId] = songs.map((s) => s.toJson()).toList();

      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await file.writeAsString(jsonEncode(cache));

      debugPrint('📋 Cached ${songs.length} songs for playlist $playlistId');
    } catch (e) {
      debugPrint('⚠️ Failed to cache playlist songs: $e');
    }
  }

  /// Get cached playlist songs (includes unavailable songs for display)
  Future<List<CachedPlaylistSong>?> getCachedPlaylistSongs(
    String playlistId,
  ) async {
    try {
      final path = await _playlistCachePath;
      final file = File(path);

      if (!await file.exists()) return null;

      final cache = jsonDecode(await file.readAsString());
      final playlistData = cache[playlistId] as List?;

      if (playlistData == null) return null;

      return playlistData.map((s) => CachedPlaylistSong.fromJson(s)).toList();
    } catch (e) {
      debugPrint('⚠️ Failed to load cached playlist songs: $e');
      return null;
    }
  }

  /// Get all cached playlist IDs (playlists that have been viewed/browsed)
  Future<List<String>> getAllCachedPlaylistIds() async {
    try {
      final path = await _playlistCachePath;
      final file = File(path);

      if (!await file.exists()) return [];

      final cache =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return cache.keys.toList();
    } catch (e) {
      debugPrint('⚠️ Failed to get cached playlist IDs: $e');
      return [];
    }
  }
}
