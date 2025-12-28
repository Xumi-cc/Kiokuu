import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// Real-time WebSocket service for friend activity updates
class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final _storage = const FlutterSecureStorage();
  
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const Duration _pingInterval = Duration(seconds: 30);

  // Stream controllers for different message types
  final _activityController = StreamController<FriendActivity>.broadcast();
  final _friendOnlineController = StreamController<FriendStatus>.broadcast();
  final _friendOfflineController = StreamController<FriendStatus>.broadcast();
  final _friendsActivityController = StreamController<List<FriendActivity>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _hqUpgradeController = StreamController<HQUpgradeNotification>.broadcast();
  final _sessionInvalidatedController = StreamController<String>.broadcast(); // Reason for invalidation

  // Public streams
  Stream<FriendActivity> get onActivityUpdate => _activityController.stream;
  Stream<FriendStatus> get onFriendOnline => _friendOnlineController.stream;
  Stream<FriendStatus> get onFriendOffline => _friendOfflineController.stream;
  Stream<List<FriendActivity>> get onFriendsActivity => _friendsActivityController.stream;
  Stream<bool> get onConnectionStateChange => _connectionStateController.stream;
  Stream<HQUpgradeNotification> get onHQUpgrade => _hqUpgradeController.stream;
  Stream<String> get onSessionInvalidated => _sessionInvalidatedController.stream;

  bool get isConnected => _channel != null;

  /// Connect to WebSocket server
  Future<void> connect() async {
    if (_isConnecting || isConnected) return;
    
    _isConnecting = true;
    _shouldReconnect = true;

    try {
      final token = await _storage.read(key: 'auth_token');
      if (token == null) {
        debugPrint('WebSocket: No auth token, cannot connect');
        _isConnecting = false;
        return;
      }

      final wsUrl = '${AppConfig.wsBaseUrl}?token=$token';
      debugPrint('WebSocket: Connecting to $wsUrl');

      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // Wait for connection to be ready
      await _channel!.ready;
      
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStateController.add(true);
      debugPrint('WebSocket: Connected successfully');

      // Start ping timer to keep connection alive
      _startPingTimer();

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      // Request initial friends activity
      requestFriendsActivity();

    } catch (e) {
      debugPrint('WebSocket: Connection failed: $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _connectionStateController.add(false);
    debugPrint('WebSocket: Disconnected');
  }

  /// Send a message to the server
  void _send(Map<String, dynamic> message) {
    if (_channel == null) return;
    _channel!.sink.add(jsonEncode(message));
  }

  /// Request friends activity from server
  void requestFriendsActivity() {
    _send({'type': 'get_friends_activity'});
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final type = message['type'] as String?;
      final payload = message['payload'];

      switch (type) {
        case 'activity':
          if (payload != null) {
            final activity = FriendActivity.fromJson(payload as Map<String, dynamic>);
            _activityController.add(activity);
          }
          break;

        case 'friend_online':
          if (payload != null) {
            final status = FriendStatus.fromJson(payload as Map<String, dynamic>);
            _friendOnlineController.add(status);
          }
          break;

        case 'friend_offline':
          if (payload != null) {
            final status = FriendStatus.fromJson(payload as Map<String, dynamic>);
            _friendOfflineController.add(status);
          }
          break;

        case 'friends_activity':
          if (payload != null && payload is List) {
            final activities = payload
                .map((e) => FriendActivity.fromJson(e as Map<String, dynamic>))
                .toList();
            _friendsActivityController.add(activities);
          }
          break;

        case 'pong':
          // Ping response received, connection is alive
          break;

        case 'hq_upgrade':
          if (payload != null) {
            final notification = HQUpgradeNotification.fromJson(payload as Map<String, dynamic>);
            _hqUpgradeController.add(notification);
            debugPrint('WebSocket: HQ upgrade notification received for ${notification.songTitle}');
          }
          break;

        case 'session_invalidated':
          // Server has invalidated this user's session (admin action, password change, etc.)
          final reason = payload?['reason'] as String? ?? 'Session expired';
          debugPrint('WebSocket: Session invalidated! Reason: $reason');
          _sessionInvalidatedController.add(reason);
          // Stop reconnecting since session is invalid
          _shouldReconnect = false;
          disconnect();
          break;

        default:
          debugPrint('WebSocket: Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('WebSocket: Error parsing message: $e');
    }
  }

  void _handleError(dynamic error) {
    debugPrint('WebSocket: Error: $error');
    _scheduleReconnect();
  }

  void _handleDisconnect() {
    debugPrint('WebSocket: Connection closed');
    _channel = null;
    _pingTimer?.cancel();
    _connectionStateController.add(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('WebSocket: Max reconnect attempts reached');
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    
    final delay = _reconnectDelay * _reconnectAttempts;
    debugPrint('WebSocket: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    
    _reconnectTimer = Timer(delay, connect);
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      _send({'type': 'ping'});
    });
  }

  /// Dispose all resources
  void dispose() {
    disconnect();
    _activityController.close();
    _friendOnlineController.close();
    _friendOfflineController.close();
    _friendsActivityController.close();
    _connectionStateController.close();
    _hqUpgradeController.close();
    _sessionInvalidatedController.close();
  }
}

// =======================
// Data Models
// =======================

class FriendActivity {
  final String userId;
  final String username;
  final String photoUrl;
  final String? songId;
  final String? songTitle;
  final String? artistName;
  final String? albumCover;
  final double progress;
  final int? durationMs;
  final int? positionMs;
  final bool isPlaying;
  final int updatedAt;

  FriendActivity({
    required this.userId,
    required this.username,
    required this.photoUrl,
    this.songId,
    this.songTitle,
    this.artistName,
    this.albumCover,
    this.progress = 0.0,
    this.durationMs,
    this.positionMs,
    this.isPlaying = false,
    required this.updatedAt,
  });

  factory FriendActivity.fromJson(Map<String, dynamic> json) {
    return FriendActivity(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      photoUrl: json['photo_url'] as String? ?? '',
      songId: json['song_id'] as String?,
      songTitle: json['song_title'] as String?,
      artistName: json['artist_name'] as String?,
      albumCover: json['album_cover'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      durationMs: json['duration_ms'] as int?,
      positionMs: json['position_ms'] as int?,
      isPlaying: json['is_playing'] as bool? ?? false,
      updatedAt: json['updated_at'] as int? ?? 0,
    );
  }
}

class FriendStatus {
  final String userId;
  final String username;
  final String photoUrl;

  FriendStatus({
    required this.userId,
    required this.username,
    required this.photoUrl,
  });

  factory FriendStatus.fromJson(Map<String, dynamic> json) {
    return FriendStatus(
      userId: json['user_id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      photoUrl: json['photo_url'] as String? ?? '',
    );
  }
}

class HQUpgradeNotification {
  final String songId;
  final String songTitle;

  HQUpgradeNotification({
    required this.songId,
    required this.songTitle,
  });

  factory HQUpgradeNotification.fromJson(Map<String, dynamic> json) {
    return HQUpgradeNotification(
      songId: json['song_id'] as String? ?? '',
      songTitle: json['song_title'] as String? ?? '',
    );
  }
}
