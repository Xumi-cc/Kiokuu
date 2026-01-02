import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Callback for download progress (0.0 to 1.0)
typedef OnDownloadProgress = void Function(double progress);

/// Status of an extension
enum ExtensionStatus { notInstalled, downloading, installed, error }

/// Definition of an available extension
class ExtensionInfo {
  final String id;
  final String name;
  final String modelName; // e.g., "all-MiniLM-L6-v2"
  final String description;
  final String version;
  final String downloadUrl;
  final List<String> capabilities;
  final IconType iconType;
  final String? ramRequirement;

  const ExtensionInfo({
    required this.id,
    required this.name,
    required this.modelName,
    required this.description,
    required this.version,
    required this.downloadUrl,
    required this.capabilities,
    this.iconType = IconType.generic,
    this.ramRequirement,
  });
}

enum IconType { generic, ai }

/// Manages downloadable extensions for the app
class ExtensionManagerService {
  static final ExtensionManagerService instance = ExtensionManagerService._();
  ExtensionManagerService._();

  String? _extensionsPath;
  final Map<String, ExtensionStatus> _extensionStatus = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, int> _extensionSizes = {}; // Fetched sizes
  final Map<String, bool> _extensionEnabled = {}; // Enable/disable state

  /// Smart Match now uses backend AI API
  /// Premium+ subscription required
  static const String _enabledKeyPrefix = 'extension_enabled_';

  /// Available extensions
  static List<ExtensionInfo> get availableExtensions => [
    ExtensionInfo(
      id: 'smart-match',
      name: 'Smart Match (AI)',
      modelName: 'Cloud AI',
      description:
          'AI-powered song matching. Understands artist names across languages and distinguishes originals from covers. Requires Premium+ subscription.',
      version: '5.0.0',
      downloadUrl: '', // No download needed - uses backend API
      capabilities: [
        'llm-reasoning',
        'multilingual',
        'artist-matching',
        'cover-detection',
      ],
      iconType: IconType.ai,
      ramRequirement: '0 MB (Cloud)',
    ),
  ];

  /// Initialize the extension manager
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      _extensionsPath = '${appDir.path}/extensions';

