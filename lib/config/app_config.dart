/// Centralized app configuration
/// Keep all environment-specific values here for easy management
class AppConfig {
  // ============================================================
  // API Configuration
  // ============================================================

  /// Backend API base URL
  static const String apiBaseUrl = 'https://mcloud.xumi.cc';

  /// WebSocket URL (derived from API URL)
  static String get wsBaseUrl {
    final uri = Uri.parse(apiBaseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}/ws';
  }

  // ============================================================
  // Share / Deep Linking Configuration
  // ============================================================

  /// Custom URL scheme for deep linking
  static const String urlScheme = 'kiokuu';

  /// Web share URL base (where share links point to)
  static String get shareBaseUrl => '$apiBaseUrl/s';

  /// Generate share URL for a token
  static String getShareUrl(String token) => '$shareBaseUrl/$token';

  // ============================================================
  // Download URLs (App Store Links)
  // ============================================================

  /// Android download URL (Play Store or direct APK)
  static const String androidDownloadUrl =
      'https://github.com/yourusername/music-cloud/releases/latest/download/music-cloud.apk';

  /// iOS download URL (App Store)
  static const String iosDownloadUrl =
      'https://apps.apple.com/app/music-cloud/id000000000';

  /// Windows download URL
  static const String windowsDownloadUrl =
      'https://github.com/yourusername/music-cloud/releases/latest/download/music-cloud-windows.exe';

  /// macOS download URL
  static const String macosDownloadUrl =
      'https://github.com/yourusername/music-cloud/releases/latest/download/music-cloud-macos.dmg';

  /// Linux download URL
  static const String linuxDownloadUrl =
      'https://github.com/yourusername/music-cloud/releases/latest/download/music-cloud-linux.AppImage';

  // ============================================================
  // Google OAuth Configuration
  // ============================================================

  /// Web Client ID from Google Cloud Console
  /// Used for getting ID tokens that backend can verify
  static const String googleWebClientId =
      '134771618917-p0jt8b9fg229viji2pde8v8b8qdpqhl9.apps.googleusercontent.com';

  /// Desktop OAuth callback port (local HTTP server)
  static const int desktopOAuthPort = 9728;

  // ============================================================
  // App Information
  // ============================================================

  static const String appName = 'KioKuu';
  static const String appVersion = '1.0.0';

  // ============================================================
  // Feature Flags
  // ============================================================

  /// Enable Google Sign-In
  static const bool enableGoogleSignIn = true;

  /// Enable debug logging
  static const bool enableDebugLogs = true;
}
