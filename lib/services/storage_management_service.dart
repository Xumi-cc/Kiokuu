import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_storage_service.dart';
import 'lyrics_service.dart';

/// Represents storage usage information for a specific category
class StorageCategory {
  final String name;
  final String description;
  final String path; // Path to the directory (for user transparency)
  final StorageIconType iconType;
  final int bytes;
  final bool canClear;
  final Future<void> Function()? onClear;

  StorageCategory({
    required this.name,
    required this.description,
    required this.path,
    required this.iconType,
    required this.bytes,
    this.canClear = true,
    this.onClear,
  });

  String get formattedSize {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Returns a shortened path for display (replaces home dir with ~)
  String get displayPath {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && path.startsWith(home)) {
      return path.replaceFirst(home, '~');
    }
    return path;
  }
}

enum StorageIconType {
  offlineSongs,
  imageCache,
  playlistCache,
  lyrics,
  importTasks,
  preferences,
  tempFiles,
}

/// Manages local storage analysis and cleanup
class StorageManagementService {
  static StorageManagementService? _instance;
  static StorageManagementService get instance {
    _instance ??= StorageManagementService._();
    return _instance!;
  }

  StorageManagementService._();

  final OfflineStorageService _offlineService = OfflineStorageService();

  /// Get all storage categories with their sizes
  Future<List<StorageCategory>> getStorageBreakdown() async {
    final categories = <StorageCategory>[];

    // Get paths upfront
    final offlineDir = await OfflineStorageService.getOfflineDir();
    final cacheDir = await getTemporaryDirectory();
    final appSupportDir = await getApplicationSupportDirectory();
    final appCacheDir = await getApplicationCacheDirectory();

    // 1. Offline Songs (downloaded for offline playback)
    final offlineBytes = await _getOfflineSongsSize();
    categories.add(
      StorageCategory(
        name: 'Offline Songs',
        description: 'Downloaded songs for offline playback',
        path: offlineDir,
        iconType: StorageIconType.offlineSongs,
        bytes: offlineBytes,
        canClear: true,
        onClear: _clearOfflineSongs,
      ),
    );

    // 2. Image Cache (album art, profile pictures, etc.)
    final imageCacheBytes = await _getImageCacheSize();
    categories.add(
      StorageCategory(
        name: 'Image Cache',
        description: 'Album artwork and profile images',
        path: '${cacheDir.path}/image_cache/',
        iconType: StorageIconType.imageCache,
        bytes: imageCacheBytes,
        canClear: true,
        onClear: _clearImageCache,
      ),
    );

    // 3. Playlist Cache (cached playlist metadata)
    final playlistCacheBytes = await _getPlaylistCacheSize();
    categories.add(
      StorageCategory(
        name: 'Playlist Cache',
        description: 'Cached playlist data for faster loading',
        path: '$offlineDir/.playlist_cache.json',
        iconType: StorageIconType.playlistCache,
        bytes: playlistCacheBytes,
        canClear: true,
        onClear: _clearPlaylistCache,
      ),
    );

    // 4. Lyrics Cache (in-memory, estimate based on count)
    final lyricsCacheBytes = _getLyricsCacheSize();
    categories.add(
      StorageCategory(
        name: 'Lyrics Cache',
        description: 'Cached song lyrics (in memory)',
        path: 'In-memory cache',
        iconType: StorageIconType.lyrics,
        bytes: lyricsCacheBytes,
        canClear: true,
        onClear: _clearLyricsCache,
      ),
    );

    // 5. Import Task Data
    final importTaskBytes = await _getImportTaskSize();
    categories.add(
      StorageCategory(
        name: 'Import Tasks',
        description: 'Pending and completed import logs',
        path: appSupportDir.path,
        iconType: StorageIconType.importTasks,
        bytes: importTaskBytes,
        canClear: true,
        onClear: _clearImportTasks,
      ),
    );

    // 6. Temporary Files
    final tempBytes = await _getTempFilesSize();
    categories.add(
      StorageCategory(
        name: 'Temporary Files',
        description: 'Temporary app data that can be cleared',
        path: appCacheDir.path,
        iconType: StorageIconType.tempFiles,
        bytes: tempBytes,
        canClear: true,
        onClear: _clearTempFiles,
      ),
    );

    return categories;
  }

  /// Get total storage used
  Future<int> getTotalStorageUsed() async {
    final categories = await getStorageBreakdown();
    return categories.fold<int>(0, (sum, cat) => sum + cat.bytes);
  }

  /// Clear all caches (not offline songs)
  Future<void> clearAllCaches() async {
    await _clearImageCache();
    await _clearPlaylistCache();
    await _clearLyricsCache();
    await _clearTempFiles();
  }

  /// Clear everything including offline songs
  Future<void> clearAllData() async {
    await clearAllCaches();
    await _clearOfflineSongs();
    await _clearImportTasks();
  }

  // --- Size Calculations ---

  Future<int> _getOfflineSongsSize() async {
    try {
      final songsDir = Directory(await OfflineStorageService.getSongsDir());
      final coversDir = Directory(await OfflineStorageService.getCoversDir());

      int total = 0;
      if (await songsDir.exists()) {
        total += await _getDirectorySize(songsDir);
      }
      if (await coversDir.exists()) {
        total += await _getDirectorySize(coversDir);
      }
      return total;
    } catch (e) {
      debugPrint('⚠️ Error calculating offline songs size: $e');
      return 0;
    }
  }

  Future<int> _getImageCacheSize() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final imageCacheDir = Directory('${cacheDir.path}/image_cache');
      final flutterCacheDir = Directory('${cacheDir.path}/flutter_cache');

