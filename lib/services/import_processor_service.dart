import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'api_service.dart';
import 'import_folder_service.dart';
import 'extension_manager_service.dart';
import 'llm_match_service.dart';
import 'import_log_service.dart';
import 'import_task_persistence.dart';
import 'fingerprint_service.dart';

export 'llm_match_service.dart' show LlmMatchResult;

/// Status of a file being processed
enum ImportStatus {
  pending,
  waitingForAI, // Waiting for AI extension to be installed
  extractingMetadata,
  matchingWithAI,
  awaitingReview, // AI found a match, awaiting user confirmation
  uploading,
  completed,
  failed,
  skipped, // User rejected the match
}

/// Represents a file being imported
class ImportTask {
  final File file;
  final String fileName;
  ImportStatus status;
  String? errorMessage;

  // Extracted/matched metadata
  String? title;
  String? artist;
  String? album;
  String? spotifyId;

  // AI match result (for user review)
  LlmMatchResult? aiMatchResult;

  // Progress (0.0 to 1.0)
  double uploadProgress;

  ImportTask({
    required this.file,
    required this.fileName,
    this.status = ImportStatus.pending,
    this.errorMessage,
    this.title,
    this.artist,
    this.album,
    this.spotifyId,
    this.aiMatchResult,
    this.uploadProgress = 0.0,
  });
}

/// Callback types for import progress updates
typedef OnImportProgress = void Function(List<ImportTask> tasks);
typedef OnImportComplete = void Function(ImportTask task, bool success);
typedef OnReviewNeeded = void Function(ImportTask task);

/// Service that processes imported audio files.
/// Requires AI extension for automatic matching and upload.
class ImportProcessorService {
  static ImportProcessorService? _instance;
  static ImportProcessorService get instance =>
      _instance ??= ImportProcessorService._();

  ImportProcessorService._();

  final List<ImportTask> _tasks = [];
  bool _isProcessing = false;
  OnImportProgress? _onProgress;
  OnImportComplete? _onComplete;
  OnReviewNeeded? _onReviewNeeded;

  /// Get current import tasks
  List<ImportTask> get tasks => List.unmodifiable(_tasks);

  /// Get tasks waiting for AI
  List<ImportTask> get pendingTasks =>
      _tasks.where((t) => t.status == ImportStatus.waitingForAI).toList();

  /// Check if AI extension is available
  bool get isAIAvailable =>
      ExtensionManagerService.instance.isAudioFingerprintAvailable;

  /// Set up callbacks for import progress
  void setCallbacks({
    OnImportProgress? onProgress,
    OnImportComplete? onComplete,
    OnReviewNeeded? onReviewNeeded,
  }) {
    _onProgress = onProgress;
    _onComplete = onComplete;
    _onReviewNeeded = onReviewNeeded;
  }

