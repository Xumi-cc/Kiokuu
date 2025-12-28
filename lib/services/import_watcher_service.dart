import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'import_folder_service.dart';

/// Callback for when new audio files are detected in the import folder
typedef OnFilesDetected = void Function(List<File> files);

/// Service that watches the import folder for new audio files.
/// When files are detected, it triggers a callback for processing.
class ImportWatcherService {
  static ImportWatcherService? _instance;
  static ImportWatcherService get instance => _instance ??= ImportWatcherService._();
  
  ImportWatcherService._();
  
  StreamSubscription<FileSystemEvent>? _watchSubscription;
  Timer? _debounceTimer;
  final Set<String> _pendingFiles = {};
  OnFilesDetected? _onFilesDetected;
  bool _isWatching = false;
  
  /// Whether the watcher is currently active
  bool get isWatching => _isWatching;
  
  /// Start watching the import folder for new files
  void startWatching({required OnFilesDetected onFilesDetected}) {
    if (_isWatching) return;
    
    final importPath = ImportFolderService.instance.importFolderPath;
    if (importPath == null) {
      debugPrint('⚠️ Import folder not initialized');
      return;
    }
    
    _onFilesDetected = onFilesDetected;
    
    try {
      final directory = Directory(importPath);
      
      // Watch for file system events
      _watchSubscription = directory.watch(events: FileSystemEvent.all).listen(
        _handleFileSystemEvent,
        onError: (error) {
          debugPrint('⚠️ File watcher error: $error');
        },
      );
      
      _isWatching = true;
      debugPrint('👁️ Started watching import folder: $importPath');
      
      // Check for any existing files on startup
      _checkExistingFiles();
    } catch (e) {
      debugPrint('⚠️ Failed to start file watcher: $e');
    }
  }
  
  /// Stop watching the import folder
  void stopWatching() {
    _watchSubscription?.cancel();
    _watchSubscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingFiles.clear();
    _isWatching = false;
    debugPrint('🛑 Stopped watching import folder');
  }
  
  /// Handle file system events
  void _handleFileSystemEvent(FileSystemEvent event) {
    // We're interested in new files and modifications (in case of copy operations)
    if (event is FileSystemCreateEvent || event is FileSystemModifyEvent) {
      final path = event.path;
      
      // Check if it's a supported audio file
      if (ImportFolderService.instance.isSupportedAudioFile(path)) {
        _pendingFiles.add(path);
        _scheduleProcessing();
      }
    }
  }
  
  /// Debounce file processing to handle bulk copies
  void _scheduleProcessing() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), _processPendingFiles);
  }
  
  /// Process accumulated pending files
  void _processPendingFiles() {
    if (_pendingFiles.isEmpty) return;
    
    final files = _pendingFiles
        .map((path) => File(path))
        .where((file) => file.existsSync())
        .toList();
    
    if (files.isNotEmpty) {
      debugPrint('🎵 Detected ${files.length} new audio file(s)');
      _onFilesDetected?.call(files);
    }
    
    _pendingFiles.clear();
  }
  
  /// Check for existing files in the import folder (on startup)
  Future<void> _checkExistingFiles() async {
    final files = await ImportFolderService.instance.getImportedFiles();
    
    if (files.isNotEmpty) {
      debugPrint('🎵 Found ${files.length} existing file(s) in import folder');
      _onFilesDetected?.call(files.cast<File>());
    }
  }
  
  /// Dispose resources
  void dispose() {
    stopWatching();
    _instance = null;
  }
}
