import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../services/import_folder_service.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'permission_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    print('=== SplashScreen: initState called ===');

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    // Check Auth after animation
    Timer(const Duration(seconds: 2), _checkPermissionsAndAuth);
  }

  Future<void> _checkPermissionsAndAuth() async {
    // Check if we need to show permission screen (only on mobile)
    final needsPermissions = await PermissionScreen.needsPermissions();

    if (needsPermissions && mounted) {
      // Show permission screen first - it will navigate to auth check when done
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PermissionScreen(
            onComplete: (permissionContext) async {
              // Reinitialize import folder now that we have permission
              await ImportFolderService.instance.initialize();

              // Navigate using the context from PermissionScreen
              if (permissionContext.mounted) {
                Navigator.of(permissionContext).pushReplacement(
                  MaterialPageRoute(builder: (_) => const _AuthCheckScreen()),
                );
              }
            },
          ),
        ),
      );
    } else {
      // Permissions already granted or desktop - proceed with auth
      _checkAuthAndNavigate();
    }
  }

  Future<void> _checkAuthAndNavigate() async {
    final storage = const FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    final token = await storage.read(key: 'auth_token');

    print('=== SplashScreen: Token found: ${token != null} ===');

    bool isValidSession = false;
    bool isOfflineMode = false;

    if (token != null) {
      // Try to validate with backend first
      final apiService = ApiService();
      isValidSession = await apiService.validateSession();
      print('=== SplashScreen: Session valid: $isValidSession ===');

      if (isValidSession) {
        // Online and valid - clear offline mode flag
        await prefs.setBool('offline_mode', false);
      } else {
        // Backend validation failed (server down, no internet, or expired token on server)
        // Token exists = user logged in before, allow offline access
        isValidSession = true;
        isOfflineMode = true;
        await prefs.setBool('offline_mode', true);
        print('=== SplashScreen: Backend unreachable - using offline mode ===');
      }
    }

    if (mounted) {
      if (isValidSession) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(isOfflineMode: isOfflineMode),
          ),
        );
      } else {
        // Token invalid or missing - go to auth screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // KioKuu Logo (white, no background)
              SvgPicture.asset(
                'assets/images/kiokuu_white.svg',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 30),
              // App Name
              Text(
                'KioKuu',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your music, everywhere',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Internal screen to check auth after permissions are granted
class _AuthCheckScreen extends StatefulWidget {
  const _AuthCheckScreen();

  @override
  State<_AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<_AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    final storage = const FlutterSecureStorage();
    final prefs = await SharedPreferences.getInstance();
    final token = await storage.read(key: 'auth_token');

    bool isValidSession = false;
    bool isOfflineMode = false;

    if (token != null) {
      final apiService = ApiService();
      isValidSession = await apiService.validateSession();

      if (isValidSession) {
        await prefs.setBool('offline_mode', false);
      } else {
        isValidSession = true;
        isOfflineMode = true;
        await prefs.setBool('offline_mode', true);
      }
    }

    if (mounted) {
      if (isValidSession) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(isOfflineMode: isOfflineMode),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(child: CircularProgressIndicator(color: Color(0xFF1DB954))),
    );
  }
}
