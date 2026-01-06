import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage the import folder for auto-importing music files.
///
/// On Android: Uses SAF (Storage Access Framework) to let user pick any folder.
/// This is Google Play compliant and doesn't require MANAGE_EXTERNAL_STORAGE.
///
/// On Desktop: Creates a ~/KioKuu folder with system bookmark integration.
class ImportFolderService {
  static ImportFolderService? _instance;
  static ImportFolderService get instance =>
      _instance ??= ImportFolderService._();

  ImportFolderService._();

  String? _importFolderPath;
  static const String _customFolderKey = 'custom_import_folder_path';
  static const String _hasPromptedFolderKey = 'has_prompted_import_folder';

  /// Get the import folder path
  String? get importFolderPath => _importFolderPath;

  /// Check if we have a valid import folder configured
  bool get hasImportFolder =>
      _importFolderPath != null && _importFolderPath!.isNotEmpty;

  /// Check if user has been prompted to select a folder (Android only)
  Future<bool> hasPromptedForFolder() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasPromptedFolderKey) ?? false;
  }

  /// Mark that user has been prompted for folder selection
  Future<void> setPromptedForFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasPromptedFolderKey, true);
  }

  /// Initialize the import folder - call this on app startup
  /// On Android, this will use the user-selected folder via SAF
  /// On Desktop, this will create/use the default ~/KioKuu folder
  Future<void> initialize() async {
    if (kIsWeb) return; // Not supported on web

    try {
      // Check if user has set a custom folder (via SAF or manual selection)
      final prefs = await SharedPreferences.getInstance();
      final customPath = prefs.getString(_customFolderKey);

      if (customPath != null && customPath.isNotEmpty) {
        // Verify the folder still exists and is accessible
        final customDir = Directory(customPath);
        if (await customDir.exists()) {
          _importFolderPath = customPath;
          debugPrint('📁 Using saved import folder: $customPath');
          return;
        } else {
          // Folder no longer exists or accessible, clear it
          await prefs.remove(_customFolderKey);
          debugPrint('⚠️ Saved folder no longer accessible, cleared');
        }
      }

      // On Android, we need user to pick a folder via SAF
      // Don't auto-create folder - wait for user selection
      if (Platform.isAndroid) {
        debugPrint(
          '📁 Android: Waiting for user to select import folder via SAF',
        );
        // Use app-specific storage as a fallback until user picks a folder
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final fallbackPath = '${directory.path}/Import';
          final fallbackDir = Directory(fallbackPath);
          if (!await fallbackDir.exists()) {
            await fallbackDir.create(recursive: true);
          }
          _importFolderPath = fallbackPath;
          debugPrint('📁 Using app-specific fallback: $fallbackPath');
        }
        return;
      }

      // On Desktop, create the default import folder
      _importFolderPath = await _createDesktopImportFolder();

      if (_importFolderPath != null) {
        // Add to system bookmarks based on platform
        await _addToSystemBookmarks(_importFolderPath!);
        debugPrint('📁 Import folder ready: $_importFolderPath');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to initialize import folder: $e');
    }
  }

  /// Open folder picker using SAF (Android) or native picker (Desktop)
  /// Returns true if folder was successfully selected
  Future<bool> pickImportFolder() async {
    try {
      // Use file_picker to select a directory
      // On Android, this uses SAF and grants persistent URI permissions
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Import Folder',
        lockParentWindow: true,
      );

      if (result != null && result.isNotEmpty) {
        return await setCustomImportFolder(result);
      }

      debugPrint('📁 Folder selection cancelled');
      return false;
    } catch (e) {
      debugPrint('⚠️ Failed to pick folder: $e');
      return false;
    }
  }

  /// Set a custom import folder path
  Future<bool> setCustomImportFolder(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        debugPrint('⚠️ Folder does not exist: $folderPath');
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_customFolderKey, folderPath);
      _importFolderPath = folderPath;

      // Add to system bookmarks (Desktop only)
      if (!Platform.isAndroid && !Platform.isIOS) {
        await _addToSystemBookmarks(folderPath);
      }

      debugPrint('✅ Import folder set: $folderPath');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to set custom folder: $e');
      return false;
    }
  }

  /// Clear custom import folder and revert to default
  Future<void> clearCustomImportFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_customFolderKey);
      _importFolderPath = null;

      // Reinitialize
      await initialize();
      debugPrint('✅ Reverted to default import folder');
    } catch (e) {
      debugPrint('⚠️ Failed to clear custom folder: $e');
    }
  }

  /// Check if user has set a custom folder
  Future<bool> hasCustomFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final customPath = prefs.getString(_customFolderKey);
    return customPath != null && customPath.isNotEmpty;
  }

  /// Create the import folder for Desktop platforms
  Future<String?> _createDesktopImportFolder() async {
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
    } else {
      // Unsupported platform, use app documents
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
        debugPrint('⚠️ Failed to create folder: $e');
        return null;
      }
    }

    return folderPath;
  }

  /// Add the import folder to system bookmarks/favorites (Desktop only)
  Future<void> _addToSystemBookmarks(String folderPath) async {
    if (Platform.isLinux) {
      await _addToLinuxBookmarks(folderPath);
    } else if (Platform.isMacOS) {
      await _addToMacOSFavorites(folderPath);
    } else if (Platform.isWindows) {
      await _addToWindowsQuickAccess(folderPath);
    }
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