      int total = 0;
      if (await imageCacheDir.exists()) {
        total += await _getDirectorySize(imageCacheDir);
      }
      if (await flutterCacheDir.exists()) {
        total += await _getDirectorySize(flutterCacheDir);
      }

      // Also check for libCachedImageData (used by cached_network_image)
      final libCacheDir = Directory('${cacheDir.path}/libCachedImageData');
      if (await libCacheDir.exists()) {
        total += await _getDirectorySize(libCacheDir);
      }

      return total;
    } catch (e) {
      debugPrint('⚠️ Error calculating image cache size: $e');
      return 0;
    }
  }

  Future<int> _getPlaylistCacheSize() async {
    try {
      final offlineDir = await OfflineStorageService.getOfflineDir();
      final cacheFile = File('$offlineDir/.playlist_cache.json');
      final metadataFile = File('$offlineDir/.offline_metadata.json');

      int total = 0;
      if (await cacheFile.exists()) {
        total += await cacheFile.length();
      }
      if (await metadataFile.exists()) {
        total += await metadataFile.length();
      }
      return total;
    } catch (e) {
      debugPrint('⚠️ Error calculating playlist cache size: $e');
      return 0;
    }
  }

  int _getLyricsCacheSize() {
    // Estimate based on average lyrics size (~2KB per song)
    final lyricsCount = LyricsService.getCacheCount();
    return lyricsCount * 2048; // ~2KB per cached lyrics
  }

  Future<int> _getImportTaskSize() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final tasksFile = File('${appDir.path}/pending_reviews.json');
      final logsDir = Directory('${appDir.path}/import_logs');

      int total = 0;
      if (await tasksFile.exists()) {
        total += await tasksFile.length();
      }
      if (await logsDir.exists()) {
        total += await _getDirectorySize(logsDir);
      }
      return total;
    } catch (e) {
      debugPrint('⚠️ Error calculating import task size: $e');
      return 0;
    }
  }

  Future<int> _getTempFilesSize() async {
    try {
      final appCacheDir = await getApplicationCacheDirectory();

      int total = 0;

      // Only scan app-specific cache directory (not the entire /tmp which has system dirs)
      if (await appCacheDir.exists()) {
        await for (final entity in appCacheDir.list()) {
          // Skip directories we've already counted in other categories
          final name = entity.path.split('/').last;
          if ([
            'image_cache',
            'flutter_cache',
            'libCachedImageData',
          ].contains(name)) {
            continue;
          }

          if (entity is File) {
            try {
              total += await entity.length();
            } catch (_) {
              // Skip files we can't read
            }
          } else if (entity is Directory) {
            total += await _getDirectorySize(entity);
          }
        }
      }

      return total;
    } catch (e) {
      debugPrint('⚠️ Error calculating temp files size: $e');
      return 0;
    }
  }

  Future<int> _getDirectorySize(Directory dir) async {
    int total = 0;
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // Skip files we can't read
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error reading directory size: $e');
    }
    return total;
  }

  // --- Clear Functions ---

  Future<void> _clearOfflineSongs() async {
    try {
      final offlineDir = Directory(await OfflineStorageService.getOfflineDir());
      if (await offlineDir.exists()) {
        await offlineDir.delete(recursive: true);
        debugPrint('🗑️ Cleared offline songs directory');
      }

      // Reset the service state
      await _offlineService.load();
    } catch (e) {
      debugPrint('⚠️ Error clearing offline songs: $e');
      rethrow;
    }
  }

  Future<void> _clearImageCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();

      final dirs = [
        Directory('${cacheDir.path}/image_cache'),
        Directory('${cacheDir.path}/flutter_cache'),
        Directory('${cacheDir.path}/libCachedImageData'),
      ];

      for (final dir in dirs) {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          debugPrint('🗑️ Cleared ${dir.path}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing image cache: $e');
      rethrow;
    }
  }

  Future<void> _clearPlaylistCache() async {
    try {
      final offlineDir = await OfflineStorageService.getOfflineDir();
      final cacheFile = File('$offlineDir/.playlist_cache.json');

      if (await cacheFile.exists()) {
        await cacheFile.delete();
        debugPrint('🗑️ Cleared playlist cache');
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing playlist cache: $e');
      rethrow;
    }
  }

  Future<void> _clearLyricsCache() async {
    LyricsService.clearCache();
    debugPrint('🗑️ Cleared lyrics cache');
  }

  Future<void> _clearImportTasks() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final tasksFile = File('${appDir.path}/pending_reviews.json');
      final logsDir = Directory('${appDir.path}/import_logs');

      if (await tasksFile.exists()) {
        await tasksFile.delete();
        debugPrint('🗑️ Cleared pending reviews');
      }
      if (await logsDir.exists()) {
        await logsDir.delete(recursive: true);
        debugPrint('🗑️ Cleared import logs');
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing import tasks: $e');
      rethrow;
    }
  }

  Future<void> _clearTempFiles() async {
    try {
      final appCacheDir = await getApplicationCacheDirectory();

      // Only clear app-specific cache (not the entire /tmp which has system dirs)
      if (await appCacheDir.exists()) {
        await for (final entity in appCacheDir.list()) {
          final name = entity.path.split('/').last;
          // Skip directories we clear in other methods
          if ([
            'image_cache',
            'flutter_cache',
            'libCachedImageData',
          ].contains(name)) {
            continue;
          }
          // Skip hidden files
          if (name.startsWith('.')) {
            continue;
          }
          try {
            await entity.delete(recursive: true);
          } catch (_) {
            // Some files may be in use or protected
          }
        }
        debugPrint('🗑️ Cleared app cache directory');
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing temp files: $e');
      rethrow;
    }
  }

  /// Clear SharedPreferences (settings reset)
  Future<void> resetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    debugPrint('🗑️ Reset all settings');
  }
}
