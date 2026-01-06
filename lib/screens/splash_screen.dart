import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/shader_warmup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../services/import_folder_service.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'permission_screen.dart';
import 'force_update_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  // Shader warmup state (Windows only)
  bool _isWarmingUpShaders = false;
  double _warmupProgress = 0.0;
  String _warmupStatus = '';

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

    // Start initialization sequence
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Wait for fade-in animation to complete
    await Future.delayed(const Duration(milliseconds: 1500));

    // On Windows, perform shader warmup first
    if (!kIsWeb &&
        Platform.isWindows &&
        !ShaderWarmupService.instance.isWarmedUp) {
      if (mounted) {
        setState(() {
          _isWarmingUpShaders = true;
          _warmupStatus = 'Preparing graphics engine...';
        });
      }

      await ShaderWarmupService.instance.warmUp(
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _warmupProgress = progress;
            });
          }
        },
        onStatusChange: (status) {
          if (mounted) {
            setState(() {
              _warmupStatus = status;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isWarmingUpShaders = false;
        });
      }

      // Brief pause to show "Ready!"
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Proceed with permissions and auth check
    if (mounted) {
      _checkPermissionsAndAuth();
    }
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

    if (!mounted) return;

    // Check for updates (uses GitHub, works even when backend is offline)
    final updateInfo = await UpdateService().checkForUpdate(force: true);

    if (updateInfo != null && mounted) {
      if (updateInfo.isForced) {
        // Critical update required - block the app
        print(
          '[SplashScreen] Forced update required: ${updateInfo.latestVersion}',
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ForceUpdateScreen(updateInfo: updateInfo),
          ),
        );
        return;
      } else {
        // Optional update available - show dialog after navigation
        _pendingUpdateInfo = updateInfo;
      }
    }

    if (mounted) {
      if (isValidSession) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomeScreen(isOfflineMode: isOfflineMode),
          ),
        );

        // Show optional update dialog after a short delay
        if (_pendingUpdateInfo != null) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && _pendingUpdateInfo != null) {
              _showOptionalUpdateDialog(_pendingUpdateInfo!);
            }
          });
        }
      } else {
        // Token invalid or missing - go to auth screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
        );
      }
    }
  }

  UpdateInfo? _pendingUpdateInfo;

  void _showOptionalUpdateDialog(UpdateInfo updateInfo) {
    final ctx = Navigator.of(context).context;
    UpdateDialog.show(ctx, updateInfo);
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
              // Show shader warmup progress on Windows, otherwise show tagline
              if (_isWarmingUpShaders) ...[
                const SizedBox(height: 20),
                // Progress bar container
                Container(
                  width: 200,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 200 * _warmupProgress,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Status text
                Text(
                  _warmupStatus,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ] else
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
