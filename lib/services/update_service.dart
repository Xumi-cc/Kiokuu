import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Type of installation on Linux
enum LinuxInstallationType {
  appImage,
  flatpak,
  systemPackage, // deb, rpm, etc.
  unknown,
}

/// Information about an available update
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String minimumVersion;
  final String releaseNotes;
  final String forceUpdateMessage;
  final String? downloadUrl;
  final String changelogUrl;
  final bool isForced;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumVersion,
    required this.releaseNotes,
    required this.forceUpdateMessage,
    this.downloadUrl,
    required this.changelogUrl,
    required this.isForced,
  });
}

/// Service for checking and managing app updates via GitHub releases
class UpdateService {
  static const String _owner = 'Xumi-cc';
  static const String _repo = 'Kiokuu';

  /// URL to fetch version.json from the main branch
  static const String _versionJsonUrl =
      'https://raw.githubusercontent.com/$_owner/$_repo/main/version.json';

  /// GitHub Releases API URL
  static const String _releasesApiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Key for storing last update check time
  static const String _lastCheckKey = 'last_update_check';

  /// Key for storing dismissed version (for optional updates)
  static const String _dismissedVersionKey = 'dismissed_update_version';

  /// Minimum interval between update checks (in hours)
  static const int _checkIntervalHours = 6;

  /// Singleton instance
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// Cached package info
  PackageInfo? _packageInfo;

