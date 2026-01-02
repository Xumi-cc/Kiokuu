import 'dart:async';

/// Stub implementation for platforms that don't support Discord RPC
/// This file is used on web and mobile platforms

Stream<bool> get connectionStateStream => const Stream.empty();

Future<void> connect() async {
  // No-op on unsupported platforms
}

Future<void> disconnect() async {
  // No-op on unsupported platforms
}

Future<void> setActivity({
  required String details,
  required String state,
  String? largeImageKey,
  String? largeImageText,
  String? smallImageKey,
  String? smallImageText,
  int? startTimestamp,
  int? endTimestamp,
}) async {
  // No-op on unsupported platforms
}

Future<void> clearActivity() async {
  // No-op on unsupported platforms
}
