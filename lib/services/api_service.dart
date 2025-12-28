import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'google_auth_service.dart';
import 'discord_auth_service.dart';
import '../config/app_config.dart';

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  final _storage = const FlutterSecureStorage();
  final _googleAuth = GoogleAuthService();
  final _discordAuth = DiscordAuthService();

  // Callback for session expiration - set this from main app
  static Function? onSessionExpired;

  // Connection state tracking
  static bool _isOnline = true;
  static final _connectionStateController = StreamController<bool>.broadcast();
  static Stream<bool> get onConnectionStateChange =>
      _connectionStateController.stream;
  static bool get isOnline => _isOnline;

  // Callback when connection is restored
  static Function? onReconnected;

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 1);
  static const Duration _requestTimeout = Duration(seconds: 15);

  /// Build a CDN URL from an API response.
  /// Prefers the full URL from API (e.g., cover_url) which contains the correct server domain.
  /// Falls back to constructing from path only for legacy data.
  ///
  /// Usage:
  ///   ApiService.getCdnUrl(data['cover_url'], data['cover_path'])
  ///   ApiService.getCdnUrl(data['image_url'], data['image_path'])
  static String? getCdnUrl(String? fullUrl, String? relativePath) {
    // Prefer full URL from API (contains correct server domain)
    if (fullUrl != null && fullUrl.isNotEmpty) {
      return fullUrl;
    }
    // Fallback: construct from relative path (legacy)
    if (relativePath != null && relativePath.isNotEmpty) {
      if (relativePath.startsWith('http')) {
        return relativePath;
      }
      return '$baseUrl/$relativePath';
    }
    return null;
  }

  /// Convenience method when you have an image_url or image_path field
  static String? getImageUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    return getCdnUrl(
      data['image_url'] as String?,
      data['image_path'] as String?,
    );
  }

  /// Convenience method when you have a cover_url or cover_path field
  static String? getCoverUrl(Map<String, dynamic>? data) {
    if (data == null) return null;
    return getCdnUrl(
      data['cover_url'] as String?,
      data['cover_path'] as String?,
    );
  }

  Future<String?> get _token async => await _storage.read(key: 'auth_token');
  Future<String?> get username async => await _storage.read(key: 'username');

  // Helper to handle 401 responses
  Future<void> _handleUnauthorized() async {
    await _storage.deleteAll();
    onSessionExpired?.call();
  }

  // Check if response is unauthorized and handle it
  bool _checkUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      _handleUnauthorized();
      return true;
    }
    return false;
  }

  /// Update connection state and notify listeners
  static void _setOnlineState(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      _connectionStateController.add(online);
      debugPrint(online ? '🌐 API: Back online' : '📴 API: Offline');

      if (online && onReconnected != null) {
        onReconnected!();
      }
    }
  }

  /// Wrapper for HTTP GET with retry logic
  Future<http.Response> _getWithRetry(
    Uri url, {
    Map<String, String>? headers,
    int retries = _maxRetries,
  }) async {
    int attempt = 0;
    Duration delay = _initialRetryDelay;

    while (true) {
      try {
        final response = await http
            .get(url, headers: headers)
            .timeout(_requestTimeout);
        _setOnlineState(true);
        return response;
      } on SocketException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after SocketException: $e');
        await Future.delayed(delay);
        delay *= 2; // Exponential backoff
      } on TimeoutException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after timeout: $e');
        await Future.delayed(delay);
        delay *= 2;
      } on HttpException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after HttpException: $e');
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// Wrapper for HTTP POST with retry logic
  Future<http.Response> _postWithRetry(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    int retries = _maxRetries,
  }) async {
    int attempt = 0;
    Duration delay = _initialRetryDelay;

    while (true) {
      try {
        final response = await http
            .post(url, headers: headers, body: body)
            .timeout(_requestTimeout);
        _setOnlineState(true);
        return response;
      } on SocketException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after SocketException: $e');
        await Future.delayed(delay);
        delay *= 2;
      } on TimeoutException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after timeout: $e');
        await Future.delayed(delay);
        delay *= 2;
      } on HttpException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after HttpException: $e');
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// Wrapper for HTTP PUT with retry logic
  Future<http.Response> _putWithRetry(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    int retries = _maxRetries,
  }) async {
    int attempt = 0;
    Duration delay = _initialRetryDelay;

    while (true) {
      try {
        final response = await http
            .put(url, headers: headers, body: body)
            .timeout(_requestTimeout);
        _setOnlineState(true);
        return response;
      } on SocketException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after SocketException: $e');
        await Future.delayed(delay);
        delay *= 2;
      } on TimeoutException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after timeout: $e');
        await Future.delayed(delay);
        delay *= 2;
      } on HttpException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after HttpException: $e');
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  /// Wrapper for HTTP DELETE with retry logic
  Future<http.Response> _deleteWithRetry(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    int retries = _maxRetries,
  }) async {
    int attempt = 0;
    Duration delay = _initialRetryDelay;

    while (true) {
      try {
        final response = await http
            .delete(url, headers: headers, body: body)
            .timeout(_requestTimeout);
        _setOnlineState(true);
        return response;
      } on SocketException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after SocketException: $e');
        await Future.delayed(delay);
        delay *= 2;
      } on TimeoutException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after timeout: $e');
        await Future.delayed(delay);
        delay *= 2;
      } on HttpException catch (e) {
        attempt++;
        _setOnlineState(false);
        if (attempt >= retries) rethrow;
        debugPrint('🔄 API retry $attempt/$retries after HttpException: $e');
        await Future.delayed(delay);
        delay *= 2;
      }
    }
  }

  // Auth
  Future<bool> login(String username, String password) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/login'),
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.write(key: 'auth_token', value: data['token']);
      await _storage.write(key: 'user_id', value: data['user_id']);
      await _storage.write(key: 'username', value: username);
      return true;
    }
    return false;
  }

  Future<bool> signup(String username, String email, String password) async {
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/signup'),
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );
    return response.statusCode == 201;
  }

  // Google Sign-In (works on all platforms)
  Future<Map<String, dynamic>> signInWithGoogle() async {
    return await _googleAuth.signIn();
  }

  // Discord Sign-In (works on all platforms)
  Future<Map<String, dynamic>> signInWithDiscord() async {
    return await _discordAuth.signIn();
  }

  Future<void> logout() async {
    final token = await _token;
    if (token != null) {
      await _postWithRetry(
        Uri.parse('$baseUrl/logout'),
        headers: {'Authorization': 'Bearer $token'},
      );
    }
    await _googleAuth.signOut();
    await _discordAuth.signOut();
    await _storage.deleteAll();
  }

  // Validate token with server (used by splash screen - doesn't trigger callback)
  Future<bool> validateSession() async {
    final token = await _token;
    if (token == null) return false;

    final response = await _getWithRetry(
      Uri.parse('$baseUrl/liked-songs'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 401) {
      // Just clear storage, don't trigger callback (splash handles navigation)
      await _storage.deleteAll();
      return false;
    }
    return response.statusCode == 200;
  }

  // Songs
  Future<Map<String, dynamic>?> getSong(String id) async {
    try {
      final token = await _token;
      final response = await _getWithRetry(
        Uri.parse('$baseUrl/songs/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_checkUnauthorized(response)) return null;

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error getting song: $e');
    }
    return null;
  }

  /// Returns a playlist-like map with: id, name, description, song_count, cover_images, songs
  Future<Map<String, dynamic>?> getLikedSongs() async {
    try {
      final token = await _token;
      final response = await _getWithRetry(
        Uri.parse('$baseUrl/liked-songs'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_checkUnauthorized(response)) return null;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        // Backwards compatibility: if it's a list, wrap it
        if (decoded is List) {
          return {
            'id': 'liked-songs',
            'name': 'Liked Songs',
            'description': 'Your favorite tracks',
            'song_count': decoded.length,
            'cover_images': <String>[],
            'songs': decoded,
          };
        }
      }
    } catch (e) {
      debugPrint('Error getting liked songs: $e');
    }
    return null;
  }

  Future<bool> likeSong(String id) async {
    final token = await _token;
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/songs/$id/like'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  // Playlists

  /// Get all playlists for the current user
  /// [type] - Optional filter: 'playlists', 'albums', 'artists'
  Future<List<dynamic>> getPlaylists({String? type}) async {
    try {
      final token = await _token;
      var url = '$baseUrl/playlists';
      if (type != null && type != 'All') {
        url += '?type=${type.toLowerCase()}';
      }
      final response = await _getWithRetry(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_checkUnauthorized(response)) return [];

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('Error getting playlists: $e');
    }
    return [];
  }

  /// Create a new playlist
  Future<Map<String, dynamic>?> createPlaylist(
    String name, {
    String description = '',
    bool isPublic = false,
  }) async {
    final token = await _token;
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/playlists'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'name': name,
        'description': description,
        'is_public': isPublic,
      }),
    );

    if (_checkUnauthorized(response)) return null;

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    return null;
  }

  /// Get a single playlist with its songs
  Future<Map<String, dynamic>?> getPlaylist(String id) async {
    try {
      final token = await _token;
      final response = await _getWithRetry(
        Uri.parse('$baseUrl/playlists/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_checkUnauthorized(response)) return null;

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error getting playlist: $e');
    }
    return null;
  }

  /// Update a playlist's metadata
  Future<bool> updatePlaylist(
    String id, {
    String? name,
    String? description,
    bool? isPublic,
  }) async {
    final token = await _token;
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (isPublic != null) body['is_public'] = isPublic;

    final response = await _putWithRetry(
      Uri.parse('$baseUrl/playlists/$id'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  /// Delete a playlist
  Future<bool> deletePlaylist(String id) async {
    final token = await _token;
    final response = await _deleteWithRetry(
      Uri.parse('$baseUrl/playlists/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  /// Add a song to a playlist
  Future<bool> addSongToPlaylist(String playlistId, String songId) async {
    final token = await _token;
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/songs'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'song_id': songId}),
    );

    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  /// Remove a song from a playlist
  Future<bool> removeSongFromPlaylist(String playlistId, String songId) async {
    final token = await _token;
    final response = await _deleteWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/songs/$songId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  /// Get playlist IDs that contain a specific song
  Future<Set<String>> getSongPlaylists(String songId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/songs/$songId/playlists'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (_checkUnauthorized(response)) return {};

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded.cast<String>().toSet();
      }
    }
    return {};
  }

  /// Reorder a song in a playlist
  Future<bool> reorderPlaylistSong(
    String playlistId,
    String songId,
    int newPosition,
  ) async {
    final token = await _token;
    final response = await _putWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/reorder'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'song_id': songId, 'position': newPosition}),
    );

    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  // Upload - returns (success, message)
  Future<(bool, String)> uploadSong(String spotifyId, String filePath) async {
    try {
      final token = await _token;
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      request.headers['Authorization'] = 'Bearer $token';
      request.fields['spotify_id'] = spotifyId;
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      // 10 minute timeout for slow downloads from mirrors
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          throw TimeoutException(
            'Upload timed out. The server may still be processing.',
          );
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (false, 'Authentication failed. Please log in again.');
      }

      if (response.statusCode == 402) {
        return (
          false,
          'SUBSCRIPTION_REQUIRED:Subscription required to upload music. Please subscribe to KioKuu Basic or Pro.',
        );
      }

      if (response.statusCode == 200) {
        // Try to extract song_id from response
        try {
          final data = jsonDecode(response.body);
          final source = data['source'] ?? 'unknown';
          return (true, 'Song uploaded successfully! (Source: $source)');
        } catch (_) {
          return (true, 'Song uploaded successfully!');
        }
      } else {
        // Try to extract error message from response
        try {
          final data = jsonDecode(response.body);
          final errorMsg =
              (data['error'] as String?) ??
              'Upload failed (${response.statusCode})';
          return (false, errorMsg);
        } catch (_) {
          return (false, 'Upload failed (${response.statusCode})');
        }
      }
    } on TimeoutException catch (e) {
      return (false, e.message ?? 'Upload timed out');
    } catch (e) {
      return (false, 'Upload error: $e');
    }
  }

  /// Search for tracks on Spotify by name
  Future<List<Map<String, dynamic>>> searchSpotifyTracks(
    String query, {
    int limit = 20,
  }) async {
    try {
      final token = await _token;
      final response = await _getWithRetry(
        Uri.parse(
          '$baseUrl/spotify/search?q=${Uri.encodeComponent(query)}&limit=$limit',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_checkUnauthorized(response)) return [];

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tracks = data['tracks'] as List<dynamic>?;
        return tracks?.cast<Map<String, dynamic>>() ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  /// AI-powered song matching (Premium+ only)
  /// Returns the best Spotify match using AI reasoning
  Future<Map<String, dynamic>?> aiMatch({
    required String title,
    String? artist,
    String? album,
  }) async {
    try {
      final token = await _token;
      final response = await _postWithRetry(
        Uri.parse('$baseUrl/ai/match'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': title,
          if (artist != null) 'artist': artist,
          if (album != null) 'album': album,
        }),
      );

      if (_checkUnauthorized(response)) return null;

      // 403 = not premium
      if (response.statusCode == 403) {
        debugPrint('⚠️ AI match failed: Premium required');
        return {'error': 'premium_required'};
      }

      // 404 = no Spotify results found
      if (response.statusCode == 404) {
        debugPrint(
          '⚠️ AI match failed: No Spotify results found for "$title" by "$artist"',
        );
        return {'error': 'no_spotify_results'};
      }

      // 500 = internal error (Spotify search failed, AI API failed, etc)
      if (response.statusCode == 500) {
        try {
          final data = jsonDecode(response.body);
          debugPrint('⚠️ AI match failed: ${data['error']}');
        } catch (_) {
          debugPrint('⚠️ AI match failed: Server error');
        }
        return {'error': 'server_error'};
      }

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }

      debugPrint(
        '⚠️ AI match failed with status ${response.statusCode}: ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('⚠️ AI match exception: $e');
      return null;
    }
  }

  /// Upload with real progress tracking using TUS protocol (2MB chunks)
  /// Falls back to regular multipart upload if TUS fails
  /// [onProgress] callback receives a value from 0.0 to 1.0
  Future<(bool, String)> uploadSongWithProgress(
    String spotifyId,
    String filePath, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final token = await _token;
      if (token == null) {
        return (false, 'Not authenticated');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        return (false, 'File not found');
      }

      final fileSize = await file.length();
      final fileName = filePath.split('/').last;

      debugPrint(
        '📤 Starting TUS upload: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)',
      );

      // Use TUS protocol for chunked resumable uploads (2MB chunks)
      // No fallback - Cloudflare doesn't like large single-request uploads
      return await _uploadWithTus(spotifyId, filePath, onProgress: onProgress);
    } catch (e) {
      debugPrint('❌ Upload failed: $e');
      return (false, 'Upload error: $e');
    }
  }

  /// TUS protocol upload with 2MB chunks (manual implementation)
  /// Implements TUS 1.0.0 protocol for resumable uploads
  Future<(bool, String)> _uploadWithTus(
    String spotifyId,
    String filePath, {
    void Function(double progress)? onProgress,
  }) async {
    final token = await _token;
    if (token == null) {
      return (false, 'Not authenticated');
    }

    final file = File(filePath);
    final fileSize = await file.length();
    final fileName = filePath.split('/').last;

    debugPrint(
      '📤 Starting TUS upload: $fileName (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)',
    );

    try {
      // Step 1: Create TUS upload session
      final createResponse = await http.post(
        Uri.parse('$baseUrl/tus/'),
        headers: {
          'Authorization': 'Bearer $token',
          'Tus-Resumable': '1.0.0',
          'Upload-Length': fileSize.toString(),
          'Upload-Metadata':
              'spotify_id ${base64Encode(utf8.encode(spotifyId))}, filename ${base64Encode(utf8.encode(fileName))}',
          'Content-Type': 'application/offset+octet-stream',
        },
      );

      // Check if song already exists
      if (createResponse.statusCode == 200) {
        try {
          final data = jsonDecode(createResponse.body);
          if (data['status'] == 'exists') {
            onProgress?.call(1.0);
            return (true, 'Song already in library');
          }
        } catch (_) {}
      }

      if (createResponse.statusCode != 201) {
        debugPrint(
          '⚠️ TUS create failed: ${createResponse.statusCode} - ${createResponse.body}',
        );
        throw Exception('TUS create failed: ${createResponse.statusCode}');
      }

      // Get upload URL from Location header
      var uploadUrl = createResponse.headers['location'];
      if (uploadUrl == null) {
        throw Exception('No upload URL returned from TUS server');
      }

      // Handle relative URLs - prepend baseUrl if needed
      if (!uploadUrl.startsWith('http')) {
        uploadUrl = '$baseUrl$uploadUrl';
      }

      debugPrint('📤 TUS upload URL: $uploadUrl');

      // Step 2: Upload file in 2MB chunks with real-time progress
      const chunkSize = 2 * 1024 * 1024; // 2MB chunks
      int totalBytesUploaded = 0;

      // Read entire file into memory for chunking
      final allBytes = await file.readAsBytes();

      while (totalBytesUploaded < fileSize) {
        final end = (totalBytesUploaded + chunkSize).clamp(0, fileSize);
        final chunkData = allBytes.sublist(totalBytesUploaded, end);
        final chunkOffset = totalBytesUploaded;

        // Use StreamedRequest for real-time progress
        final request = http.StreamedRequest('PATCH', Uri.parse(uploadUrl));
        request.headers.addAll({
          'Authorization': 'Bearer $token',
          'Tus-Resumable': '1.0.0',
          'Upload-Offset': chunkOffset.toString(),
          'Content-Type': 'application/offset+octet-stream',
          'Content-Length': chunkData.length.toString(),
        });

        // Track bytes as they're being sent
        int bytesSentInChunk = 0;
        const updateInterval = 65536; // Update every 64KB
        int lastUpdate = 0;

        // Split data into small pieces for progress tracking
        const pieceSize = 65536; // 64KB pieces
        int pieceOffset = 0;

        Future<void> sendChunk() async {
          while (pieceOffset < chunkData.length) {
            final pieceEnd = (pieceOffset + pieceSize).clamp(
              0,
              chunkData.length,
            );
            final piece = chunkData.sublist(pieceOffset, pieceEnd);
            request.sink.add(piece);

            bytesSentInChunk += piece.length;
            pieceOffset = pieceEnd;

            // Update progress
            if (bytesSentInChunk - lastUpdate >= updateInterval ||
                pieceOffset >= chunkData.length) {
              lastUpdate = bytesSentInChunk;
              final totalSent = chunkOffset + bytesSentInChunk;
              final progress = (totalSent / fileSize).clamp(0.0, 0.95);
              onProgress?.call(progress);
            }
          }
          await request.sink.close();
        }

        // Start sending data
        sendChunk();

        // Wait for response
        final streamedResponse = await request.send();
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode != 204) {
          debugPrint(
            '⚠️ TUS chunk failed at offset $chunkOffset: ${response.statusCode}',
          );
          throw Exception('Chunk upload failed at offset $chunkOffset');
        }

        totalBytesUploaded = end;
        debugPrint(
          '📤 TUS chunk complete: ${(totalBytesUploaded / fileSize * 100).toStringAsFixed(0)}%',
        );
      }

      onProgress?.call(1.0);
      debugPrint('✅ TUS upload complete: $fileName');
      return (true, 'Song uploaded successfully!');
    } catch (e) {
      debugPrint('❌ TUS upload error: $e');
      rethrow;
    }
  }

  // Artist System
  Future<(bool, int?)> followArtist(String artistId) async {
    final token = await _token;
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/artists/$artistId/follow'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return (false, null);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (true, data['follower_count'] as int?);
    }
    return (false, null);
  }

  Future<Map<String, dynamic>?> getArtist(String artistId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/artists/$artistId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return null;

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getFollowedArtists() async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/artists/followed'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return [];

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['artists'] ?? []);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getArtistSongs(String artistId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/artists/$artistId/songs'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return [];

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['songs']);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> getArtistAlbums(String artistId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/artists/$artistId/albums'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return [];

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['albums']);
    }
    return [];
  }

  Future<(bool, int?)> unfollowArtist(String artistId) async {
    final token = await _token;
    final response = await _deleteWithRetry(
      Uri.parse('$baseUrl/artists/$artistId/follow'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return (false, null);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (true, data['follower_count'] as int?);
    }
    return (false, null);
  }

  Future<bool> checkArtistFollowStatus(String artistId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/artists/$artistId/status'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return false;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['is_following'] ?? false;
    }
    return false;
  }

  Future<Map<String, dynamic>?> getArtistFromSong(String songId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/songs/$songId/artist'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return null;

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // Liked Playlists

  /// Like a playlist (add to favorites)
  Future<bool> likePlaylist(String playlistId) async {
    final token = await _token;
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/like'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  /// Unlike a playlist (remove from favorites)
  Future<bool> unlikePlaylist(String playlistId) async {
    final token = await _token;
    final response = await _deleteWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/like'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  /// Check if a playlist is liked
  Future<bool> checkPlaylistLikeStatus(String playlistId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/like'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return false;

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['is_liked'] ?? false;
    }
    return false;
  }

  /// Get all liked playlists
  Future<List<dynamic>> getLikedPlaylists() async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/liked-playlists'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return [];

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded;
      }
    }
    return [];
  }

  // ======================= PLAYLIST SHARING =======================

  /// Create a share link for a playlist (7 days expiration)
  Future<Map<String, dynamic>?> createShareLink(String playlistId) async {
    final token = await _token;
    final response = await _postWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/share'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return null;

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  /// Get all share links for a playlist
  Future<List<dynamic>> getShareLinks(String playlistId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/shares'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return [];

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is List) {
        return decoded;
      }
    }
    return [];
  }

  /// Revoke a share link with optional reason
  Future<bool> revokeShareLink(
    String playlistId,
    String shareId, {
    String? reason,
  }) async {
    final token = await _token;
    final response = await _deleteWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/shares/$shareId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: reason != null ? jsonEncode({'reason': reason}) : null,
    );
    if (_checkUnauthorized(response)) return false;
    return response.statusCode == 200;
  }

  /// Get sharing statistics for a playlist
  Future<Map<String, dynamic>?> getShareStats(String playlistId) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/playlists/$playlistId/share-stats'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return null;

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  /// Access a shared playlist via token (requires auth)
  Future<Map<String, dynamic>?> getSharedPlaylist(String shareToken) async {
    final token = await _token;
    final response = await _getWithRetry(
      Uri.parse('$baseUrl/share/$shareToken'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (_checkUnauthorized(response)) return null;

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 403 || response.statusCode == 410) {
      // Return error info for revoked/expired links
      return jsonDecode(response.body);
    }
    return null;
  }

  /// Check if user has access to stream content
  /// Returns (hasAccess, errorMessage)
  Future<(bool, String?)> checkStreamAccess(String songId) async {
    final token = await _token;
    if (token == null) return (false, 'Not authenticated');

    try {
      final response = await http.head(
        Uri.parse('$baseUrl/stream/$songId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200 || response.statusCode == 206) {
        return (true, null);
      } else if (response.statusCode == 402) {
        return (
          false,
          'SUBSCRIPTION_REQUIRED:Subscription required to stream music. Please subscribe to KioKuu Basic or Pro.',
        );
      } else if (response.statusCode == 401) {
        await _handleUnauthorized();
        return (false, 'Authentication required');
      } else {
        return (false, 'Stream not available');
      }
    } catch (e) {
      return (false, 'Network error: $e');
    }
  }

  /// Download a song (HLS or full file) to the specified directory
  /// Returns the local playlist path on success, null on failure
  /// If returns a string starting with 'ERROR:', it contains an error message
  Future<String?> downloadSong(
    String songId,
    String folderName,
    String downloadDir, {
    void Function(double progress)? onProgress,
  }) async {
    final token = await _token;
    if (token == null) return null;

    try {
      // First, try to get the HLS playlist
      final playlistResponse = await _getWithRetry(
        Uri.parse('$baseUrl/stream/$songId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (playlistResponse.statusCode != 200) return null;

      final contentType = playlistResponse.headers['content-type'] ?? '';
      final songDir = '$downloadDir/$songId';
      await Directory(songDir).create(recursive: true);

      // Check if it's HLS (m3u8 playlist)
      if (contentType.contains('mpegurl') ||
          playlistResponse.body.contains('#EXTM3U')) {
        // It's HLS - download playlist and all segments
        final playlistContent = playlistResponse.body;

        // Save the playlist
        final playlistFile = File('$songDir/playlist.m3u8');
        await playlistFile.writeAsString(playlistContent);

        // Parse segments from playlist
        final lines = playlistContent.split('\n');
        final segments = <String>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
            // Extract just the segment filename (e.g., segment_000.m4s)
            final segmentName = trimmed.contains('/')
                ? trimmed.split('/').last
                : trimmed;
            segments.add(segmentName);
          }
        }

        // Download init.mp4 if present (fMP4 format)
        try {
          final initResponse = await _getWithRetry(
            Uri.parse('$baseUrl/stream/$songId/init.mp4'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (initResponse.statusCode == 200) {
            await File(
              '$songDir/init.mp4',
            ).writeAsBytes(initResponse.bodyBytes);
          }
        } catch (_) {}

        // Download all segments
        int downloaded = 0;
        for (final segment in segments) {
          final segResponse = await _getWithRetry(
            Uri.parse('$baseUrl/stream/$songId/$segment'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (segResponse.statusCode == 200) {
            await File('$songDir/$segment').writeAsBytes(segResponse.bodyBytes);
          }
          downloaded++;
          if (onProgress != null) {
            onProgress(downloaded / segments.length);
          }
        }

        // Rewrite playlist with local paths
        final localPlaylist = playlistContent
            .replaceAll('/stream/$songId/', '')
            .replaceAll(RegExp(r'URI="/stream/[^/]+/'), 'URI="');
        await playlistFile.writeAsString(localPlaylist);

        return playlistFile.path;
      } else {
        // Legacy: single file - save with original extension
        final ext = contentType.contains('mpeg')
            ? 'mp3'
            : contentType.contains('flac')
            ? 'flac'
            : contentType.contains('ogg')
            ? 'ogg'
            : 'm4a';
        final safeName = folderName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
        final file = File('$songDir/$safeName.$ext');
        await file.writeAsBytes(playlistResponse.bodyBytes);
        onProgress?.call(1.0);
        return file.path;
      }
    } catch (e) {
      return null;
    }
  }

  // ======================= SUBSCRIPTION =======================

  /// Get user's current subscription status
  Future<Map<String, dynamic>?> getSubscription() async {
    try {
      final token = await _token;
      final response = await _getWithRetry(
        Uri.parse('$baseUrl/subscription'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (_checkUnauthorized(response)) return null;

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error getting subscription: $e');
    }
    return null;
  }

  /// Get available subscription plans
  Future<Map<String, dynamic>?> getSubscriptionPlans() async {
    try {
      final token = await _token;
      final response = await _getWithRetry(
        Uri.parse('$baseUrl/subscription/plans'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (_checkUnauthorized(response)) return null;

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('Error getting subscription plans: $e');
    }
    return null;
  }

  /// Create a Stripe checkout session for subscription
  /// Returns checkout URL on success, null on failure
  Future<String?> createCheckoutSession({
    required String plan,
    required String billingCycle,
  }) async {
    try {
      final token = await _token;
      if (token == null) return null;

      final response = await http.post(
        Uri.parse('$baseUrl/subscription/checkout'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'plan': plan, 'billing_cycle': billingCycle}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['checkout_url'] as String?;
      } else {
        debugPrint('Failed to create checkout session: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error creating checkout session: $e');
    }
    return null;
  }
}