  /// Check for updates
  /// Returns UpdateInfo if an update is available, null otherwise
  /// Set [force] to true to bypass the check interval
  Future<UpdateInfo?> checkForUpdate({bool force = false}) async {
    try {
      // Skip update checks on web
      if (kIsWeb) return null;

      // Check if we should skip this check (rate limiting)
      if (!force && !await _shouldCheckForUpdate()) {
        debugPrint('[UpdateService] Update check skipped (checked recently)');
        return null;
      }

      // Get current version
      _packageInfo ??= await PackageInfo.fromPlatform();
      final currentVersion = _packageInfo!.version;
      debugPrint('[UpdateService] Current app version: $currentVersion');

      // Fetch version info
      final versionInfo = await _fetchVersionInfo();
      if (versionInfo == null) {
        debugPrint('[UpdateService] Failed to fetch version info');
        return null;
      }

      // Record this check
      await _recordUpdateCheck();

      final latestVersion = versionInfo['latest_version'] as String;
      final minimumVersion = versionInfo['minimum_version'] as String;

      debugPrint('[UpdateService] Latest version: $latestVersion');
      debugPrint('[UpdateService] Minimum version: $minimumVersion');

      // Check if update is needed
      final isForced = _isVersionLower(currentVersion, minimumVersion);
      final hasUpdate = _isVersionLower(currentVersion, latestVersion);

      if (!hasUpdate) {
        debugPrint('[UpdateService] App is up to date');
        return null;
      }

      // Check if user dismissed this optional update
      if (!isForced) {
        final dismissedVersion = await _getDismissedVersion();
        if (dismissedVersion == latestVersion) {
          debugPrint('[UpdateService] User dismissed update to $latestVersion');
          return null;
        }
      }

      debugPrint(
        isForced
            ? '[UpdateService] FORCED update required!'
            : '[UpdateService] Optional update available',
      );

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        minimumVersion: minimumVersion,
        releaseNotes: versionInfo['release_notes'] as String? ?? '',
        forceUpdateMessage:
            versionInfo['force_update_message'] as String? ??
            'Please update to continue.',
        downloadUrl: _getDownloadUrl(versionInfo, latestVersion),
        changelogUrl:
            versionInfo['changelog_url'] as String? ??
            'https://github.com/$_owner/$_repo/releases/latest',
        isForced: isForced,
      );
    } catch (e) {
      debugPrint('[UpdateService] Update check failed: $e');
      return null;
    }
  }

  /// Fetch version info from version.json in the repo
  Future<Map<String, dynamic>?> _fetchVersionInfo() async {
    try {
      final response = await http
          .get(Uri.parse(_versionJsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      debugPrint(
        '[UpdateService] Failed to fetch version.json: ${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('[UpdateService] Error fetching version.json: $e');
      return null;
    }
  }

  /// Fetch latest release info from GitHub API (alternative method)
  Future<Map<String, dynamic>?> fetchLatestRelease() async {
    try {
      final response = await http
          .get(
            Uri.parse(_releasesApiUrl),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      debugPrint(
        '[UpdateService] Failed to fetch GitHub release: ${response.statusCode}',
      );
      return null;
    } catch (e) {
      debugPrint('[UpdateService] Error fetching GitHub release: $e');
      return null;
    }
  }

  /// Get platform-specific download URL
  String? _getDownloadUrl(Map<String, dynamic> versionInfo, String version) {
    final downloadUrls = versionInfo['download_urls'] as Map<String, dynamic>?;
    if (downloadUrls == null) return null;

    String? urlTemplate;

    if (Platform.isAndroid) {
      final androidUrls = downloadUrls['android'];
      if (androidUrls is Map<String, dynamic>) {
        // Prefer arm64, then arm32, then x86_64
        urlTemplate =
            androidUrls['arm64'] as String? ??
            androidUrls['arm32'] as String? ??
            androidUrls['x86_64'] as String?;
      } else if (androidUrls is String) {
        urlTemplate = androidUrls;
      }
    } else if (Platform.isIOS) {
      final iosUrls = downloadUrls['ios'];
      if (iosUrls is Map<String, dynamic>) {
        urlTemplate = iosUrls['ipa'] as String?;
      } else if (iosUrls is String) {
        urlTemplate = iosUrls;
      }
    } else if (Platform.isWindows) {
      final windowsUrls = downloadUrls['windows'];
      if (windowsUrls is Map<String, dynamic>) {
        // Prefer portable, then msix
        urlTemplate =
            windowsUrls['portable'] as String? ??
            windowsUrls['msix'] as String?;
      } else if (windowsUrls is String) {
        urlTemplate = windowsUrls;
      }
    } else if (Platform.isMacOS) {
      final macosUrls = downloadUrls['macos'];
      if (macosUrls is Map<String, dynamic>) {
        urlTemplate = macosUrls['dmg'] as String?;
      } else if (macosUrls is String) {
        urlTemplate = macosUrls;
      }
    } else if (Platform.isLinux) {
      final installType = _getLinuxInstallationType();
      debugPrint('[UpdateService] Linux installation type: $installType');

      final linuxUrls = downloadUrls['linux'];
      if (linuxUrls is Map<String, dynamic>) {
        // Match URL to installation type
        switch (installType) {
          case LinuxInstallationType.appImage:
            urlTemplate = linuxUrls['appimage'] as String?;
            break;
          case LinuxInstallationType.flatpak:
            urlTemplate = linuxUrls['flatpak'] as String?;
            break;
          case LinuxInstallationType.systemPackage:
            // For system packages, go to releases page
            return versionInfo['changelog_url'] as String? ??
                'https://github.com/$_owner/$_repo/releases/latest';
          case LinuxInstallationType.unknown:
            // Default to AppImage
            urlTemplate = linuxUrls['appimage'] as String?;
            break;
        }
      } else if (linuxUrls is String) {
        if (installType == LinuxInstallationType.appImage ||
            installType == LinuxInstallationType.unknown) {
          urlTemplate = linuxUrls;
        } else {
          return versionInfo['changelog_url'] as String? ??
              'https://github.com/$_owner/$_repo/releases/latest';
        }
      }
    }

    return urlTemplate?.replaceAll('{version}', version);
  }

  /// Detect how the app is installed on Linux
  LinuxInstallationType _getLinuxInstallationType() {
    if (!Platform.isLinux) return LinuxInstallationType.unknown;

    // Check for AppImage
    if (Platform.environment.containsKey('APPIMAGE')) {
      return LinuxInstallationType.appImage;
    }

    // Check for Flatpak
    if (Platform.environment.containsKey('FLATPAK_ID') ||
        File('/.flatpak-info').existsSync()) {
      return LinuxInstallationType.flatpak;
    }

    // Check executable path
    final exePath = Platform.executable;
    if (exePath.startsWith('/usr/bin') ||
        exePath.startsWith('/opt/') ||
        exePath.startsWith('/usr/lib')) {
      return LinuxInstallationType.systemPackage;
    }

    return LinuxInstallationType.unknown;
  }

  /// Compare versions - returns true if v1 < v2
  bool _isVersionLower(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    // Pad with zeros if needed
    while (parts1.length < 3) parts1.add(0);
    while (parts2.length < 3) parts2.add(0);

    for (int i = 0; i < 3; i++) {
      if (parts1[i] < parts2[i]) return true;
      if (parts1[i] > parts2[i]) return false;
    }

    return false; // Equal versions
  }

  /// Check if we should perform an update check based on rate limiting
  Future<bool> _shouldCheckForUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey);

      if (lastCheck == null) return true;

      final lastCheckTime = DateTime.fromMillisecondsSinceEpoch(lastCheck);
      final now = DateTime.now();
      final difference = now.difference(lastCheckTime);

      return difference.inHours >= _checkIntervalHours;
    } catch (e) {
      return true;
    }
  }

  /// Record that we performed an update check
  Future<void> _recordUpdateCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[UpdateService] Failed to record update check time: $e');
    }
  }

  /// Get the version that user dismissed
  Future<String?> _getDismissedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_dismissedVersionKey);
    } catch (e) {
      return null;
    }
  }

  /// Dismiss an optional update (user chose "Later")
  Future<void> dismissUpdate(String version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dismissedVersionKey, version);
      debugPrint('[UpdateService] User dismissed update to $version');
    } catch (e) {
      debugPrint('[UpdateService] Failed to save dismissed version: $e');
    }
  }

  /// Clear dismissed update (useful for testing or forcing re-prompt)
  Future<void> clearDismissedUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_dismissedVersionKey);
    } catch (e) {
      debugPrint('[UpdateService] Failed to clear dismissed version: $e');
    }
  }

  /// Get the current app version
  Future<String> getCurrentVersion() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!.version;
  }

  /// Get full version string including build number
  Future<String> getFullVersion() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return '${_packageInfo!.version}+${_packageInfo!.buildNumber}';
  }
}
