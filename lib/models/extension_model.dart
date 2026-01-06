/// Extension system models for Music Cloud
/// Extensions are user-imported configurations that can fetch and parse music data

/// Represents the type of extension
enum ExtensionType {
  /// Parses metadata from supported sources
  scraper,

  /// Handles downloading from specific sources
  downloader,

  /// Both parsing and downloading
  full,
}

/// Represents the capabilities an extension can request
enum ExtensionCapability {
  /// Make HTTP requests
  http,

  /// Parse HTML content
  htmlParsing,

  /// Access download queue
  downloadQueue,

  /// Access local storage (for caching)
  localStorage,

  /// Show notifications
  notifications,
}

/// Metadata about an extension
class ExtensionMetadata {
  final String id;
  final String name;
  final String description;
  final String version;
  final String author;
  final String? homepage;
  final String? iconUrl;
  final ExtensionType type;
  final List<ExtensionCapability> capabilities;
  final List<String> supportedDomains;
  final DateTime installedAt;
  final DateTime? updatedAt;
  final bool isEnabled;
  final String? updateUrl;

  const ExtensionMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    this.homepage,
    this.iconUrl,
    required this.type,
    required this.capabilities,
    required this.supportedDomains,
    required this.installedAt,
    this.updatedAt,
    this.isEnabled = true,
    this.updateUrl,
  });

  factory ExtensionMetadata.fromJson(Map<String, dynamic> json) {
    return ExtensionMetadata(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Unknown',
      homepage: json['homepage'] as String?,
      iconUrl: json['icon'] as String?,
      type: ExtensionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ExtensionType.full,
      ),
      capabilities:
          (json['capabilities'] as List<dynamic>?)
              ?.map(
                (c) => ExtensionCapability.values.firstWhere(
                  (cap) => cap.name == c,
                  orElse: () => ExtensionCapability.http,
                ),
              )
              .toList() ??
          [ExtensionCapability.http],
      supportedDomains:
          (json['domains'] as List<dynamic>?)?.cast<String>() ?? [],
      installedAt: json['installedAt'] != null
          ? DateTime.parse(json['installedAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      isEnabled: json['enabled'] as bool? ?? true,
      updateUrl: json['updateUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'author': author,
    'homepage': homepage,
    'icon': iconUrl,
    'type': type.name,
    'capabilities': capabilities.map((c) => c.name).toList(),
    'domains': supportedDomains,
    'installedAt': installedAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'enabled': isEnabled,
    'updateUrl': updateUrl,
  };

  ExtensionMetadata copyWith({
    String? id,
    String? name,
    String? description,
    String? version,
    String? author,
    String? homepage,
    String? iconUrl,
    ExtensionType? type,
    List<ExtensionCapability>? capabilities,
    List<String>? supportedDomains,
    DateTime? installedAt,
    DateTime? updatedAt,
    bool? isEnabled,
    String? updateUrl,
  }) {
    return ExtensionMetadata(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      author: author ?? this.author,
      homepage: homepage ?? this.homepage,
      iconUrl: iconUrl ?? this.iconUrl,
      type: type ?? this.type,
      capabilities: capabilities ?? this.capabilities,
      supportedDomains: supportedDomains ?? this.supportedDomains,
      installedAt: installedAt ?? this.installedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isEnabled: isEnabled ?? this.isEnabled,
      updateUrl: updateUrl ?? this.updateUrl,
    );
  }
}

/// Represents a scraped track from an extension
class ScrapedTrack {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final int? durationMs;
  final String? streamUrl;
  final String? downloadUrl;
  final Map<String, dynamic>? extra;

  const ScrapedTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.coverUrl,
    this.durationMs,
    this.streamUrl,
    this.downloadUrl,
    this.extra,
  });

  factory ScrapedTrack.fromJson(Map<String, dynamic> json) {
    return ScrapedTrack(
      id: json['id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String?,
      coverUrl: json['cover'] as String?,
      durationMs: json['duration'] as int?,
      streamUrl: json['streamUrl'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
      extra: json['extra'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'cover': coverUrl,
    'duration': durationMs,
    'streamUrl': streamUrl,
    'downloadUrl': downloadUrl,
    'extra': extra,
  };
}

/// Represents a search result from an extension
class ExtensionSearchResult {
  final List<ScrapedTrack> tracks;
  final int totalResults;
  final int page;
  final bool hasMore;

  const ExtensionSearchResult({
    required this.tracks,
    this.totalResults = 0,
    this.page = 1,
    this.hasMore = false,
  });

  factory ExtensionSearchResult.fromJson(Map<String, dynamic> json) {
    return ExtensionSearchResult(
      tracks:
          (json['tracks'] as List<dynamic>?)
              ?.map((t) => ScrapedTrack.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      totalResults: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}

/// Result of extension execution
class ExtensionResult<T> {
  final bool success;
  final T? data;
  final String? error;
  final Duration? executionTime;

  const ExtensionResult({
    required this.success,
    this.data,
    this.error,
    this.executionTime,
  });

  factory ExtensionResult.success(T data, {Duration? executionTime}) {
    return ExtensionResult(
      success: true,
      data: data,
      executionTime: executionTime,
    );
  }

  factory ExtensionResult.failure(String error) {
    return ExtensionResult(success: false, error: error);
  }
}
