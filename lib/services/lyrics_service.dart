import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for fetching lyrics from multiple providers (like Echo-Music approach)
/// Providers: 1. LrcLib  2. KuGou (fallback for better coverage)
class LyricsService {
  static const String _lrcLibBaseUrl = 'https://lrclib.net/api';
  static const String _kuGouSearchUrl = 'https://krcs.kugou.com/search';
  static const String _kuGouDownloadUrl = 'https://krcs.kugou.com/download';

  // Cache to avoid repeated API calls
  static final Map<String, LyricsResult?> _cache = {};

  /// Fetches lyrics for a song from multiple providers
  /// Returns a LyricsResult containing plain and synced lyrics
  static Future<LyricsResult?> getLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    // Check cache first
    final cacheKey = '${artistName.toLowerCase()}-${trackName.toLowerCase()}';
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      print('📝 Lyrics from cache (${cached?.providerName ?? "null"})');
      return cached;
    }

    print('🔍 Fetching lyrics for: $artistName - $trackName');

    // Try LrcLib first (best for Western music)
    LyricsResult? result = await _getLyricsFromLrcLib(
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      durationSeconds: durationSeconds,
    );

    if (result != null) {
      print('✓ LrcLib: found (synced: ${result.hasSyncedLyrics})');
    } else {
      print('✗ LrcLib: not found');
    }

    // If LrcLib failed or has no synced lyrics, try KuGou
    if (result == null || !result.hasSyncedLyrics) {
      print('🔍 Trying KuGou fallback...');
      final kuGouResult = await _getLyricsFromKuGou(
        trackName: trackName,
        artistName: artistName,
        durationSeconds: durationSeconds ?? 0,
      );

      if (kuGouResult != null) {
        print('✓ KuGou: found (synced: ${kuGouResult.hasSyncedLyrics})');
      } else {
        print('✗ KuGou: not found');
      }

      // Use KuGou result if it has synced lyrics
      if (kuGouResult != null && kuGouResult.hasSyncedLyrics) {
        result = kuGouResult;
      } else if (result == null) {
        // Use KuGou even without synced if LrcLib returned nothing
        result = kuGouResult;
      }
    }

    // Cache the result
    _cache[cacheKey] = result;

    print('📝 Final lyrics provider: ${result?.providerName ?? "none"}');

    return result;
  }

  /// Fetches lyrics from LrcLib API
  static Future<LyricsResult?> _getLyricsFromLrcLib({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    try {
      final queryParams = {
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
        if (durationSeconds != null) 'duration': durationSeconds.toString(),
      };

      final uri = Uri.parse(
        '$_lrcLibBaseUrl/get',
      ).replace(queryParameters: queryParams);

      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'MusicCloud/1.0.0 (https://github.com/music-cloud)',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return LyricsResult.fromJson(data, providerName: 'LrcLib');
      }
      return null;
    } catch (e) {
      print('LrcLib error: $e');
      return null;
    }
  }

  /// Fetches lyrics from KuGou API (excellent for Asian music and synced lyrics)
  static Future<LyricsResult?> _getLyricsFromKuGou({
    required String trackName,
    required String artistName,
    required int durationSeconds,
  }) async {
    try {
      // KuGou uses duration in milliseconds
      final durationMs = durationSeconds * 1000;

      // First, search for the song
      final searchUri = Uri.parse(_kuGouSearchUrl).replace(
        queryParameters: {
          'ver': '1',
          'man': 'yes',
          'client': 'mobi',
          'keyword': '$artistName - $trackName',
          'duration': durationMs.toString(),
          'hash': '',
        },
      );

      final searchResponse = await http
          .get(searchUri)
          .timeout(const Duration(seconds: 10));

      if (searchResponse.statusCode != 200) return null;

      final searchData = json.decode(searchResponse.body);
      final candidates = searchData['candidates'] as List?;

      if (candidates == null || candidates.isEmpty) return null;

      // Get the first candidate
      final candidate = candidates.first;
      final id = candidate['id']?.toString() ?? '';
      final accessKey = candidate['accesskey']?.toString() ?? '';

      if (id.isEmpty || accessKey.isEmpty) return null;

      // Download the lyrics
      final downloadUri = Uri.parse(_kuGouDownloadUrl).replace(
        queryParameters: {
          'ver': '1',
          'client': 'pc',
          'id': id,
          'accesskey': accessKey,
          'fmt': 'lrc',
          'charset': 'utf8',
        },
      );

      final downloadResponse = await http
          .get(downloadUri)
          .timeout(const Duration(seconds: 10));

      if (downloadResponse.statusCode != 200) return null;

      final downloadData = json.decode(downloadResponse.body);

      if (downloadData['status'] != 200) return null;

      // Decode base64 lyrics content
      final contentBase64 = downloadData['content']?.toString();
      if (contentBase64 == null || contentBase64.isEmpty) return null;

      final decodedBytes = base64Decode(contentBase64);
      final lyricsContent = utf8.decode(decodedBytes);

      // Parse the LRC content
      return LyricsResult(
        id: int.tryParse(id) ?? 0,
        trackName: trackName,
        artistName: artistName,
        syncedLyrics: lyricsContent,
        providerName: 'KuGou',
      );
    } catch (e) {
      print('KuGou error: $e');
      return null;
    }
  }

  /// Searches for lyrics matching the query
  static Future<List<LyricsResult>> searchLyrics({
    required String trackName,
    String? artistName,
    String? albumName,
  }) async {
    try {
      final queryParams = {
        'track_name': trackName,
        if (artistName != null && artistName.isNotEmpty)
          'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
      };

      final uri = Uri.parse(
        '$_lrcLibBaseUrl/search',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'MusicCloud/1.0.0 (https://github.com/music-cloud)',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((item) => LyricsResult.fromJson(item)).toList();
      } else {
        print('LRCLIB search error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error searching lyrics: $e');
      return [];
    }
  }

  /// Clears the lyrics cache
  static void clearCache() {
    _cache.clear();
  }

  /// Gets the count of cached lyrics entries
  static int getCacheCount() {
    return _cache.length;
  }
}

