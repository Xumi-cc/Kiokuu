import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'llm_match_service.dart';
import 'import_processor_service.dart';

/// Service to persist import task state across app restarts.
/// Stores tasks awaiting review so users don't lose their progress.
class ImportTaskPersistence {
  static ImportTaskPersistence? _instance;
  static ImportTaskPersistence get instance =>
      _instance ??= ImportTaskPersistence._();

  ImportTaskPersistence._();

  String? _persistencePath;

  /// Initialize the persistence storage
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _persistencePath = '${appDir.path}/import_tasks.json';
      debugPrint('📦 Import task persistence initialized: $_persistencePath');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize import task persistence: $e');
    }
  }

  /// Save a task awaiting review to persistent storage
  Future<void> saveTaskAwaitingReview(ImportTask task) async {
    if (_persistencePath == null) return;

    try {
      final tasks = await loadPersistedTasks();

      // Check if task already exists (by file path)
      final existingIndex = tasks.indexWhere(
        (t) => t['filePath'] == task.file.path,
      );

      final taskData = {
        'filePath': task.file.path,
        'fileName': task.fileName,
        'title': task.title,
        'artist': task.artist,
        'album': task.album,
        'spotifyId': task.spotifyId,
        'aiMatch': task.aiMatchResult != null
            ? {
                'title': task.aiMatchResult!.title,
                'artist': task.aiMatchResult!.artist,
                'album': task.aiMatchResult!.album,
                'albumArt': task.aiMatchResult!.albumArt,
                'spotifyId': task.aiMatchResult!.spotifyId,
                'reasoning': task.aiMatchResult!.reasoning,
                'confidence': task.aiMatchResult!.confidence,
              }
            : null,
        'savedAt': DateTime.now().toIso8601String(),
      };

      if (existingIndex >= 0) {
        tasks[existingIndex] = taskData;
      } else {
        tasks.add(taskData);
      }

      await _saveToFile(tasks);
      debugPrint('💾 Saved task awaiting review: ${task.fileName}');
    } catch (e) {
      debugPrint('⚠️ Failed to save task: $e');
    }
  }

  /// Remove a task from persistent storage (after accept/reject)
  Future<void> removeTask(String filePath) async {
    if (_persistencePath == null) return;

    try {
      final tasks = await loadPersistedTasks();
      tasks.removeWhere((t) => t['filePath'] == filePath);
      await _saveToFile(tasks);
      debugPrint('🗑️ Removed persisted task: $filePath');
    } catch (e) {
      debugPrint('⚠️ Failed to remove task: $e');
    }
  }

  /// Load all persisted tasks
  Future<List<Map<String, dynamic>>> loadPersistedTasks() async {
    if (_persistencePath == null) return [];

    try {
      final file = File(_persistencePath!);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      final List<dynamic> decoded = json.decode(content);
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('⚠️ Failed to load persisted tasks: $e');
      return [];
    }
  }

  /// Restore persisted tasks to ImportTask objects
  Future<List<ImportTask>> restorePersistedTasks() async {
    final persistedData = await loadPersistedTasks();
    final restoredTasks = <ImportTask>[];

    for (final data in persistedData) {
      try {
        final filePath = data['filePath'] as String?;
        if (filePath == null) continue;

        final file = File(filePath);
        if (!await file.exists()) {
          // File no longer exists, remove from persistence
          await removeTask(filePath);
          continue;
        }

        LlmMatchResult? aiMatch;
        if (data['aiMatch'] != null) {
          final matchData = data['aiMatch'] as Map<String, dynamic>;
          aiMatch = LlmMatchResult(
            title: matchData['title'] ?? '',
            artist: matchData['artist'] ?? '',
            album: matchData['album'] ?? '',
            albumArt: matchData['albumArt'] ?? '',
            spotifyId: matchData['spotifyId'] ?? '',
            reasoning: matchData['reasoning'] ?? '',
            confidence: (matchData['confidence'] as num?)?.toDouble() ?? 0.5,
          );
        }

        restoredTasks.add(
          ImportTask(
            file: file,
            fileName: data['fileName'] ?? file.uri.pathSegments.last,
            status: ImportStatus.awaitingReview,
            title: data['title'] as String?,
            artist: data['artist'] as String?,
            album: data['album'] as String?,
            spotifyId: data['spotifyId'] as String?,
            aiMatchResult: aiMatch,
          ),
        );

        debugPrint('♻️ Restored task: ${data['fileName']}');
      } catch (e) {
        debugPrint('⚠️ Failed to restore task: $e');
      }
    }

    return restoredTasks;
  }

  /// Check if a file has a persisted task (already processed)
  Future<bool> hasPersistedTask(String filePath) async {
    final tasks = await loadPersistedTasks();
    return tasks.any((t) => t['filePath'] == filePath);
  }

  /// Save tasks list to file
  Future<void> _saveToFile(List<Map<String, dynamic>> tasks) async {
    if (_persistencePath == null) return;

    final file = File(_persistencePath!);
    await file.writeAsString(json.encode(tasks));
  }

  /// Clear all persisted tasks
  Future<void> clearAll() async {
    if (_persistencePath == null) return;

    try {
      final file = File(_persistencePath!);
      if (await file.exists()) {
        await file.delete();
      }
      debugPrint('🧹 Cleared all persisted tasks');
    } catch (e) {
      debugPrint('⚠️ Failed to clear persisted tasks: $e');
    }
  }
}
