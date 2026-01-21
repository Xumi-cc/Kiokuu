import '../services/api_service.dart';

class Song {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String filePath;
  final String? streamUrl; // Full URL with server domain from DB
  final String? coverUrl; // Full URL for cover image from DB
  final Duration duration;
  final String? artworkPath;
  final List<String> genres;
  final List<String> tags;
  final bool isOwned; // Whether the user has access to this song
  final int playCount; // Total streams/play count
  final String? uploadedBy; // User ID of who uploaded the song
  final String
  source; // Audio source: "user", "tidal", etc. (for HD upgrade detection)

  Song({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    required this.filePath,
    this.streamUrl,
    this.coverUrl,
    required this.duration,
    this.artworkPath,
    this.genres = const [],
    this.tags = const [],
    this.isOwned = true, // Default to true for backward compatibility
    this.playCount = 0,
    this.uploadedBy,
    this.source = 'user', // Default to 'user' for backward compatibility
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'filePath': filePath,
    'streamUrl': streamUrl,
    'coverUrl': coverUrl,
    'duration': duration.inMilliseconds,
    'artworkPath': artworkPath,
    'genres': genres,
    'tags': tags,
    'isOwned': isOwned,
    'playCount': playCount,
    'uploaded_by': uploadedBy,
    'source': source,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'] ?? '',
    title: json['title'] ?? 'Unknown',
    artist: json['artist'] ?? json['artist_name'] ?? 'Unknown Artist',
    album: json['album'] ?? json['album_name'],
    filePath: json['filePath'] ?? json['file_path'] ?? '',
    streamUrl: json['streamUrl'] ?? json['stream_url'],
    coverUrl: json['coverUrl'] ?? json['cover_url'],
    duration: json['duration_ms'] != null
        ? Duration(milliseconds: json['duration_ms'])
        : (json['duration'] != null
              ? (json['duration'] >
                        10000 // Heuristic: if > 10000, it's likely ms
                    ? Duration(milliseconds: json['duration'])
                    : Duration(seconds: json['duration']))
              : Duration.zero),
    artworkPath:
        json['artworkPath'] ?? json['cover_path'] ?? json['image_path'],
    genres: json['genres'] != null ? List<String>.from(json['genres']) : [],
    tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
    isOwned: json['isOwned'] ?? true,
    playCount: json['playCount'] ?? json['play_count'] ?? 0,
    uploadedBy: json['uploaded_by'] ?? json['uploadedBy'],
    source: json['source'] ?? 'user',
  );

  /// Create a copy with modified isOwned
  Song copyWith({
    bool? isOwned,
    int? playCount,
    String? streamUrl,
    String? coverUrl,
    String? source,
  }) => Song(
    id: id,
    title: title,
    artist: artist,
    album: album,
    filePath: filePath,
    streamUrl: streamUrl ?? this.streamUrl,
    coverUrl: coverUrl ?? this.coverUrl,
    duration: duration,
    artworkPath: artworkPath,
    genres: genres,
    tags: tags,
    isOwned: isOwned ?? this.isOwned,
    playCount: playCount ?? this.playCount,
    uploadedBy: uploadedBy ?? this.uploadedBy,
    source: source ?? this.source,
  );

  /// Helper to get the best available artwork URL/path
  String? get artwork {
    if (coverUrl != null && coverUrl!.isNotEmpty) return coverUrl;
    if (artworkPath == null || artworkPath!.isEmpty) return null;

    // If it's already a full URL, return it
    if (artworkPath!.startsWith('http')) return artworkPath;

    // If it's a local file path, return it as is
    if (artworkPath!.startsWith('/') || artworkPath!.contains(':\\')) {
      return artworkPath;
    }

    // Otherwise it's a relative path from the server
    final url = ApiService.getCdnUrl(null, artworkPath);
    // debugPrint('Resolved relative artwork: $artworkPath -> $url');
    return url;
  }
}
