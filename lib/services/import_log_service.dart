import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Types of log entries
enum LogType {
  info,
  success,
  warning,
  error,
  aiThinking,  // Special type for AI "thinking" logs
}

/// A single log entry
class LogEntry {
  final DateTime timestamp;
  final LogType type;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.type,
    required this.message,
    this.details,
  });

  /// Get the icon for this log type
  IconData get iconData {
    switch (type) {
      case LogType.info: return Icons.info_outline;
      case LogType.success: return Icons.check_circle_outline;
      case LogType.warning: return Icons.warning_amber_outlined;
      case LogType.error: return Icons.error_outline;
      case LogType.aiThinking: return Icons.psychology;
    }
  }

  /// Get the color for this log type
  Color get color {
    switch (type) {
      case LogType.info: return Colors.blue;
      case LogType.success: return Colors.green;
      case LogType.warning: return Colors.orange;
      case LogType.error: return Colors.red;
      case LogType.aiThinking: return Colors.purple;
    }
  }

  /// Get prefix for debug console
  String get _debugPrefix {
    switch (type) {
      case LogType.info: return 'ℹ';
      case LogType.success: return '✓';
      case LogType.warning: return '⚠';
      case LogType.error: return '✗';
      case LogType.aiThinking: return '◉';
    }
  }

  String get timeFormatted {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}';
  }
}

/// Service for capturing and displaying AI processing logs
class ImportLogService {
  static final ImportLogService instance = ImportLogService._();
  ImportLogService._();

  final List<LogEntry> _logs = [];
  final _controller = StreamController<List<LogEntry>>.broadcast();

  /// Stream of log updates
  Stream<List<LogEntry>> get logStream => _controller.stream;

  /// Get all logs
  List<LogEntry> get logs => List.unmodifiable(_logs);

  /// Clear all logs
  void clear() {
    _logs.clear();
    _notify();
  }

  void _notify() {
    _controller.add(_logs);
  }

  /// Add a log entry
  void _log(LogType type, String message, {String? details}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      type: type,
      message: message,
      details: details,
    );
    _logs.add(entry);
    
    // Keep only last 100 logs
    if (_logs.length > 100) {
      _logs.removeAt(0);
    }
    
    _notify();
    
    // Also print to debug console
    debugPrint('${entry._debugPrefix} [${entry.timeFormatted}] $message');
  }

  // Convenience methods
  void info(String message, {String? details}) => 
      _log(LogType.info, message, details: details);
  
  void success(String message, {String? details}) => 
      _log(LogType.success, message, details: details);
  
  void warning(String message, {String? details}) => 
      _log(LogType.warning, message, details: details);
  
  void error(String message, {String? details}) => 
      _log(LogType.error, message, details: details);

  /// Log AI thinking process
  void aiThinking(String thought, {String? details}) => 
      _log(LogType.aiThinking, thought, details: details);

  // --- Specific import logging methods ---

  void fileDetected(String filename) {
    info('New file detected: $filename');
  }

  void extractingMetadata(String filename) {
    aiThinking('Analyzing audio file...',
      details: 'Reading embedded ID3/Vorbis tags from $filename');
  }

  void metadataExtracted(String? title, String? artist) {
    if (title != null || artist != null) {
      success('Found metadata: "${title ?? 'Unknown'}" by "${artist ?? 'Unknown'}"');
    } else {
      warning('No embedded metadata found');
    }
  }

  void tryingSmartMatch(String filename) {
    aiThinking('Analyzing filename for clues...',
      details: 'Looking for artist/title patterns in: $filename');
  }

  void filenameCleaned(String original, String cleaned) {
    info('Cleaned filename: "$cleaned"',
      details: 'Removed junk from: $original');
  }

  void searchingSpotify(String query) {
    aiThinking('Searching Spotify catalog...',
      details: 'Query: "$query"');
  }

  void spotifyMatch(String title, String artist, String spotifyId) {
    success('Spotify match found: "$title" by "$artist"',
      details: 'ID: $spotifyId');
  }

  void spotifyNoMatch(String query) {
    warning('No Spotify match for: "$query"');
  }

  void uploadStarted(String filename) {
    info('Starting upload: $filename');
  }

  void uploadProgress(String filename, int percent) {
    // Don't log every progress update, just milestones
    if (percent == 25 || percent == 50 || percent == 75) {
      info('Upload progress: $percent%');
    }
  }

  void uploadComplete(String filename) {
    success('Upload complete: $filename');
  }

  void uploadFailed(String filename, String error) {
    this.error('Upload failed: $filename', details: error);
  }

  void importComplete(String filename) {
    success('Import complete: $filename');
  }

  void importFailed(String filename, String reason) {
    error('Import failed: $filename', details: reason);
  }
}
