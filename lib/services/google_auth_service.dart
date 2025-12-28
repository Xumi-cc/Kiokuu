import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

// Conditional imports for desktop-only features
import 'google_auth_desktop_stub.dart'
    if (dart.library.io) 'google_auth_desktop.dart' as desktop;

/// Handles Google OAuth authentication for all platforms.
/// - Mobile/Web: Uses google_sign_in package
/// - Desktop: Opens browser for OAuth and receives callback via local HTTP server
class GoogleAuthService {
  final _storage = const FlutterSecureStorage();
  
  // For mobile/web
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: AppConfig.googleWebClientId,
  );
  
  /// Check if we're running on a desktop platform
  bool get isDesktop => desktop.isDesktopPlatform();
  
  /// Sign in with Google - automatically uses the right method for the platform
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
  
  /// Mobile/Web sign-in using google_sign_in package
  Future<Map<String, dynamic>> _signInMobile() async {
    try {
      print('=== GoogleAuth: Starting sign in ===');
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        print('=== GoogleAuth: User cancelled ===');
        return {'success': false, 'error': 'Sign in cancelled'};
      }

      print('=== GoogleAuth: Got user: ${googleUser.email} ===');
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      if (googleAuth.idToken == null) {
        print('=== GoogleAuth: No ID token! ===');
        return {'success': false, 'error': 'Failed to get ID token'};
      }

      print('=== GoogleAuth: Got ID token, sending to backend... ===');
      // Send the ID token to our backend
      final result = await _sendToBackend(
        idToken: googleAuth.idToken!,
        email: googleUser.email,
        displayName: googleUser.displayName ?? googleUser.email.split('@')[0],
        photoUrl: googleUser.photoUrl,
      );
      print('=== GoogleAuth: Backend result: $result ===');
      return result;
    } catch (e) {
      print('=== GoogleAuth: Exception: $e ===');
      return {'success': false, 'error': _parseGoogleSignInError(e)};
    }
  }
  
  /// Parse Google Sign-In errors into user-friendly messages
  String _parseGoogleSignInError(dynamic error) {
    final errorString = error.toString();
    
    // ApiException error codes from Google Play Services
    if (errorString.contains('ApiException: 10')) {
      return 'Google Sign-In is not configured for this app. Please contact the developer.';
    } else if (errorString.contains('ApiException: 7')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('ApiException: 12500')) {
      return 'Google Sign-In failed. Please update Google Play Services.';
    } else if (errorString.contains('ApiException: 12501')) {
      return 'Sign in cancelled';
    } else if (errorString.contains('ApiException: 12502')) {
      return 'Sign in is already in progress';
    } else if (errorString.contains('sign_in_canceled')) {
      return 'Sign in cancelled';
    } else if (errorString.contains('network_error')) {
      return 'Network error. Please check your internet connection.';
    }
    
    // Return a cleaned version of the error
    return 'Google Sign-In failed. Please try again.';
  }
  
  /// Desktop sign-in using browser OAuth flow
  Future<Map<String, dynamic>> _signInDesktop() async {
    try {
      // Open browser for OAuth
      final authUrl = Uri.parse('${AppConfig.apiBaseUrl}/auth/google/login?redirect_port=${desktop.localPort}');
      
      if (!await launchUrl(authUrl, mode: LaunchMode.externalApplication)) {
        return {'success': false, 'error': 'Could not open browser for authentication'};
      }
      
      // Start local server and wait for callback
      final result = await desktop.waitForOAuthCallback();
      
      if (result.containsKey('error')) {
        return {'success': false, 'error': result['error']};
      }
      
      if (result.containsKey('token') && result.containsKey('user_id')) {
        // Store credentials
        await _storage.write(key: 'auth_token', value: result['token']);
        await _storage.write(key: 'user_id', value: result['user_id']);
        // Store user info
        if (result['username'] != null) {
          await _storage.write(key: 'username', value: result['username']);
        }
        if (result['photo_url'] != null) {
          await _storage.write(key: 'photo_url', value: result['photo_url']);
        }
        return {'success': true};
      }
      
      return {'success': false, 'error': 'Invalid response from server'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
  
  /// Send OAuth data to backend
  Future<Map<String, dynamic>> _sendToBackend({
    required String idToken,
    required String email,
    required String displayName,
    String? photoUrl,
  }) async {
    try {
      print('=== Backend: Calling ${AppConfig.apiBaseUrl}/auth/google ===');
      final response = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': idToken,
          'email': email,
          'display_name': displayName,
          'photo_url': photoUrl,
        }),
      );

      print('=== Backend: Status ${response.statusCode}, Body: ${response.body} ===');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _storage.write(key: 'auth_token', value: data['token']);
        await _storage.write(key: 'user_id', value: data['user_id']);
        // Store user info
        if (data['username'] != null) {
          await _storage.write(key: 'username', value: data['username']);
        }
        if (data['photo_url'] != null) {
          await _storage.write(key: 'photo_url', value: data['photo_url']);
        }
        return {'success': true};
      } else {
        // Handle Cloudflare and server errors
        return {'success': false, 'error': _parseServerError(response.statusCode, response.body)};
      }
    } catch (e) {
      print('=== Backend: Exception: $e ===');
      return {'success': false, 'error': _parseConnectionError(e)};
    }
  }
  
  /// Parse server errors into user-friendly messages
  String _parseServerError(int statusCode, String body) {
    // Cloudflare errors (52x, 1xxx)
    if (body.contains('error code: 1') || statusCode >= 520) {
      return 'Server is currently offline. Please try again later.';
    }
    
    // Server errors
    if (statusCode >= 500) {
      return 'Server error. Please try again later.';
    }
    
    // Try to parse JSON error
    try {
      final error = jsonDecode(body);
      return error['error'] ?? 'Authentication failed';
    } catch (_) {
      return 'Server error ($statusCode). Please try again.';
    }
  }
  
  /// Parse connection errors into user-friendly messages
  String _parseConnectionError(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('socketexception') || 
        errorString.contains('connection refused') ||
        errorString.contains('network is unreachable')) {
      return 'Cannot connect to server. Check your internet connection.';
    }
    
    if (errorString.contains('timeout')) {
      return 'Connection timed out. Please try again.';
    }
    
    if (errorString.contains('handshake') || errorString.contains('certificate')) {
      return 'Secure connection failed. Please try again.';
    }
    
    return 'Connection failed. Please check your internet.';
  }
  
  /// Sign out from Google (clears local state)
  Future<void> signOut() async {
    if (!isDesktop) {
      await _googleSignIn.signOut();
    }
  }
}
