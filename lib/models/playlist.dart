/// Playlist model for the KioKuu app
class Playlist {
  final String id;
  final String name;
  final String description;
  final bool isPublic;
  final bool isSystem; // System playlists like "Liked Songs"
  final int songCount;
  final List<String> coverImages; // Up to 4 cover images for mosaic
  final List<String> coverImageUrls; // Full URLs with domain from DB
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<PlaylistSong>? songs; // Full songs when fetching single playlist
  // Album playlist fields
  final String? albumId; // If set, this is an album playlist
  final String? artistName; // Primary artist for album playlists
  final String? releaseDate; // Album release date

  /// Returns true if this playlist is an album
  bool get isAlbum => albumId != null && albumId!.isNotEmpty;

  Playlist({
    required this.id,
    required this.name,
    this.description = '',
    this.isPublic = false,
    this.isSystem = false,
    this.songCount = 0,
    this.coverImages = const [],
    this.coverImageUrls = const [],
    required this.createdAt,
    this.updatedAt,
    this.songs,
    this.albumId,
    this.artistName,
    this.releaseDate,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    List<String> covers = [];
    if (json['cover_images'] != null) {
      covers = (json['cover_images'] as List).map((e) => e.toString()).toList();
    }

    List<String> coverUrls = [];
    if (json['cover_image_urls'] != null) {
      coverUrls = (json['cover_image_urls'] as List)
          .map((e) => e.toString())
          .toList();
    }

    List<PlaylistSong>? songs;
    if (json['songs'] != null) {
      songs = (json['songs'] as List)
          .map((s) => PlaylistSong.fromJson(s))
          .toList();
    }

    return Playlist(
      id: json['id'],
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      isPublic: json['is_public'] ?? false,
      isSystem: json['is_system'] ?? false,
      songCount: json['song_count'] ?? (songs?.length ?? 0),
      coverImages: covers,
      coverImageUrls: coverUrls,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
      songs: songs,
      albumId: json['album_id'],
      artistName: json['artist_name'],
      releaseDate: json['release_date'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'is_public': isPublic,
    'song_count': songCount,
    'cover_images': coverImages,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}

/// Song inside a playlist (view model from backend)
class PlaylistSong {
  final String id;
  final String title;
  final String artistName;
  final String albumName;
  final int durationMs;
  final String? coverPath;
  final String? filePath;
  final String? streamUrl; // Full URL with server domain from DB
  final String? coverUrl; // Full URL for cover image from DB
  final List<String> genres;
  final List<String> tags;
  final bool isOfflineAvailable; // For offline mode - false means greyed out
  final String
  source; // Audio source: "user", "tidal", etc. (for HD upgrade detection)

  PlaylistSong({
    required this.id,
    required this.title,
    required this.artistName,
    this.albumName = '',
    required this.durationMs,
    this.coverPath,
    this.filePath,
    this.streamUrl,
    this.coverUrl,
    this.genres = const [],
    this.tags = const [],
    this.isOfflineAvailable = true,
    this.source = 'user',
  });

  factory PlaylistSong.fromJson(Map<String, dynamic> json) {
    return PlaylistSong(
      id: json['id'],
      title: json['title'] ?? '',
      artistName: json['artist_name'] ?? 'Unknown Artist',
      albumName: json['album_name'] ?? '',
      durationMs: json['duration_ms'] ?? 0,
      coverPath: json['cover_path'],
      filePath: json['file_path'] ?? '',
      streamUrl: json['stream_url'],
      coverUrl: json['cover_url'],
      genres: json['genres'] != null ? List<String>.from(json['genres']) : [],
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      source: json['source'] ?? 'user',
    );
  }

  Duration get duration => Duration(milliseconds: durationMs);
}
