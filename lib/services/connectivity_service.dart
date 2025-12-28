import 'dart:io';
import 'dart:async';

/// Simple connectivity checker without external dependencies
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  /// Check if device has internet connectivity by attempting to reach a known host
  Future<bool> hasInternetConnection() async {
    try {
      // Try multiple reliable hosts for better accuracy
      final hosts = [
        'google.com',
        'cloudflare.com', 
        '8.8.8.8', // Google DNS
      ];
      
      for (final host in hosts) {
        try {
          final result = await InternetAddress.lookup(host)
              .timeout(const Duration(seconds: 3));
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            return true;
          }
        } catch (_) {
          // Try next host
          continue;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Quick check - just try one host (faster but less reliable)
  Future<bool> quickCheck() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
