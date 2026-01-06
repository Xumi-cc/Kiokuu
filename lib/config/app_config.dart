/// Centralized app configuration
/// Keep all environment-specific values here for easy management
class AppConfig {
  // ============================================================
  // API Configuration
  // ============================================================

  /// Backend API base URL
  static const String apiBaseUrl = 'https://api.kiokuu.app';

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
  // Download URLs (App Store Links / GitHub Releases)
  // ============================================================

  /// GitHub repository info
  static const String githubOwner = 'Xumi-cc';
  static const String githubRepo = 'Kiokuu';
  static const String githubReleasesUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

  /// Android download URL (GitHub Releases)
  static const String androidDownloadUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

  /// iOS download URL (App Store - placeholder)
  static const String iosDownloadUrl =
      'https://apps.apple.com/app/kiokuu/id000000000';

  /// Windows download URL
  static const String windowsDownloadUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

  /// macOS download URL
  static const String macosDownloadUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

  /// Linux download URL
  static const String linuxDownloadUrl =
      'https://github.com/$githubOwner/$githubRepo/releases/latest';

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
  static const String appVersion = '0.9.2';

  // ============================================================
  // Feature Flags
  // ============================================================

  /// Enable Google Sign-In
  static const bool enableGoogleSignIn = true;

  /// Enable debug logging
  static const bool enableDebugLogs = true;

  // ============================================================
  // Social / Support Links
  // ============================================================

  /// Discord invite URL
  static const String discordInviteUrl = 'https://discord.gg/geHykXBUcz';

  /// Support email
  static const String supportEmail = 'support@kiokuu.app';

  /// Website URL
  static const String websiteUrl = 'https://kiokuu.app';
}
