import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

/// Service for fetching analytics data from the backend
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  final _storage = const FlutterSecureStorage();
  String get _baseUrl => AppConfig.apiBaseUrl;

  Future<String?> get _token async => await _storage.read(key: 'auth_token');

  Map<String, String> _authHeaders(String token) => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  /// Explicitly track a song play (for prefetched songs)
  Future<void> trackPlay({
    required String songId,
    String? playlistId,
    String context = 'library',
  }) async {
    final token = await _token;
    if (token == null) return;

    try {
      await http.post(
        Uri.parse('$_baseUrl/analytics/track-play'),
        headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
        body: jsonEncode({
          'song_id': songId,
          if (playlistId != null) 'playlist_id': playlistId,
          'context': context,
        }),
      );
    } catch (e) {
      // Silently fail
    }
  }

  /// Get user's top songs
  /// [period] - "week", "month", "year", or "all"
  Future<List<SongStats>> getTopSongs({
    int limit = 10,
    String period = 'all',
  }) async {
    final token = await _token;
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/top-songs?limit=$limit&period=$period'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songs = data['songs'] as List? ?? [];
        return songs.map((s) => SongStats.fromJson(s)).toList();
      }
    } catch (e) {
      // Silently fail - return empty list
    }
    return [];
  }

  /// Get user's top artists
  Future<List<ArtistStats>> getTopArtists({
    int limit = 10,
    String period = 'all',
  }) async {
    final token = await _token;
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/analytics/top-artists?limit=$limit&period=$period',
        ),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final artists = data['artists'] as List? ?? [];
        return artists.map((a) => ArtistStats.fromJson(a)).toList();
      }
    } catch (e) {
      // Silently fail
    }
    return [];
  }

  /// Get recently played songs
  Future<List<RecentSong>> getRecentlyPlayed({int limit = 20}) async {
    final token = await _token;
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/recently-played?limit=$limit'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final songs = data['songs'] as List? ?? [];
        return songs.map((s) => RecentSong.fromJson(s)).toList();
      }
    } catch (e) {
      // Silently fail
    }
    return [];
  }

  /// Get recently played artists with pagination
  Future<PaginatedArtists> getRecentlyPlayedArtists({
    int limit = 10,
    int offset = 0,
  }) async {
    final token = await _token;
    if (token == null) return PaginatedArtists(artists: [], total: 0);

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/analytics/recently-played-artists?limit=$limit&offset=$offset',
        ),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final artists = (data['artists'] as List? ?? [])
            .map((a) => RecentArtist.fromJson(a))
            .toList();
        final total = data['total'] as int? ?? 0;
        return PaginatedArtists(artists: artists, total: total);
      }
    } catch (e) {
      // Silently fail
    }
    return PaginatedArtists(artists: [], total: 0);
  }

  /// Get recently played albums with pagination
  Future<PaginatedAlbums> getRecentlyPlayedAlbums({
    int limit = 10,
    int offset = 0,
  }) async {
    final token = await _token;
    if (token == null) return PaginatedAlbums(albums: [], total: 0);

    try {
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/analytics/recently-played-albums?limit=$limit&offset=$offset',
        ),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final albums = (data['albums'] as List? ?? [])
            .map((a) => RecentAlbum.fromJson(a))
            .toList();
        final total = data['total'] as int? ?? 0;
        return PaginatedAlbums(albums: albums, total: total);
      }
    } catch (e) {
      // Silently fail
    }
    return PaginatedAlbums(albums: [], total: 0);
  }

  /// Get playlist stats
  Future<List<PlaylistStats>> getPlaylistStats({int limit = 10}) async {
    final token = await _token;
    if (token == null) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/playlists?limit=$limit'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final playlists = data['playlists'] as List? ?? [];
        return playlists.map((p) => PlaylistStats.fromJson(p)).toList();
      }
    } catch (e) {
      // Silently fail
    }
    return [];
  }

  /// Get listening insights
  Future<ListeningInsights?> getInsights({String period = 'month'}) async {
    final token = await _token;
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/insights?period=$period'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ListeningInsights.fromJson(data);
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  /// Get listening streak
  Future<ListeningStreak?> getStreak() async {
    final token = await _token;
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/streak'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return ListeningStreak.fromJson(data);
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  /// Sync the Most Played playlist with current analytics data
  /// Returns the playlist ID if successful
  Future<String?> syncMostPlayedPlaylist() async {
    final token = await _token;
    if (token == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/analytics/sync-most-played'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['playlist_id'] as String?;
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  /// Sync the Recently Played playlist with current analytics data
  /// Returns the playlist ID if successful
  Future<String?> syncRecentlyPlayedPlaylist() async {
    final token = await _token;
    if (token == null) return null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/analytics/sync-recently-played'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['playlist_id'] as String?;
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }

  /// Get the Most Played playlist ID (creates if doesn't exist)
  Future<String?> getMostPlayedPlaylistId() async {
    final token = await _token;
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/analytics/most-played-playlist'),
        headers: _authHeaders(token),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['playlist_id'] as String?;
      }
    } catch (e) {
      // Silently fail
    }
    return null;
  }
}

// =======================
// Data Models
// =======================

class SongStats {
  final String songId;
  final String title;
  final String artistName;
  final String coverPath;
  final String? coverUrl; // Full URL with domain from DB
  final int playCount;
  final int completionCount;
  final int skipCount;
  final int repeatCount;
  final int totalListenedMs;
  final double avgCompletionPct;
  final DateTime? lastPlayedAt;
  final DateTime? firstPlayedAt;

  SongStats({
    required this.songId,
    required this.title,
    required this.artistName,
    required this.coverPath,
    this.coverUrl,
    required this.playCount,
    required this.completionCount,
    required this.skipCount,
    required this.repeatCount,
    required this.totalListenedMs,
    required this.avgCompletionPct,
    this.lastPlayedAt,
    this.firstPlayedAt,
  });

  factory SongStats.fromJson(Map<String, dynamic> json) {
    return SongStats(
      songId: json['song_id'] ?? '',
      title: json['title'] ?? 'Unknown',
      artistName: json['artist_name'] ?? 'Unknown Artist',
      coverPath: json['cover_path'] ?? '',
      coverUrl: json['cover_url'] as String?,
      playCount: json['play_count'] ?? 0,
      completionCount: json['completion_count'] ?? 0,
      skipCount: json['skip_count'] ?? 0,
      repeatCount: json['repeat_count'] ?? 0,
      totalListenedMs: json['total_listened_ms'] ?? 0,
      avgCompletionPct: (json['avg_completion_pct'] as num?)?.toDouble() ?? 0,
      lastPlayedAt: json['last_played_at'] != null
          ? DateTime.tryParse(json['last_played_at'])
          : null,
      firstPlayedAt: json['first_played_at'] != null
          ? DateTime.tryParse(json['first_played_at'])
          : null,
    );
  }
}

class ArtistStats {
  final String artistId;
  final String name;
  final String imagePath;
  final String? imageUrl; // Full URL with domain from DB
  final int playCount;
  final int totalListenedMs;
  final int songCount;

  ArtistStats({
    required this.artistId,
    required this.name,
    required this.imagePath,
    this.imageUrl,
    required this.playCount,
    required this.totalListenedMs,
    required this.songCount,
  });

  factory ArtistStats.fromJson(Map<String, dynamic> json) {
    return ArtistStats(
      artistId: json['artist_id'] ?? '',
      name: json['name'] ?? 'Unknown Artist',
      imagePath: json['image_path'] ?? '',
      imageUrl: json['image_url'] as String?,
      playCount: json['play_count'] ?? 0,
      totalListenedMs: json['total_listened_ms'] ?? 0,
      songCount: json['song_count'] ?? 0,
    );
  }
}

class RecentSong {
  final String songId;
  final String title;
  final String artistName;
  final String coverPath;
  final String? coverUrl; // Full URL with domain from DB
  final DateTime playedAt;

  RecentSong({
    required this.songId,
    required this.title,
    required this.artistName,
    required this.coverPath,
    this.coverUrl,
    required this.playedAt,
  });

  factory RecentSong.fromJson(Map<String, dynamic> json) {
    return RecentSong(
      songId: json['song_id'] ?? '',
      title: json['title'] ?? 'Unknown',
      artistName: json['artist_name'] ?? 'Unknown Artist',
      coverPath: json['cover_path'] ?? '',
      coverUrl: json['cover_url'] as String?,
      playedAt: DateTime.tryParse(json['played_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class PlaylistStats {
  final String playlistId;
  final String name;
  final int startCount;
  final int completionCount;
  final int totalListenedMs;
  final DateTime? lastPlayedAt;

  PlaylistStats({
    required this.playlistId,
    required this.name,
    required this.startCount,
    required this.completionCount,
    required this.totalListenedMs,
    this.lastPlayedAt,
  });

  factory PlaylistStats.fromJson(Map<String, dynamic> json) {
    return PlaylistStats(
      playlistId: json['playlist_id'] ?? '',
      name: json['name'] ?? 'Unknown Playlist',
      startCount: json['start_count'] ?? 0,
      completionCount: json['completion_count'] ?? 0,
      totalListenedMs: json['total_listened_ms'] ?? 0,
      lastPlayedAt: json['last_played_at'] != null
          ? DateTime.tryParse(json['last_played_at'])
          : null,
    );
  }
}

class ListeningInsights {
  final int totalListenedMs;
  final int totalSongsPlayed;
  final int totalSongsCompleted;
  final int totalSkips;
  final int uniqueSongsListened;
  final int uniqueArtistsListened;
  final Map<int, int> listeningByHour;
  final Map<int, int> listeningByDayOfWeek;
  final Map<String, int> listeningByMonth;

  ListeningInsights({
    required this.totalListenedMs,
    required this.totalSongsPlayed,
    required this.totalSongsCompleted,
    required this.totalSkips,
    required this.uniqueSongsListened,
    required this.uniqueArtistsListened,
    required this.listeningByHour,
    required this.listeningByDayOfWeek,
    required this.listeningByMonth,
  });

  factory ListeningInsights.fromJson(Map<String, dynamic> json) {
    return ListeningInsights(
      totalListenedMs: json['total_listened_ms'] ?? 0,
      totalSongsPlayed: json['total_songs_played'] ?? 0,
      totalSongsCompleted: json['total_songs_completed'] ?? 0,
      totalSkips: json['total_skips'] ?? 0,
      uniqueSongsListened: json['unique_songs_listened'] ?? 0,
      uniqueArtistsListened: json['unique_artists_listened'] ?? 0,
      listeningByHour: _parseIntMap(json['listening_by_hour']),
      listeningByDayOfWeek: _parseIntMap(json['listening_by_day']),
      listeningByMonth: _parseStringIntMap(json['listening_by_month']),
    );
  }

  static Map<int, int> _parseIntMap(dynamic data) {
    if (data == null) return {};
    if (data is Map) {
      return data.map(
        (k, v) => MapEntry(
          int.tryParse(k.toString()) ?? 0,
          (v as num?)?.toInt() ?? 0,
        ),
      );
    }
    return {};
  }

  static Map<String, int> _parseStringIntMap(dynamic data) {
    if (data == null) return {};
    if (data is Map) {
      return data.map(
        (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
      );
    }
    return {};
  }

  /// Get total listening time in hours
  double get totalHours => totalListenedMs / 1000 / 60 / 60;

  /// Get total listening time in minutes
  int get totalMinutes => (totalListenedMs / 1000 / 60).round();
}

class ListeningStreak {
  final int currentStreak;
  final int longestStreak;
  final int totalDays;

  ListeningStreak({
    required this.currentStreak,
    required this.longestStreak,
    required this.totalDays,
  });

  factory ListeningStreak.fromJson(Map<String, dynamic> json) {
    return ListeningStreak(
      currentStreak: json['current_streak'] ?? 0,
      longestStreak: json['longest_streak'] ?? 0,
      totalDays: json['total_days'] ?? 0,
    );
  }
}

class RecentArtist {
  final String artistId;
  final String name;
  final String imagePath;
  final String? imageUrl; // Full URL with domain from DB
  final int playCount;
  final DateTime lastPlayedAt;

  RecentArtist({
    required this.artistId,
    required this.name,
    required this.imagePath,
    this.imageUrl,
    required this.playCount,
    required this.lastPlayedAt,
  });

  factory RecentArtist.fromJson(Map<String, dynamic> json) {
    return RecentArtist(
      artistId: json['artist_id'] ?? '',
      name: json['name'] ?? 'Unknown Artist',
      imagePath: json['image_path'] ?? '',
      imageUrl: json['image_url'] as String?,
      playCount: json['play_count'] ?? 0,
      lastPlayedAt:
          DateTime.tryParse(json['last_played_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class RecentAlbum {
  final String albumId;
  final String name;
  final String imagePath;
  final String? imageUrl; // Full URL with domain from DB
  final String artistName;
  final int playCount;
  final DateTime lastPlayedAt;
  final String? playlistId; // Album's playlist ID for navigation

  RecentAlbum({
    required this.albumId,
    required this.name,
    required this.imagePath,
    this.imageUrl,
    required this.artistName,
    required this.playCount,
    required this.lastPlayedAt,
    this.playlistId,
  });

  factory RecentAlbum.fromJson(Map<String, dynamic> json) {
    return RecentAlbum(
      albumId: json['album_id'] ?? '',
      name: json['name'] ?? 'Unknown Album',
      imagePath: json['image_path'] ?? '',
      imageUrl: json['image_url'] as String?,
      artistName: json['artist_name'] ?? 'Unknown Artist',
      playCount: json['play_count'] ?? 0,
      lastPlayedAt:
          DateTime.tryParse(json['last_played_at'] ?? '') ?? DateTime.now(),
      playlistId: json['playlist_id'] as String?,
    );
  }
}

class PaginatedArtists {
  final List<RecentArtist> artists;
  final int total;

  PaginatedArtists({required this.artists, required this.total});
}

class PaginatedAlbums {
  final List<RecentAlbum> albums;
  final int total;

  PaginatedAlbums({required this.albums, required this.total});
}
