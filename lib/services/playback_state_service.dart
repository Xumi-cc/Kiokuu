import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/song.dart';

/// Service for persisting and restoring playback state
/// Handles both local persistence and cloud sync
class PlaybackStateService {
  static const _storage = FlutterSecureStorage();
  static const _localStateKey = 'playback_state';
  static String get _baseUrl => AppConfig.apiBaseUrl;

  Future<String?> get _token async => await _storage.read(key: 'auth_token');

  Map<String, String> _authHeaders(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  // =========================
  // Playback State Model
  // =========================

  /// Save playback state locally for instant restore on app restart
  Future<void> saveLocalState(PlaybackState state) async {
    try {
      final json = state.toJson();
      await _storage.write(key: _localStateKey, value: jsonEncode(json));
      debugPrint('💾 Saved local playback state');
    } catch (e) {
      debugPrint('❌ Error saving local state: $e');
    }
  }

  /// Load playback state from local storage
  Future<PlaybackState?> loadLocalState() async {
    try {
      final jsonStr = await _storage.read(key: _localStateKey);
      if (jsonStr == null) return null;

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final state = PlaybackState.fromJson(json);
      debugPrint('📂 Loaded local playback state');
      return state;
    } catch (e) {
      debugPrint('❌ Error loading local state: $e');
      return null;
    }
  }

  /// Clear local playback state
  Future<void> clearLocalState() async {
    try {
      await _storage.delete(key: _localStateKey);
      debugPrint('🗑️ Cleared local playback state');
    } catch (e) {
      debugPrint('❌ Error clearing local state: $e');
    }
  }

  // =========================
  // Cloud Sync
  // =========================

  /// Save playback state to cloud for cross-device sync
  Future<bool> saveCloudState(PlaybackState state) async {
    try {
      final token = await _token;
      if (token == null) return false;

      final response = await http.put(
        Uri.parse('$_baseUrl/playback-state'),
        headers: _authHeaders(token),
        body: jsonEncode(state.toJson()),
      );

      if (response.statusCode == 200) {
        debugPrint('☁️ Saved cloud playback state');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error saving cloud state: $e');
      return false;
    }
  }

  /// Load playback state from cloud
  Future<PlaybackState?> loadCloudState() async {
    try {
      final token = await _token;
      if (token == null) return null;

      final response = await http.get(
        Uri.parse('$_baseUrl/playback-state'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['state'] == null) return null;

        final state = PlaybackState.fromJson(data['state'] as Map<String, dynamic>);
        debugPrint('☁️ Loaded cloud playback state');
        return state;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error loading cloud state: $e');
      return null;
    }
  }

  /// Clear cloud playback state
  Future<bool> clearCloudState() async {
    try {
      final token = await _token;
      if (token == null) return false;

      final response = await http.delete(
        Uri.parse('$_baseUrl/playback-state'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        debugPrint('🗑️ Cleared cloud playback state');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ Error clearing cloud state: $e');
      return false;
    }
  }

  // =========================
  // Smart Sync
  // =========================

  /// Get the most recent state (cloud takes precedence if newer)
  Future<PlaybackState?> getLatestState() async {
    final localState = await loadLocalState();
    final cloudState = await loadCloudState();

    if (localState == null && cloudState == null) {
      return null;
    }

    if (localState == null) return cloudState;
    if (cloudState == null) return localState;

    // Return the more recent one
    if (cloudState.updatedAt > localState.updatedAt) {
      debugPrint('📡 Using cloud state (more recent)');
      // Update local with cloud state
      await saveLocalState(cloudState);
      return cloudState;
    } else {
      debugPrint('📱 Using local state (more recent)');
      // Update cloud with local state
      await saveCloudState(localState);
      return localState;
    }
  }

  /// Save state to both local and cloud
  Future<void> saveState(PlaybackState state) async {
    // Save locally first for instant access
    await saveLocalState(state);
    // Then sync to cloud (non-blocking)
    saveCloudState(state);
  }
}

/// Represents the saved playback state
class PlaybackState {
  final String? songId;
  final String? playlistId;
  final String? playlistName;
  final int positionMs;
  final int durationMs;
  final int queueIndex;
  final bool shuffleOn;
  final String repeatMode;
  final List<String> queueSongIds;
  final bool isPlaying;
  final String? deviceId;
  final String? deviceName;
  final int updatedAt;

  PlaybackState({
    this.songId,
    this.playlistId,
    this.playlistName,
    required this.positionMs,
    required this.durationMs,
    required this.queueIndex,
    required this.shuffleOn,
    required this.repeatMode,
    required this.queueSongIds,
    required this.isPlaying,
    this.deviceId,
    this.deviceName,
    required this.updatedAt,
  });

  factory PlaybackState.fromJson(Map<String, dynamic> json) {
    return PlaybackState(
      songId: json['song_id'] as String?,
      playlistId: json['playlist_id'] as String?,
      playlistName: json['playlist_name'] as String?,
      positionMs: json['position_ms'] as int? ?? 0,
      durationMs: json['duration_ms'] as int? ?? 0,
      queueIndex: json['queue_index'] as int? ?? 0,
      shuffleOn: json['shuffle_on'] as bool? ?? false,
      repeatMode: json['repeat_mode'] as String? ?? 'off',
      queueSongIds: (json['queue_song_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isPlaying: json['is_playing'] as bool? ?? false,
      deviceId: json['device_id'] as String?,
      deviceName: json['device_name'] as String?,
      updatedAt: json['updated_at'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'song_id': songId,
      'playlist_id': playlistId,
      'playlist_name': playlistName,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'queue_index': queueIndex,
      'shuffle_on': shuffleOn,
      'repeat_mode': repeatMode,
      'queue_song_ids': queueSongIds,
      'is_playing': isPlaying,
      'device_id': deviceId,
      'device_name': deviceName,
      'updated_at': updatedAt,
    };
  }

  /// Create state from MusicProvider data
  static PlaybackState fromPlayerState({
    required Song? currentSong,
    required String? playlistId,
    required String? playlistName,
    required Duration position,
    required Duration duration,
    required int queueIndex,
    required bool shuffleOn,
    required String repeatMode,
    required List<Song> queue,
    required bool isPlaying,
    required String deviceId,
    required String deviceName,
  }) {
    return PlaybackState(
      songId: currentSong?.id,
      playlistId: playlistId,
      playlistName: playlistName,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      queueIndex: queueIndex,
      shuffleOn: shuffleOn,
      repeatMode: repeatMode,
      queueSongIds: queue.map((s) => s.id).toList(),
      isPlaying: isPlaying,
      deviceId: deviceId,
      deviceName: deviceName,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }
}
