import 'dart:async';
import 'package:dart_discord_presence/dart_discord_presence.dart';

/// Discord RPC implementation for desktop platforms (Windows, Linux, macOS)

// KioKuu Discord Application ID
// Created at https://discord.com/developers/applications
const String _applicationId = '1454011409619751023';

DiscordRPC? _rpc;
bool _isConnected = false;
final _connectionController = StreamController<bool>.broadcast();
Stream<bool> get connectionStateStream => _connectionController.stream;

Future<void> connect() async {
  if (_rpc != null) return;

  _rpc = DiscordRPC();

  // Listen for connection events
  _rpc!.onReady.listen((event) {
    _isConnected = true;
    _connectionController.add(true);
  });

  _rpc!.onDisconnected.listen((_) {
    _isConnected = false;
    _connectionController.add(false);
  });

  try {
    await _rpc!.initialize(_applicationId);
    _isConnected = true;
  } catch (e) {
    // Discord not running or other error - clean up and rethrow
    _isConnected = false;
    _rpc = null;
    rethrow;
  }
}

Future<void> disconnect() async {
  if (_rpc == null) return;
  await _rpc!.dispose();
  _rpc = null;
  _isConnected = false;
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
  if (_rpc == null || !_isConnected) return;

  try {
    await _rpc!.setPresence(
      DiscordPresence(
        type: DiscordActivityType.listening,
        details: details,
        state: state,
        largeAsset: largeImageKey != null
            ? DiscordAsset(key: largeImageKey, text: largeImageText)
            : null,
        smallAsset: smallImageKey != null
            ? DiscordAsset(key: smallImageKey, text: smallImageText)
            : null,
        timestamps: startTimestamp != null || endTimestamp != null
            ? DiscordTimestamps(start: startTimestamp, end: endTimestamp)
            : null,
      ),
    );
  } catch (e) {
    // Silently fail if presence update fails
  }
}

Future<void> clearActivity() async {
  if (_rpc == null) return;
  try {
    await _rpc!.clearPresence();
  } catch (e) {
    // Silently fail
  }
}

void dispose() {
  _rpc?.dispose();
  _rpc = null;
  _isConnected = false;
}
