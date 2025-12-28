/// Stub file for web - desktop features are not available
/// This file is used when dart:io is not available (web platform)

const int localPort = 9728;

bool isDesktopPlatform() => false;

Future<Map<String, String>> waitForOAuthCallback() async {
  return {'error': 'Desktop OAuth not available on this platform'};
}
