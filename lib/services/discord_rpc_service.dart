import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Conditionally import flutter_discord_rpc on desktop platforms
import 'discord_rpc_stub.dart'
    if (dart.library.io) 'discord_rpc_desktop.dart'
    as discord_impl;

/// Service for managing Discord Rich Presence integration
class DiscordRpcService {
  static DiscordRpcService? _instance;
  static DiscordRpcService get instance => _instance ??= DiscordRpcService._();

  DiscordRpcService._();

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isEnabled = false;
  Timer? _reconnectTimer;
  StreamSubscription<bool>? _connectionSub;

  // Current activity data
  String? _currentSongTitle;
  String? _currentArtist;
  String? _currentAlbum;
  String? _albumArtUrl;
  bool _isPlaying = false;
  int? _durationMs;
  int? _positionMs;

  /// Whether Discord RPC is connected
  bool get isConnected => _isConnected;

  /// Whether Discord RPC is enabled in settings
  bool get isEnabled => _isEnabled;

  /// Whether Discord RPC is available on this platform
  bool get isAvailable =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Initialize the service and restore settings
  Future<void> initialize() async {
    if (!isAvailable) return;

    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('discord_rpc_enabled') ?? false;

    if (_isEnabled) {
      connect();
    }
  }

  /// Enable Discord Rich Presence
  Future<void> enable() async {
    if (!isAvailable) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('discord_rpc_enabled', true);
    _isEnabled = true;

    await connect();
  }

  /// Disable Discord Rich Presence
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('discord_rpc_enabled', false);
    _isEnabled = false;

    await disconnect();
  }

  /// Connect to Discord
  Future<void> connect() async {
    if (!isAvailable || !_isEnabled || _isConnected || _isConnecting) return;

    _isConnecting = true;
    try {
      await discord_impl.connect();
      _isConnected = true;
      debugPrint('✅ Discord RPC connected');

      // If we have a current song, update the presence
      if (_currentSongTitle != null) {
        await _updatePresence();
      }

      // Listen for future connection events (e.g. if Discord starts later)
      _connectionSub?.cancel();
      _connectionSub = discord_impl.connectionStateStream.listen((connected) {
        if (connected && _currentSongTitle != null) {
          debugPrint('🔄 Discord is now ready, updating presence...');
          _updatePresence();
        }
      });
    } catch (e) {
      debugPrint('❌ Failed to connect to Discord RPC: $e');
      _isConnected = false;

      // Retry connection after a delay
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  /// Disconnect from Discord
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectionSub?.cancel();
    _connectionSub = null;

    try {
      await discord_impl.disconnect();
      _isConnected = false;
      debugPrint('📤 Discord RPC disconnected');
    } catch (e) {
      debugPrint('⚠️ Error disconnecting Discord RPC: $e');
    }
  }

  /// Schedule a reconnection attempt
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 15), () {
      if (_isEnabled && !_isConnected) {
        connect();
      }
    });
  }

  /// Update the current playing song
  Future<void> updateNowPlaying({
    required String title,
    required String artist,
    String? album,
    String? albumArtUrl,
    bool isPlaying = true,
    int? durationMs,
    int? positionMs,
  }) async {
    _currentSongTitle = title;
    _currentArtist = artist;
    _currentAlbum = album;
    _albumArtUrl = albumArtUrl;
    _isPlaying = isPlaying;
    _durationMs = durationMs;
    _positionMs = positionMs;

    if (!_isEnabled || !_isConnected) return;

    await _updatePresence();
  }

  /// Update playback state (playing/paused)
  Future<void> updatePlaybackState({
    required bool isPlaying,
    int? positionMs,
  }) async {
    _isPlaying = isPlaying;
    if (positionMs != null) _positionMs = positionMs;

    if (!_isEnabled || !_isConnected) return;

    await _updatePresence();
  }

  /// Clear the current activity
  Future<void> clearActivity() async {
    _currentSongTitle = null;
    _currentArtist = null;
    _currentAlbum = null;
    _albumArtUrl = null;
    _isPlaying = false;
    _durationMs = null;
    _positionMs = null;

    if (!_isEnabled || !_isConnected) return;

    try {
      await discord_impl.clearActivity();
      debugPrint('🎵 Discord presence cleared');
    } catch (e) {
      debugPrint('⚠️ Failed to clear Discord presence: $e');
    }
  }

  /// Internal method to update Discord presence
  Future<void> _updatePresence() async {
    if (_currentSongTitle == null) return;

    try {
      await discord_impl.setActivity(
        details: _currentSongTitle!,
        state: _currentArtist ?? 'Unknown Artist',
        largeImageKey: _albumArtUrl ?? 'kiokuu_logo',
        largeImageText: _currentAlbum ?? 'KioKuu',
        smallImageKey: _isPlaying ? 'playing' : 'paused',
        smallImageText: _isPlaying ? 'Playing' : 'Paused',
        startTimestamp: _isPlaying && _positionMs != null
            ? DateTime.now()
                      .subtract(Duration(milliseconds: _positionMs!))
                      .millisecondsSinceEpoch ~/
                  1000
            : null,
        endTimestamp: _isPlaying && _durationMs != null && _positionMs != null
            ? DateTime.now()
                      .add(Duration(milliseconds: _durationMs! - _positionMs!))
                      .millisecondsSinceEpoch ~/
                  1000
            : null,
      );
      debugPrint(
        '🎵 Discord presence updated: $_currentSongTitle by $_currentArtist',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to update Discord presence: $e');
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  /// Dispose the service
  void dispose() {
    disconnect();
    _instance = null;
  }
}
