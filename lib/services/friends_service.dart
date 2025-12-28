import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Service for Friends API operations
class FriendsService {
  static final FriendsService _instance = FriendsService._internal();
  factory FriendsService() => _instance;
  FriendsService._internal();

  final _storage = const FlutterSecureStorage();
  String get _baseUrl => AppConfig.apiBaseUrl;

  Future<String?> get _token async => await _storage.read(key: 'auth_token');

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  // =======================
  // Friend Search
  // =======================

  /// Search for a user by exact username
  Future<SearchUserResult?> searchUser(String username) async {
    final token = await _token;
    if (token == null) return null;

    final response = await http.get(
      Uri.parse('$_baseUrl/friends/search?username=${Uri.encodeComponent(username)}'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return SearchUserResult(
        user: UserInfo.fromJson(data['user']),
        status: data['status'] as String,
      );
    } else if (response.statusCode == 404) {
      return null; // User not found
    }
    
    throw ApiException(response.statusCode, 'Failed to search user');
  }

  // =======================
  // Friend Requests
  // =======================

  /// Send a friend request to a user
  Future<SendRequestResult> sendFriendRequest(String userId) async {
    final token = await _token;
    if (token == null) throw ApiException(401, 'Not authenticated');

    final response = await http.post(
      Uri.parse('$_baseUrl/friends/request'),
      headers: _authHeaders(token),
      body: jsonEncode({'user_id': userId}),
    );

    if (response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return SendRequestResult(
        success: true,
        message: data['message'],
        requestId: data['request_id'],
        status: 'request_sent',
      );
    } else if (response.statusCode == 200) {
      // Mutual request - auto-accepted
      final data = jsonDecode(response.body);
      return SendRequestResult(
        success: true,
        message: data['message'],
        status: data['status'] ?? 'friends',
      );
    } else if (response.statusCode == 409) {
      final data = jsonDecode(response.body);
      throw ApiException(409, data['error']);
    }

    throw ApiException(response.statusCode, 'Failed to send friend request');
  }

  /// Get incoming friend requests
  Future<List<FriendRequest>> getFriendRequests() async {
    final token = await _token;
    if (token == null) return [];

    final response = await http.get(
      Uri.parse('$_baseUrl/friends/requests'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final requests = data['requests'] as List? ?? [];
      return requests.map<FriendRequest>((r) => FriendRequest.fromJson(r as Map<String, dynamic>)).toList();
    }

    return <FriendRequest>[];
  }

  /// Get sent friend requests
  Future<List<SentFriendRequest>> getSentRequests() async {
    final token = await _token;
    if (token == null) return [];

    final response = await http.get(
      Uri.parse('$_baseUrl/friends/requests/sent'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final requests = data['requests'] as List? ?? [];
      return requests.map<SentFriendRequest>((r) => SentFriendRequest.fromJson(r as Map<String, dynamic>)).toList();
    }

    return <SentFriendRequest>[];
  }

  /// Accept a friend request
  Future<bool> acceptFriendRequest(String requestId) async {
    final token = await _token;
    if (token == null) return false;

    final response = await http.post(
      Uri.parse('$_baseUrl/friends/requests/$requestId/accept'),
      headers: _authHeaders(token),
    );

    return response.statusCode == 200;
  }

  /// Reject a friend request
  Future<bool> rejectFriendRequest(String requestId) async {
    final token = await _token;
    if (token == null) return false;

    final response = await http.post(
      Uri.parse('$_baseUrl/friends/requests/$requestId/reject'),
      headers: _authHeaders(token),
    );

    return response.statusCode == 200;
  }

  /// Cancel a sent friend request
  Future<bool> cancelFriendRequest(String requestId) async {
    final token = await _token;
    if (token == null) return false;

    final response = await http.delete(
      Uri.parse('$_baseUrl/friends/requests/$requestId'),
      headers: _authHeaders(token),
    );

    return response.statusCode == 200;
  }

  // =======================
  // Friends List
  // =======================

  /// Get user's friends list
  Future<List<Friend>> getFriends() async {
    final token = await _token;
    if (token == null) return [];

    final response = await http.get(
      Uri.parse('$_baseUrl/friends'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final friends = data['friends'] as List? ?? [];
      return friends.map<Friend>((f) => Friend.fromJson(f as Map<String, dynamic>)).toList();
    }

    return <Friend>[];
  }

  /// Remove a friend
  Future<bool> removeFriend(String friendId) async {
    final token = await _token;
    if (token == null) return false;

    final response = await http.delete(
      Uri.parse('$_baseUrl/friends/$friendId'),
      headers: _authHeaders(token),
    );

    return response.statusCode == 200;
  }

  // =======================
  // Activity
  // =======================

  /// Update current listening activity
  Future<bool> updateActivity({
    required String songId,
    required String songTitle,
    required String artistName,
    String? albumCover,
    required double progress,
    required int durationMs,
    required int positionMs,
    required bool isPlaying,
    // Additional context for analytics (optional)
    String? playlistId,
    String? context, // "playlist", "album", "library", "search"
    bool shuffleOn = false,
    String repeatMode = 'off', // "off", "all", "one"
  }) async {
    final token = await _token;
    if (token == null) return false;

    final body = <String, dynamic>{
      'song_id': songId,
      'song_title': songTitle,
      'artist_name': artistName,
      'album_cover': albumCover,
      'progress': progress,
      'duration_ms': durationMs,
      'position_ms': positionMs,
      'is_playing': isPlaying,
    };

    // Add optional analytics context
    if (playlistId != null) body['playlist_id'] = playlistId;
    if (context != null) body['context'] = context;
    body['shuffle_on'] = shuffleOn;
    body['repeat_mode'] = repeatMode;

    final response = await http.post(
      Uri.parse('$_baseUrl/activity'),
      headers: _authHeaders(token),
      body: jsonEncode(body),
    );

    return response.statusCode == 200;
  }

  /// Clear current activity (when paused/stopped)
  Future<bool> clearActivity() async {
    final token = await _token;
    if (token == null) return false;

    final response = await http.delete(
      Uri.parse('$_baseUrl/activity'),
      headers: _authHeaders(token),
    );

    return response.statusCode == 200;
  }

  /// Get friends activity (fallback if WebSocket not connected)
  Future<List<FriendActivityData>> getFriendsActivity() async {
    final token = await _token;
    if (token == null) return [];

    final response = await http.get(
      Uri.parse('$_baseUrl/activity/friends'),
      headers: _authHeaders(token),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final activities = data['activities'] as List? ?? [];
      return activities.map<FriendActivityData>((a) => FriendActivityData.fromJson(a as Map<String, dynamic>)).toList();
    }

    return <FriendActivityData>[];
  }
}

// =======================
// Data Models
// =======================

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class UserInfo {
  final String id;
  final String username;
  final String photoUrl;

  UserInfo({required this.id, required this.username, required this.photoUrl});

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      photoUrl: json['photo_url'] as String? ?? '',
    );
  }
}

class SearchUserResult {
  final UserInfo user;
  final String status; // 'none', 'friends', 'request_sent', 'request_received'

  SearchUserResult({required this.user, required this.status});
}

class SendRequestResult {
  final bool success;
  final String message;
  final String? requestId;
  final String status;

  SendRequestResult({
    required this.success,
    required this.message,
    this.requestId,
    required this.status,
  });
}

class FriendRequest {
  final String id;
  final UserInfo fromUser;
  final DateTime createdAt;

  FriendRequest({required this.id, required this.fromUser, required this.createdAt});

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] as String? ?? '',
      fromUser: UserInfo.fromJson(json['from_user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

class SentFriendRequest {
  final String id;
  final UserInfo toUser;
  final DateTime createdAt;

  SentFriendRequest({required this.id, required this.toUser, required this.createdAt});

  factory SentFriendRequest.fromJson(Map<String, dynamic> json) {
    return SentFriendRequest(
      id: json['id'] as String? ?? '',
      toUser: UserInfo.fromJson(json['to_user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

class Friend {
  final String id;
  final String username;
  final String photoUrl;
  final bool isOnline;
  final String? currentSong;
  final String? currentArtist;
  final double? progress;
  final DateTime friendsSince;

  Friend({
    required this.id,
    required this.username,
    required this.photoUrl,
    this.isOnline = false,
    this.currentSong,
    this.currentArtist,
    this.progress,
    required this.friendsSince,
  });

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      photoUrl: json['photo_url'] as String? ?? '',
      isOnline: json['is_online'] as bool? ?? false,
      currentSong: json['current_song'] as String?,
      currentArtist: json['current_artist'] as String?,
      progress: (json['progress'] as num?)?.toDouble(),
      friendsSince: DateTime.parse(json['friends_since'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

class FriendActivityData {
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

  FriendActivityData({
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

  factory FriendActivityData.fromJson(Map<String, dynamic> json) {
    return FriendActivityData(
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
