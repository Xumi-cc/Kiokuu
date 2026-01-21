import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for audio fingerprint-based song identification
///
/// Sends audio samples to the backend for AcoustID fingerprint matching.
/// This provides the most accurate song identification for known tracks.
///
/// Workflow:
/// 1. Auto-import: Send partial audio → Get Spotify ID
/// 2. Upload: Backend verifies/corrects Spotify ID automatically
class FingerprintService {
  static FingerprintService? _instance;
  static FingerprintService get instance =>
      _instance ??= FingerprintService._();

  FingerprintService._();

  final _storage = const FlutterSecureStorage();

  Future<String?> get _token async => await _storage.read(key: 'auth_token');

  /// Check if fingerprint service is available on the backend
  Future<bool> isAvailable() async {
    try {
      final token = await _token;
      if (token == null) return false;

      final response = await http
          .get(
            Uri.parse('${AppConfig.apiBaseUrl}/fingerprint/status'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['enabled'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('🔇 Fingerprint status check failed: $e');
      return false;
    }
  }

  /// Identify a song from an audio file
  ///
  /// Sends the audio file (or a sample) to the backend for identification
  /// Returns the track info including Spotify ID if found
  Future<FingerprintResult?> identifyAudio(File audioFile) async {
    try {
      final token = await _token;
      if (token == null) {
        debugPrint('❌ No auth token for fingerprint identification');
        return null;
      }

      debugPrint(
        '🔍 Sending audio for fingerprint identification: ${audioFile.path}',
      );

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.apiBaseUrl}/fingerprint/identify'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath('audio', audioFile.path),
      );

      // Send with timeout (fingerprinting can take a few seconds)
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        debugPrint(
          '❌ Fingerprint identification failed: ${response.statusCode}',
        );
        return null;
      }

      final data = jsonDecode(response.body);

      if (data['found'] != true) {
        debugPrint('❌ No fingerprint match found');
        return FingerprintResult(found: false);
      }

      final result = FingerprintResult(
        found: true,
        spotifyId: data['spotify_id'] as String?,
        title: data['title'] as String?,
        artist: data['artist'] as String?,
        album: data['album'] as String?,
        recordingId: data['recording_id'] as String?,
        confidence: (data['confidence'] as num?)?.toDouble() ?? 0.0,
      );

      debugPrint('✅ Fingerprint match: ${result.title} - ${result.artist}');
      if (result.spotifyId != null) {
        debugPrint('   Spotify ID: ${result.spotifyId}');
      }
      debugPrint(
        '   Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
      );

      return result;
    } catch (e) {
      debugPrint('❌ Fingerprint identification error: $e');
      return null;
    }
  }

  /// Identify multiple audio files
  /// Returns a map of file path to result
  Future<Map<String, FingerprintResult?>> identifyMultiple(
    List<File> audioFiles,
  ) async {
    final results = <String, FingerprintResult?>{};

    for (final file in audioFiles) {
      results[file.path] = await identifyAudio(file);
      // Small delay between requests to be nice to the server
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return results;
  }
}

/// Result of fingerprint identification
class FingerprintResult {
  final bool found;
  final String? spotifyId;
  final String? title;
  final String? artist;
  final String? album;
  final String? recordingId;
  final double confidence;

  FingerprintResult({
    required this.found,
    this.spotifyId,
    this.title,
    this.artist,
    this.album,
    this.recordingId,
    this.confidence = 0.0,
  });

  /// Has a usable Spotify ID
  bool get hasSpotifyId => spotifyId != null && spotifyId!.isNotEmpty;

  /// High confidence match (> 80%)
  bool get isHighConfidence => confidence >= 0.80;

  @override
  String toString() {
    if (!found) return 'FingerprintResult(not found)';
    return 'FingerprintResult(title: $title, artist: $artist, spotifyId: $spotifyId, confidence: ${(confidence * 100).toStringAsFixed(0)}%)';
  }
}