      final extDir = Directory(_extensionsPath!);
      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }

      // Scan which extensions are already installed
      await _scanInstalledExtensions();

      // Load enabled states from SharedPreferences
      await _loadEnabledStates();

      // Fetch sizes for available extensions in background
      _fetchExtensionSizes();

      debugPrint('📦 ExtensionManager initialized at: $_extensionsPath');
    } catch (e) {
      debugPrint('⚠️ Failed to initialize ExtensionManager: $e');
    }
  }

  /// Load enabled states from SharedPreferences
  Future<void> _loadEnabledStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final ext in availableExtensions) {
        final key = '$_enabledKeyPrefix${ext.id}';
        if (prefs.containsKey(key)) {
          _extensionEnabled[ext.id] = prefs.getBool(key) ?? true;
        } else {
          // Default to true for smart-match (cloud-based),
          // but for others it might depend on if they are installed
          _extensionEnabled[ext.id] = true;
        }
      }
      debugPrint('⚙️ Extension states loaded: $_extensionEnabled');
    } catch (e) {
      debugPrint('⚠️ Failed to load extension states: $e');
    }
  }

  /// Fetch file sizes from remote URLs
  Future<void> _fetchExtensionSizes() async {
    for (final ext in availableExtensions) {
      if (ext.downloadUrl.isEmpty) continue;

      try {
        final request = http.Request('HEAD', Uri.parse(ext.downloadUrl));
        final response = await http.Client().send(request);

        final contentLength = response.contentLength;
        if (contentLength != null && contentLength > 0) {
          _extensionSizes[ext.id] = contentLength;
          debugPrint('📏 ${ext.name} size: ${_formatSize(contentLength)}');
        }
      } catch (e) {
        debugPrint('⚠️ Could not fetch size for ${ext.name}: $e');
      }
    }
  }

  /// Format bytes to human readable string
  String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Download a file from URL directly to disk (streaming)
  Future<void> _downloadToPath(
    String url,
    String path,
    void Function(double)? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final totalBytes = response.contentLength ?? 0;
    var receivedBytes = 0;

    final file = File(path);
    final sink = file.openWrite();

    try {
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          onProgress?.call(progress);
        }
      });
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  /// Get formatted size for an extension
  String getFormattedSize(String extensionId) {
    final size = _extensionSizes[extensionId];
    if (size != null) {
      return _formatSize(size);
    }
    // Return estimated size if not fetched yet
    if (extensionId == 'smart-match') return '~120 MB';
    return '...';
  }

  /// Scan for already installed extensions
  Future<void> _scanInstalledExtensions() async {
    for (final ext in availableExtensions) {
      final manifestFile = File('$_extensionsPath/${ext.id}/manifest.json');
      if (await manifestFile.exists()) {
        _extensionStatus[ext.id] = ExtensionStatus.installed;
        _downloadProgress[ext.id] = 1.0;
        debugPrint('✅ Extension found: ${ext.name}');
      } else {
        _extensionStatus[ext.id] = ExtensionStatus.notInstalled;
        _downloadProgress[ext.id] = 0.0;
      }
    }
  }

  /// Get the status of an extension
  ExtensionStatus getStatus(String extensionId) {
    return _extensionStatus[extensionId] ?? ExtensionStatus.notInstalled;
  }

  /// Get download progress for an extension (0.0 to 1.0)
  double getProgress(String extensionId) {
    return _downloadProgress[extensionId] ?? 0.0;
  }

  /// Check if a specific extension is installed
  bool isInstalled(String extensionId) {
    final ext = getExtensionInfo(extensionId);
    if (ext != null && ext.downloadUrl.isEmpty) {
      return true; // Cloud-based extensions are always "installed"
    }
    return _extensionStatus[extensionId] == ExtensionStatus.installed;
  }

  /// Check if extension is enabled (installed AND enabled)
  bool isEnabled(String extensionId) {
    return isInstalled(extensionId) && (_extensionEnabled[extensionId] ?? true);
  }

  /// Enable or disable an extension
  Future<void> setEnabled(String extensionId, bool enabled) async {
    _extensionEnabled[extensionId] = enabled;

    // Persist the state
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_enabledKeyPrefix$extensionId', enabled);
    } catch (e) {
      debugPrint('⚠️ Failed to persist extension state: $e');
    }

    debugPrint(
      '${enabled ? "✅" : "⏸️"} $extensionId ${enabled ? "enabled" : "disabled"}',
    );
  }

  /// Convenience getters - only return true if installed AND enabled
  /// For smart-match, it's always "available" since it's backend-based
  /// The backend will check Premium+ subscription
  bool get isSmartMatchAvailable => _extensionEnabled['smart-match'] ?? true;

  /// Enable smart match (called after API key is configured) - deprecated
  void enableSmartMatch() {
    _extensionStatus['smart-match'] = ExtensionStatus.installed;
    _extensionEnabled['smart-match'] = true;
    debugPrint('✅ Smart Match enabled (Cloud AI)');
  }

  /// Disable smart match - deprecated
  void disableSmartMatch() {
    _extensionEnabled['smart-match'] = false;
    debugPrint('⏸️ Smart Match disabled');
  }

  /// Check if AI matching is available
  bool get isAudioFingerprintAvailable => isSmartMatchAvailable;

  /// Get extension info by ID
  ExtensionInfo? getExtensionInfo(String extensionId) {
    try {
      return availableExtensions.firstWhere((e) => e.id == extensionId);
    } catch (_) {
      return null;
    }
  }

  /// Get path to an installed extension
  String? getExtensionPath(String extensionId) {
    if (!isInstalled(extensionId)) return null;
    return '$_extensionsPath/$extensionId';
  }

  /// Download and install an extension
  Future<bool> downloadExtension(
    String extensionId, {
    OnDownloadProgress? onProgress,
  }) async {
    final extension = availableExtensions.firstWhere(
      (e) => e.id == extensionId,
      orElse: () => throw Exception('Extension not found: $extensionId'),
    );

    if (_extensionsPath == null) {
      debugPrint('⚠️ Extensions path not initialized');
      return false;
    }

    try {
      _extensionStatus[extensionId] = ExtensionStatus.downloading;
      _downloadProgress[extensionId] = 0.0;

      final extDir = Directory('$_extensionsPath/$extensionId');
      if (!await extDir.exists()) {
        await extDir.create(recursive: true);
      }

      // Handle mobile platforms that need native implementation
      if (extension.downloadUrl.isEmpty) {
        debugPrint('⚠️ ${extension.name} not available for this platform');
        _extensionStatus[extensionId] = ExtensionStatus.error;
        return false;
      }

      // Download the model file
      debugPrint('⬇️ Downloading ${extension.name} model...');

      // Save the model file
      String modelFilename;
      if (extensionId == 'smart-match') {
        // GGUF model for llama.cpp
        modelFilename = 'model.gguf';
      } else {
        modelFilename = 'model.onnx';
      }

      final modelFile = File('$_extensionsPath/$extensionId/$modelFilename');

      // Download directly to file (stream) to save memory
      await _downloadToPath(extension.downloadUrl, modelFile.path, (progress) {
        _downloadProgress[extensionId] = progress;
        onProgress?.call(progress);
      });

      final fileSize = await modelFile.length();
      debugPrint('🧠 Saved model: $modelFilename (${_formatSize(fileSize)})');

      // Create manifest
      final manifest = {
        'id': extension.id,
        'name': extension.name,
        'version': extension.version,
        'installed_at': DateTime.now().toIso8601String(),
        'capabilities': extension.capabilities,
        'files': [modelFilename],
        'size': fileSize,
      };

      final manifestFile = File('$_extensionsPath/$extensionId/manifest.json');
      await manifestFile.writeAsString(jsonEncode(manifest));

      _extensionStatus[extensionId] = ExtensionStatus.installed;
      _downloadProgress[extensionId] = 1.0;

      debugPrint('✅ Extension installed: ${extension.name}');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to download extension: $e');
      _extensionStatus[extensionId] = ExtensionStatus.error;
      return false;
    }
  }

  /// Uninstall an extension
  Future<bool> uninstallExtension(String extensionId) async {
    if (_extensionsPath == null) return false;

    try {
      final extDir = Directory('$_extensionsPath/$extensionId');
      if (await extDir.exists()) {
        await extDir.delete(recursive: true);
      }

      _extensionStatus[extensionId] = ExtensionStatus.notInstalled;
      _downloadProgress[extensionId] = 0.0;

      debugPrint('🗑️ Extension uninstalled: $extensionId');
      return true;
    } catch (e) {
      debugPrint('⚠️ Failed to uninstall extension: $e');
      return false;
    }
  }

  /// Get list of installed extension IDs
  List<String> get installedExtensionIds {
    return _extensionStatus.entries
        .where((e) => e.value == ExtensionStatus.installed)
        .map((e) => e.key)
        .toList();
  }

  /// Get total size of installed extensions
  int get installedExtensionsSize {
    var total = 0;
    for (final id in installedExtensionIds) {
      total += _extensionSizes[id] ?? 0;
    }
    return total;
  }
}