  /// Queue files for import processing
  Future<void> queueFiles(List<File> files) async {
    // Check if AI extension is enabled
    if (!isAIAvailable) {
      debugPrint('🚫 Smart Match disabled - ignoring ${files.length} files');
      return;
    }

    final persistence = ImportTaskPersistence.instance;

    for (final file in files) {
      // Skip if already queued
      if (_tasks.any((t) => t.file.path == file.path)) {
        continue;
      }

      // Check if this file has a persisted task awaiting review
      if (await persistence.hasPersistedTask(file.path)) {
        debugPrint(
          '⏭️ Skipping ${file.uri.pathSegments.last} - already awaiting review',
        );
        continue;
      }

      final task = ImportTask(file: file, fileName: file.uri.pathSegments.last);

      _tasks.add(task);
    }

    _onProgress?.call(_tasks);

    // Start processing if not already
    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Restore persisted tasks awaiting review (call on app startup)
  Future<void> restorePersistedTasks() async {
    try {
      await ImportTaskPersistence.instance.initialize();
      final restoredTasks = await ImportTaskPersistence.instance
          .restorePersistedTasks();

      if (restoredTasks.isEmpty) return;

      debugPrint('♻️ Restoring ${restoredTasks.length} tasks awaiting review');

      for (final task in restoredTasks) {
        // Skip if already in the queue
        if (_tasks.any((t) => t.file.path == task.file.path)) {
          continue;
        }
        _tasks.add(task);
      }

      _onProgress?.call(_tasks);

      // Trigger review for each restored task
      for (final task in restoredTasks) {
        if (task.status == ImportStatus.awaitingReview) {
          _onReviewNeeded?.call(task);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to restore persisted tasks: $e');
    }
  }

  /// Called when AI extension is installed - starts processing waiting tasks
  void onAIExtensionInstalled() {
    debugPrint('🤖 AI extension installed - resuming import queue');

    // Move waiting tasks back to pending
    for (final task in _tasks) {
      if (task.status == ImportStatus.waitingForAI) {
        task.status = ImportStatus.pending;
      }
    }

    _onProgress?.call(_tasks);

    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Process the queue of import tasks
  Future<void> _processQueue() async {
    if (_isProcessing) return;
    if (!isAIAvailable) {
      debugPrint('⚠️ Cannot process - AI extension not installed');
      return;
    }

    _isProcessing = true;

    while (_tasks.any((t) => t.status == ImportStatus.pending)) {
      final task = _tasks.firstWhere((t) => t.status == ImportStatus.pending);
      await _processTask(task);
    }

    _isProcessing = false;
  }

  /// Process a single import task
  Future<void> _processTask(ImportTask task) async {
    final log = ImportLogService.instance;

    try {
      log.fileDetected(task.fileName);

      // Step 1: Extract metadata from file
      task.status = ImportStatus.extractingMetadata;
      _onProgress?.call(_tasks);
      log.extractingMetadata(task.fileName);

      await _extractMetadata(task);
      log.metadataExtracted(task.title, task.artist);

      // Step 2: Try fingerprint matching first (most accurate for known songs)
      task.status = ImportStatus.matchingWithAI; // Reuse status
      _onProgress?.call(_tasks);

      final fingerprintResult = await _tryFingerprintMatch(task);
      if (fingerprintResult != null && fingerprintResult.hasSpotifyId) {
        // Fingerprint found a match with Spotify ID!
        task.aiMatchResult = LlmMatchResult(
          title: fingerprintResult.title ?? task.title ?? '',
          artist: fingerprintResult.artist ?? task.artist ?? '',
          album: fingerprintResult.album ?? '',
          spotifyId: fingerprintResult.spotifyId!,
          confidence: fingerprintResult.confidence,
          reasoning: 'Identified via audio fingerprint (AcoustID)',
        );
        debugPrint(
          '🎯 Fingerprint match: ${fingerprintResult.title} - ${fingerprintResult.artist}',
        );
      } else {
        // Fallback to AI matching
        debugPrint('🤖 Fingerprint not found, trying AI matching...');
        await _matchWithAI(task);
      }

      // Step 3: Check confidence and decide whether to auto-upload or ask for review
      if (task.aiMatchResult != null) {
        if (task.aiMatchResult!.isHighConfidence) {
          // High confidence - auto-upload without asking
          debugPrint(
            '🚀 High confidence match (${(task.aiMatchResult!.confidence * 100).toStringAsFixed(0)}%) - auto-uploading',
          );

          // Set the spotifyId from the AI match
          task.spotifyId = task.aiMatchResult!.spotifyId;
          task.title = task.aiMatchResult!.title;
          task.artist = task.aiMatchResult!.artist;
          task.album = task.aiMatchResult!.album;

          // Continue directly to upload
          task.status = ImportStatus.uploading;
          _onProgress?.call(_tasks);
          log.uploadStarted(task.fileName);

          final success = await _uploadFile(task);

          if (success) {
            task.status = ImportStatus.completed;
            log.uploadComplete(task.fileName);
            log.importComplete(task.fileName);
            await _moveToProcessed(task);
          } else {
            task.status = ImportStatus.failed;
            task.errorMessage ??= 'Upload failed';
            log.uploadFailed(
              task.fileName,
              task.errorMessage ?? 'Unknown error',
            );
          }

          _onProgress?.call(_tasks);
          _onComplete?.call(task, task.status == ImportStatus.completed);
          return;
        } else {
          // Low confidence - ask for user review
          debugPrint(
            '⚠️ Low confidence match (${(task.aiMatchResult!.confidence * 100).toStringAsFixed(0)}%) - requesting user review',
          );
          task.status = ImportStatus.awaitingReview;
          _onProgress?.call(_tasks);

          // Persist task so it survives app restart
          await ImportTaskPersistence.instance.saveTaskAwaitingReview(task);

          _onReviewNeeded?.call(task);
          return;
        }
      }

      // No match found - show review so user can manually search
      debugPrint('❌ No AI match found - requesting user input');
      task.status = ImportStatus.awaitingReview;
      _onProgress?.call(_tasks);

      // Persist task so it survives app restart
      await ImportTaskPersistence.instance.saveTaskAwaitingReview(task);

      _onReviewNeeded?.call(task);
      return;
    } catch (e) {
      task.status = ImportStatus.failed;
      task.errorMessage = e.toString();
      log.importFailed(task.fileName, e.toString());
      debugPrint('⚠️ Import failed for ${task.fileName}: $e');
      _onProgress?.call(_tasks);
      _onComplete?.call(task, false);
    }
  }

  /// Accept the AI match and continue with upload
  Future<void> acceptMatch(
    ImportTask task, {
    String? spotifyId,
    String? title,
    String? artist,
    String? album,
  }) async {
    final log = ImportLogService.instance;

    // Update task with accepted values
    task.spotifyId =
        spotifyId ?? task.aiMatchResult?.spotifyId ?? task.spotifyId;
    if (title != null) task.title = title;
    if (artist != null) task.artist = artist;
    if (album != null) task.album = album;

    // Check if we have a Spotify ID now
    if (task.spotifyId == null || task.spotifyId!.isEmpty) {
      task.status = ImportStatus.failed;
      task.errorMessage = 'No Spotify ID provided';
      log.importFailed(task.fileName, 'No Spotify ID');
      _onProgress?.call(_tasks);
      _onComplete?.call(task, false);
      return;
    }

    try {
      // Continue with upload
      task.status = ImportStatus.uploading;
      _onProgress?.call(_tasks);
      log.uploadStarted(task.fileName);

      final success = await _uploadFile(task);

      if (success) {
        task.status = ImportStatus.completed;
        log.uploadComplete(task.fileName);
        log.importComplete(task.fileName);

        // Move file to a "processed" subfolder
        await _moveToProcessed(task);
      } else {
        task.status = ImportStatus.failed;
        task.errorMessage ??= 'Upload failed';
        log.uploadFailed(task.fileName, task.errorMessage ?? 'Unknown error');
      }
    } catch (e) {
      task.status = ImportStatus.failed;
      task.errorMessage = e.toString();
      log.importFailed(task.fileName, e.toString());
      debugPrint('⚠️ Upload failed for ${task.fileName}: $e');
    }

    _onProgress?.call(_tasks);
    _onComplete?.call(task, task.status == ImportStatus.completed);

    // Remove from persistence (task is now processed)
    await ImportTaskPersistence.instance.removeTask(task.file.path);

    // Continue processing other tasks
    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Reject the AI match - skip this file
  Future<void> rejectMatch(ImportTask task) async {
    final log = ImportLogService.instance;

    task.status = ImportStatus.skipped;
    task.errorMessage = 'Skipped by user';
    log.warning('Skipped: ${task.fileName}');

    _onProgress?.call(_tasks);
    _onComplete?.call(task, false);

    // Remove from persistence
    await ImportTaskPersistence.instance.removeTask(task.file.path);

    // Move to a "skipped" subfolder
    _moveToSkipped(task);

    // Continue processing other tasks
    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Move skipped file to a subfolder
  Future<void> _moveToSkipped(ImportTask task) async {
    try {
      final importFolder = ImportFolderService.instance.importFolderPath;
      if (importFolder == null) return;

      final skippedFolder = Directory('$importFolder/Skipped');
      if (!await skippedFolder.exists()) {
        await skippedFolder.create();
      }

      final newPath = '${skippedFolder.path}/${task.fileName}';
      await task.file.rename(newPath);

      debugPrint('📦 Moved to skipped: ${task.fileName}');
    } catch (e) {
      // If move fails, just leave the file
      debugPrint('⚠️ Could not move file: $e');
    }
  }

  /// Extract metadata from the audio file using pure Dart package
  Future<void> _extractMetadata(ImportTask task) async {
    try {
      final metadata = readMetadata(task.file, getImage: false);

      task.title = metadata.title ?? _titleFromFileName(task.fileName);
      task.artist = metadata.artist;
      task.album = metadata.album;

      debugPrint('📝 Extracted: ${task.title} - ${task.artist}');
    } catch (e) {
      debugPrint('⚠️ Failed to extract metadata: $e');
      task.title = _titleFromFileName(task.fileName);
    }
  }

  /// Convert filename to title (remove extension, replace underscores, etc.)
  String _titleFromFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'\.[^.]+$'), '') // Remove extension
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();
  }

  /// Match with AI for Spotify ID
  /// Uses Smart Match LLM extension for intelligent reasoning
  Future<void> _matchWithAI(ImportTask task) async {
    final extManager = ExtensionManagerService.instance;

    // Check if AI matching is available
    if (!extManager.isSmartMatchAvailable) {
      debugPrint(
        '⚠️ Smart Match AI not available. Please install the extension in Settings.',
      );
      task.status = ImportStatus.waitingForAI;
      return;
    }

    debugPrint('🔍 Intelligent AI matching for: ${task.fileName}');
    final matchResult = await _trySmartMatch(task);

    if (matchResult != null) {
      // Store the match result for user review
      task.aiMatchResult = matchResult;
      debugPrint(
        '🤖 AI found match: "${matchResult.title}" by ${matchResult.artist}',
      );
    } else {
      debugPrint('❌ AI could not find a confident match for: ${task.fileName}');
      task.errorMessage = 'AI matching failed to find a confident result';
    }
  }

  /// Try matching using LLM-powered intelligent matching
  /// Returns the full LlmMatchResult for user review
  Future<LlmMatchResult?> _trySmartMatch(ImportTask task) async {
    final log = ImportLogService.instance;

    try {
      final llmMatch = LlmMatchService.instance;
      log.tryingSmartMatch(task.fileName);

      // Use extracted metadata for LLM matching
      if (task.title == null || task.title!.isEmpty) {
        log.warning('No title available for LLM matching');
        return null;
      }

      final result = await llmMatch.findBestMatch(
        title: task.title!,
        artist: task.artist,
        album: task.album,
      );

      if (result == null) {
        log.warning('LLM matching did not find a suitable result');
        return null;
      }

      log.spotifyMatch(result.title, result.artist, result.spotifyId);
      if (result.reasoning.isNotEmpty) {
        debugPrint('💭 Reasoning: ${result.reasoning}');
      }
      return result;
    } catch (e) {
      log.error('LLM matching failed', details: e.toString());
      debugPrint('⚠️ LLM matching failed: $e');
      return null;
    }
  }

  /// Try matching using audio fingerprint (server-side AcoustID)
  /// This is the most accurate method for known songs
  Future<FingerprintResult?> _tryFingerprintMatch(ImportTask task) async {
    final log = ImportLogService.instance;
    final fingerprintService = FingerprintService.instance;

    try {
      // Check if fingerprinting is available on the backend
      final isAvailable = await fingerprintService.isAvailable();
      if (!isAvailable) {
        debugPrint('🔇 Fingerprint service not available on backend');
        return null;
      }

      debugPrint(
        '🔍 Sending audio for fingerprint identification: ${task.fileName}',
      );
      log.info('Identifying via audio fingerprint...');

      final result = await fingerprintService.identifyAudio(task.file);

      if (result == null) {
        debugPrint('❌ Fingerprint identification failed');
        return null;
      }

      if (!result.found) {
        debugPrint('❌ No fingerprint match found');
        return null;
      }

      if (result.hasSpotifyId) {
        log.info(
          'Fingerprint: ${result.title} by ${result.artist} (${(result.confidence * 100).toStringAsFixed(0)}%)',
        );
      }

      return result;
    } catch (e) {
      log.warning('Fingerprint matching failed: $e');
      debugPrint('⚠️ Fingerprint matching error: $e');
      return null;
    }
  }

  /// Upload the file to the server
  Future<bool> _uploadFile(ImportTask task) async {
    if (task.spotifyId == null) {
      task.errorMessage = 'No Spotify ID available';
      return false;
    }

    try {
      final apiService = ApiService();
      final result = await apiService.uploadSongWithProgress(
        task.spotifyId!,
        task.file.path,
        onProgress: (progress) {
          task.uploadProgress = progress;
          _onProgress?.call(_tasks);
        },
      );

      final (success, message) = result;
      if (!success) {
        task.errorMessage = message;
      }

      debugPrint(
        success ? '✅ Uploaded: ${task.fileName}' : '❌ Upload failed: $message',
      );
      return success;
    } catch (e) {
      debugPrint('⚠️ Upload failed: $e');
      task.errorMessage = e.toString();
      return false;
    }
  }

  /// Move processed file to a subfolder
  Future<void> _moveToProcessed(ImportTask task) async {
    try {
      final importFolder = ImportFolderService.instance.importFolderPath;
      if (importFolder == null) return;

      final processedFolder = Directory('$importFolder/Processed');
      if (!await processedFolder.exists()) {
        await processedFolder.create();
      }

      final newPath = '${processedFolder.path}/${task.fileName}';
      await task.file.rename(newPath);

      debugPrint('📦 Moved to processed: ${task.fileName}');
    } catch (e) {
      // If move fails, just leave the file
      debugPrint('⚠️ Could not move file: $e');
    }
  }

  /// Clear completed/failed tasks from the list
  void clearCompletedTasks() {
    _tasks.removeWhere(
      (t) =>
          t.status == ImportStatus.completed || t.status == ImportStatus.failed,
    );
    _onProgress?.call(_tasks);
  }

  /// Retry failed tasks
  Future<void> retryFailedTasks() async {
    for (final task in _tasks) {
      if (task.status == ImportStatus.failed) {
        task.status = ImportStatus.pending;
        task.errorMessage = null;
        task.uploadProgress = 0.0;
      }
    }

    _onProgress?.call(_tasks);

    if (!_isProcessing) {
      _processQueue();
    }
  }

  /// Dispose resources
  void dispose() {
    _tasks.clear();
    _instance = null;
  }
}
