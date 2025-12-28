import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service to manage the "KioKuu" import folder that appears in system file managers.
/// This folder is mounted/created automatically on app startup.
class ImportFolderService {
  static ImportFolderService? _instance;
  static ImportFolderService get instance =>
      _instance ??= ImportFolderService._();

  ImportFolderService._();

  String? _importFolderPath;

  /// Get the import folder path
  String? get importFolderPath => _importFolderPath;

  /// Initialize the import folder - call this on app startup
  /// Note: Does NOT request permissions - that's handled by PermissionScreen
  Future<void> initialize() async {
    if (kIsWeb) return; // Not supported on web

    try {
      // On Android, just check if we have permission (don't request here)
      if (Platform.isAndroid) {
        final hasPermission = await _hasStoragePermission();
        if (!hasPermission) {
          debugPrint(
            '⚠️ Storage permission not granted - using app-specific storage',
          );
        }
      }

      // Create the import folder
      _importFolderPath = await _createImportFolder();

      if (_importFolderPath != null) {
        // Add to system bookmarks based on platform
        await _addToSystemBookmarks(_importFolderPath!);
        debugPrint('📁 Import folder ready: $_importFolderPath');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to initialize import folder: $e');
    }
  }

  /// Check if storage permission is already granted (no request)
  Future<bool> _hasStoragePermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    return false;
  }

  /// Create the import folder in the appropriate location
  Future<String?> _createImportFolder() async {
    String folderPath;

    if (Platform.isLinux || Platform.isMacOS) {
      // Linux/macOS: ~/KioKuu
      final home = Platform.environment['HOME'];
      if (home == null) return null;
      folderPath = '$home/KioKuu';
    } else if (Platform.isWindows) {
      // Windows: %USERPROFILE%\KioKuu
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) return null;
      folderPath = '$userProfile\\KioKuu';
    } else if (Platform.isAndroid) {
      // Android: Create in user-accessible external storage
      // Try /storage/emulated/0/KioKuu first (visible in file managers)
      try {
        const externalPath = '/storage/emulated/0';
        final externalDir = Directory(externalPath);
        if (await externalDir.exists()) {
          folderPath = '$externalPath/KioKuu';
        } else {
          // Fallback to Download folder
          folderPath = '/storage/emulated/0/Download/KioKuu';
        }
      } catch (e) {
        // Last resort: use app-specific external directory
        final directory = await getExternalStorageDirectory();
        if (directory == null) return null;
        folderPath = '${directory.path}/Import';
        debugPrint('⚠️ Using app-specific storage: $folderPath');
      }
    } else {
      // iOS: Use app documents directory (limited due to sandboxing)
      final directory = await getApplicationDocumentsDirectory();
      folderPath = '${directory.path}/Import';
    }

    // Create the folder if it doesn't exist
    final folder = Directory(folderPath);
    if (!await folder.exists()) {
      try {
        await folder.create(recursive: true);
        debugPrint('📁 Created import folder: $folderPath');
      } catch (e) {
        debugPrint('⚠️ Failed to create folder at $folderPath: $e');
        // On Android, permission might be denied - try app-specific storage
        if (Platform.isAndroid) {
          final directory = await getExternalStorageDirectory();
          if (directory != null) {
            folderPath = '${directory.path}/Import';
            final appFolder = Directory(folderPath);
            if (!await appFolder.exists()) {
              await appFolder.create(recursive: true);
            }
            debugPrint('📁 Fallback to app storage: $folderPath');
          }
        }
      }
    }

    return folderPath;
  }

  /// Add the import folder to system bookmarks/favorites
  Future<void> _addToSystemBookmarks(String folderPath) async {
    if (Platform.isLinux) {
      await _addToLinuxBookmarks(folderPath);
    } else if (Platform.isMacOS) {
      await _addToMacOSFavorites(folderPath);
    } else if (Platform.isWindows) {
      await _addToWindowsQuickAccess(folderPath);
    }
    // Android & iOS: Native file managers handle this differently
    // Android DocumentsProvider will be added via native code
  }

  /// Linux: Add to GTK3 bookmarks (shows in Nautilus, Thunar, etc.)
  Future<void> _addToLinuxBookmarks(String folderPath) async {
    try {
      final home = Platform.environment['HOME'];
      if (home == null) return;

      final bookmarksFile = File('$home/.config/gtk-3.0/bookmarks');
      final bookmarkEntry =
          'file://${Uri.encodeComponent(folderPath).replaceAll('%2F', '/')} KioKuu';

      // Check if bookmark already exists
      if (await bookmarksFile.exists()) {
        final content = await bookmarksFile.readAsString();
        if (content.contains('KioKuu')) {
          debugPrint('📌 Bookmark already exists');
          return;
        }
        // Append to existing bookmarks
        await bookmarksFile.writeAsString(
          '$content\n$bookmarkEntry',
          mode: FileMode.write,
        );
      } else {
        // Create bookmarks file with our entry
        await bookmarksFile.parent.create(recursive: true);
        await bookmarksFile.writeAsString('$bookmarkEntry\n');
      }

      debugPrint('📌 Added to Linux bookmarks');
    } catch (e) {
      debugPrint('⚠️ Failed to add Linux bookmark: $e');
    }
  }

  /// macOS: Add to Finder sidebar favorites
  Future<void> _addToMacOSFavorites(String folderPath) async {
    try {
      // For full Finder sidebar integration, we'd need to use LSSharedFileList API via native code
      // For now, we'll use a simpler approach: open the folder once in Finder
      // This adds it to "Recents" and users can easily drag it to sidebar
      await Process.run('open', [folderPath]);

      debugPrint('📌 Opened folder in Finder (user can pin to sidebar)');
    } catch (e) {
      debugPrint('⚠️ Failed to add macOS favorite: $e');
    }
  }

  /// Windows: Add to Quick Access using PowerShell
  Future<void> _addToWindowsQuickAccess(String folderPath) async {
    try {
      // Use PowerShell to pin to Quick Access
      final script =
          '''
\$shell = New-Object -ComObject shell.application
\$folder = \$shell.Namespace("$folderPath")
\$folder.Self.InvokeVerb("pintohome")
''';

      await Process.run('powershell', ['-Command', script], runInShell: true);

      debugPrint('📌 Added to Windows Quick Access');
    } catch (e) {
      debugPrint('⚠️ Failed to add Windows Quick Access: $e');
    }
  }

  /// Check if a file is a supported audio format
  bool isSupportedAudioFile(String path) {
    final extensions = [
      '.mp3',
      '.flac',
      '.wav',
      '.m4a',
      '.aac',
      '.ogg',
      '.wma',
      '.opus',
    ];
    final lowercasePath = path.toLowerCase();
    return extensions.any((ext) => lowercasePath.endsWith(ext));
  }

  /// Get list of audio files currently in the import folder
  Future<List<FileSystemEntity>> getImportedFiles() async {
    if (_importFolderPath == null) return [];

    final folder = Directory(_importFolderPath!);
    if (!await folder.exists()) return [];

    final files = <FileSystemEntity>[];
    await for (final entity in folder.list()) {
      if (entity is File && isSupportedAudioFile(entity.path)) {
        files.add(entity);
      }
    }
    return files;
  }
}
