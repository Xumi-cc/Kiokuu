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
    'source': source,
  };

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id'] ?? '',
    title: json['title'] ?? 'Unknown',
    artist: json['artist'] ?? 'Unknown Artist',
    album: json['album'],
    filePath: json['filePath'] ?? '',
    streamUrl: json['streamUrl'] ?? json['stream_url'],
    coverUrl: json['coverUrl'] ?? json['cover_url'],
    duration: Duration(milliseconds: json['duration'] ?? 0),
    artworkPath: json['artworkPath'],
    genres: json['genres'] != null ? List<String>.from(json['genres']) : [],
    tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
    isOwned: json['isOwned'] ?? true,
    playCount: json['playCount'] ?? json['play_count'] ?? 0,
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
    source: source ?? this.source,
  );
}