/// Represents a lyrics result from multiple providers
class LyricsResult {
  final int id;
  final String trackName;
  final String artistName;
  final String? albumName;
  final double? duration;
  final bool instrumental;
  final String? plainLyrics;
  final String? syncedLyrics;
  final String providerName; // Which provider returned this result

  LyricsResult({
    required this.id,
    required this.trackName,
    required this.artistName,
    this.albumName,
    this.duration,
    this.instrumental = false,
    this.plainLyrics,
    this.syncedLyrics,
    this.providerName = 'Unknown',
  });

  factory LyricsResult.fromJson(
    Map<String, dynamic> json, {
    String providerName = 'LrcLib',
  }) {
    return LyricsResult(
      id: json['id'] ?? 0,
      trackName: json['trackName'] ?? '',
      artistName: json['artistName'] ?? '',
      albumName: json['albumName'],
      duration: json['duration']?.toDouble(),
      instrumental: json['instrumental'] ?? false,
      plainLyrics: json['plainLyrics'],
      syncedLyrics: json['syncedLyrics'],
      providerName: providerName,
    );
  }

  /// Parses synced lyrics into a list of LyricLine objects
  List<LyricLine> get parsedSyncedLyrics {
    if (syncedLyrics == null || syncedLyrics!.isEmpty) return [];

    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)');

    for (final line in syncedLyrics!.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisecondsStr = match.group(3)!;
        // Handle both 2-digit (centiseconds) and 3-digit (milliseconds) formats
        final milliseconds = millisecondsStr.length == 2
            ? int.parse(millisecondsStr) * 10
            : int.parse(millisecondsStr);

        final timestamp = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        final text = match.group(4)?.trim() ?? '';
        if (text.isNotEmpty) {
          lines.add(LyricLine(timestamp: timestamp, text: text));
        }
      }
    }

    return lines;
  }

  /// Returns plain lyrics split into lines
  List<String> get plainLyricsLines {
    if (plainLyrics == null || plainLyrics!.isEmpty) return [];
    return plainLyrics!
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
  }

  bool get hasSyncedLyrics => syncedLyrics != null && syncedLyrics!.isNotEmpty;
  bool get hasPlainLyrics => plainLyrics != null && plainLyrics!.isNotEmpty;
  bool get hasAnyLyrics => hasSyncedLyrics || hasPlainLyrics;
}

/// Represents a single line of synced lyrics with timestamp
class LyricLine {
  final Duration timestamp;
  final String text;

  LyricLine({required this.timestamp, required this.text});

  /// Parses words from this line with interpolated timestamps
  /// [nextLineTimestamp] is needed to calculate end time for this line
  List<LyricWord> parseWords(Duration? nextLineTimestamp) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return [];

    // Calculate duration for this line
    final lineEndTime =
        nextLineTimestamp ?? (timestamp + const Duration(seconds: 5));
    final lineDuration = lineEndTime - timestamp;

    // Distribute time across words (evenly for simplicity)
    final wordDuration = lineDuration ~/ words.length;

    final parsedWords = <LyricWord>[];
    for (int i = 0; i < words.length; i++) {
      final wordStart = timestamp + (wordDuration * i);
      final wordEnd = timestamp + (wordDuration * (i + 1));
      parsedWords.add(
        LyricWord(
          text: words[i],
          startTime: wordStart,
          endTime: wordEnd,
          index: i,
        ),
      );
    }

    return parsedWords;
  }

  @override
  String toString() =>
      '[${timestamp.inMinutes}:${(timestamp.inSeconds % 60).toString().padLeft(2, '0')}] $text';
}

/// Represents a single word within a lyric line with timing
class LyricWord {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final int index;

  LyricWord({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.index,
  });

  /// Returns progress (0.0 to 1.0) of the word based on current position
  double getProgress(Duration currentPosition) {
    if (currentPosition < startTime) return 0.0;
    if (currentPosition >= endTime) return 1.0;

    final wordDuration = endTime - startTime;
    final elapsed = currentPosition - startTime;
    return elapsed.inMilliseconds / wordDuration.inMilliseconds;
  }

  /// Checks if this word should be highlighted at the given position
  bool isActive(Duration currentPosition) {
    return currentPosition >= startTime && currentPosition < endTime;
  }

  /// Checks if this word has been sung (past its end time)
  bool isPast(Duration currentPosition) {
    return currentPosition >= endTime;
  }
}
