import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Threshold above which AI is confident enough to auto-upload
const double kHighConfidenceThreshold = 0.8;

/// Service for AI-powered song matching via backend API
/// Requires Premium+ subscription for access
class LlmMatchService {
  static final LlmMatchService instance = LlmMatchService._();
  LlmMatchService._();

  final _api = ApiService();

  /// Check if AI match is available (always returns true - backend checks subscription)
  bool get isReady => true;

  /// Initialize the service (no-op for backend-based service)
  Future<bool> initialize() async {
    return true;
  }

  /// Check if user has API key configured (not needed for backend approach)
  Future<bool> hasApiKey() async => true;

  /// Set API key (not needed - backend handles this)
  Future<void> setApiKey(String apiKey) async {}

  /// Get masked API key (not applicable)
  Future<String?> getApiKeyMasked() async => null;

  /// Clear API key (not applicable)
  Future<void> clearApiKey() async {}

  /// Find the best Spotify match using backend AI service
  /// Requires Premium+ subscription
  Future<LlmMatchResult?> findBestMatch({
    required String title,
    String? artist,
    String? album,
    int? durationMs,
  }) async {
    try {
      debugPrint('🤖 Sending AI match request to backend: $title - $artist');

      final result = await _api.aiMatch(
        title: title,
        artist: artist,
        album: album,
      );

      if (result == null) {
        debugPrint('⚠️ AI match returned null');
        return null;
      }

      // Check for error responses
      if (result.containsKey('error')) {
        debugPrint('⚠️ AI match error: ${result['error']}');
        return null;
      }

      // Validate we have required fields
      if (result['spotify_id'] == null ||
          (result['spotify_id'] as String).isEmpty) {
        debugPrint('⚠️ AI match missing spotify_id');
        return null;
      }

      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.5;
      debugPrint(
        '✅ AI match result: ${result['title']} by ${result['artist']} (confidence: ${(confidence * 100).toStringAsFixed(0)}%)',
      );

      return LlmMatchResult(
        title: result['title'] ?? title,
        artist: result['artist'] ?? artist ?? '',
        album: result['album'] ?? '',
        albumArt: result['album_art'] ?? '',
        spotifyId: result['spotify_id'] ?? '',
        reasoning: result['reasoning'] ?? '',
        confidence: confidence,
      );
    } catch (e) {
      debugPrint('⚠️ AI match failed: $e');
      return null;
    }
  }

  /// Dispose resources
  void dispose() {}
}

/// Result from AI-powered matching
class LlmMatchResult {
  final String title;
  final String artist;
  final String album;
  final String albumArt;
  final String spotifyId;
  final String reasoning;
  final double confidence; // 0.0-1.0 indicating match confidence

  /// Returns true if confidence is high enough to auto-upload
  bool get isHighConfidence => confidence >= kHighConfidenceThreshold;

  LlmMatchResult({
    required this.title,
    required this.artist,
    required this.spotifyId,
    this.album = '',
    this.albumArt = '',
    this.reasoning = '',
    this.confidence = 0.5,
  });

  @override
  String toString() =>
      'LlmMatchResult(title: $title, artist: $artist, spotifyId: $spotifyId, confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
}
