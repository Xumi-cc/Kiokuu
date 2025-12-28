import 'dart:async';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import 'discord_auth_desktop_stub.dart'
    if (dart.library.io) 'discord_auth_desktop.dart'
    as desktop;

/// Discord OAuth service for all platforms
class DiscordAuthService {
  final _storage = const FlutterSecureStorage();

  bool get isDesktop => desktop.isDesktopPlatform();

  Future<Map<String, dynamic>> signIn() async {
    try {
      if (isDesktop) {
        return await _signInDesktop();
      } else {
        return await _signInMobile();
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _signInMobile() async {
    final authUrl = Uri.parse(
      '${AppConfig.apiBaseUrl}/auth/discord/login?redirect_uri=${Uri.encodeComponent(_getMobileRedirectUri())}',
    );

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      return {'success': false, 'error': 'Could not open browser'};
    }

    return {
      'success': false,
      'pending': true,
      'error': 'Complete sign-in in browser...',
    };
  }

  Future<Map<String, dynamic>> _signInDesktop() async {
    final authUrl = Uri.parse(
      '${AppConfig.apiBaseUrl}/auth/discord/login?redirect_port=${desktop.localPort}',
    );

    if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
      return {'success': false, 'error': 'Could not open browser'};
    }

    final result = await desktop.waitForOAuthCallback();

    if (result.containsKey('error')) {
      return {'success': false, 'error': result['error']};
    }

    if (result.containsKey('token') && result.containsKey('user_id')) {
      await _storage.write(key: 'auth_token', value: result['token']);
      await _storage.write(key: 'user_id', value: result['user_id']);
      if (result['username'] != null) {
        await _storage.write(key: 'username', value: result['username']);
      }
      if (result['photo_url'] != null) {
        await _storage.write(key: 'photo_url', value: result['photo_url']);
      }
      return {'success': true};
    }

    return {'success': false, 'error': 'Invalid response'};
  }

  Future<Map<String, dynamic>> handleCallback(
    String code, {
    String? redirectUri,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/discord'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'redirect_uri': redirectUri ?? _getMobileRedirectUri(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storage.write(key: 'auth_token', value: data['token']);
        await _storage.write(key: 'user_id', value: data['user_id']);
        if (data['username'] != null) {
          await _storage.write(key: 'username', value: data['username']);
        }
        if (data['photo_url'] != null) {
          await _storage.write(key: 'photo_url', value: data['photo_url']);
        }
        return {'success': true};
      }
      return {
        'success': false,
        'error': 'Auth failed (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  String _getMobileRedirectUri() =>
      '${AppConfig.urlScheme}://auth/discord/callback';

  Future<void> signOut() async {}
}
