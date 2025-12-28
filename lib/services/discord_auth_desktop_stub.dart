/// Stub for web platform
bool isDesktopPlatform() => false;
int get localPort => 9728;
Future<Map<String, dynamic>> waitForOAuthCallback() async => {
  'error': 'Not supported on web',
};
