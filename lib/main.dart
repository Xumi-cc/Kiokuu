import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'providers/music_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/shared_playlist_screen.dart';
import 'screens/home_screen.dart';
import 'services/audio_handler.dart';
import 'services/api_service.dart';
import 'services/import_folder_service.dart';
import 'services/extension_manager_service.dart';
import 'utils/snackbar_utils.dart';

// Global navigator key for navigation from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global deep link handler
late AppLinks _appLinks;
String? _pendingShareToken;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style - show status bar with light icons
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Ensure system overlays are visible
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: SystemUiOverlay.values,
  );

  // Initialize MediaKit
  MediaKit.ensureInitialized();

  // Initialize window manager for desktop platforms
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.black,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // Frameless window
      title: 'KioKuu',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Initialize import folder (creates ~/KioKuu and adds to system bookmarks)
  await ImportFolderService.instance.initialize();

  // Initialize extension manager (checks for installed AI extensions)
  await ExtensionManagerService.instance.initialize();

  // Create player first
  final player = Player();

  // Try to initialize audio service
  MediaKitAudioHandler? audioHandler;
  try {
    audioHandler = await initAudioService(player);
    debugPrint('✅ Audio service initialized successfully');
  } catch (e) {
    debugPrint('⚠️ Audio service initialization failed: $e');
    debugPrint('App will continue without background audio support');
  }

  // Set up session expiration handler
  ApiService.onSessionExpired = () {
    debugPrint('🔒 Session expired - logging out...');
    // Use post frame callback to avoid navigation during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentState?.mounted == true) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthScreen()),
          (route) => false,
        );
      }
    });
  };

  // Initialize deep linking
  _appLinks = AppLinks();

  // Check if app was opened via deep link
  try {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _pendingShareToken = _extractShareToken(initialUri);
      debugPrint('🔗 App opened via deep link: $initialUri');
    }
  } catch (e) {
    debugPrint('⚠️ Failed to get initial deep link: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => MusicProvider(player, audioHandler),
      child: const KioKuuApp(),
    ),
  );
}

/// Extract share token from deep link URI
String? _extractShareToken(Uri uri) {
  // Handle musiccloud://share/TOKEN
  if (uri.scheme == 'musiccloud' &&
      uri.host == 'share' &&
      uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  // Handle musiccloud://share/TOKEN (path style)
  if (uri.scheme == 'musiccloud' && uri.path.startsWith('/share/')) {
    return uri.path.replaceFirst('/share/', '');
  }
  // Handle https://mcloud.xumi.cc/s/TOKEN
  if (uri.host == 'mcloud.xumi.cc' && uri.path.startsWith('/s/')) {
    return uri.path.replaceFirst('/s/', '');
  }
  return null;
}

class KioKuuApp extends StatefulWidget {
  const KioKuuApp({super.key});

  @override
  State<KioKuuApp> createState() => _KioKuuAppState();
}

class _KioKuuAppState extends State<KioKuuApp> {
  @override
  void initState() {
    super.initState();

    // Listen for incoming deep links while app is running
    _appLinks.uriLinkStream.listen((Uri uri) {
      debugPrint('🔗 Deep link received: $uri');

      // Check for Discord auth callback
      if (_isDiscordAuthCallback(uri)) {
        _handleDiscordAuthCallback(uri);
        return;
      }

      final token = _extractShareToken(uri);
      if (token != null) {
        _handleShareToken(token);
      }
    });

    // Handle pending share token after app is initialized
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Set up subscription required callback for MusicProvider
      final musicProvider = Provider.of<MusicProvider>(context, listen: false);
      debugPrint(
        '🔧 Setting up onSubscriptionRequired callback on MusicProvider',
      );
      musicProvider.onSubscriptionRequired = (message) {
        debugPrint('📞 onSubscriptionRequired callback invoked with: $message');
        _showSubscriptionRequiredSnackbar(message);
      };

      if (_pendingShareToken != null) {
        // Delay to ensure user is authenticated
        Future.delayed(const Duration(seconds: 2), () {
          if (_pendingShareToken != null) {
            _handleShareToken(_pendingShareToken!);
            _pendingShareToken = null;
          }
        });
      }
    });
  }

  void _showSubscriptionRequiredSnackbar(String message) {
    debugPrint('🔔 Showing subscription snackbar: $message');

    // Try to get context from navigator
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      debugPrint('❌ Navigator context is null');
      return;
    }

    AppSnackbar.subscriptionRequired(
      ctx,
      message: message,
      onSubscribe: () {
        // Navigate to subscription settings
        navigatorKey.currentState?.pushNamed(
          '/settings',
          arguments: 'subscription',
        );
      },
    );
  }

  void _handleShareToken(String token) {
    debugPrint('🎵 Opening shared playlist: $token');

    // Navigate to shared playlist screen
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => SharedPlaylistScreen(shareToken: token),
      ),
    );
  }

  bool _isDiscordAuthCallback(Uri uri) {
    // Check for kiokuu://auth/discord/callback
    return uri.scheme == 'kiokuu' &&
        (uri.host == 'auth' || uri.path.contains('auth/discord/callback'));
  }

  Future<void> _handleDiscordAuthCallback(Uri uri) async {
    debugPrint('🔐 Discord auth callback: $uri');

    final token = uri.queryParameters['token'];
    final userId = uri.queryParameters['user_id'];
    final username = uri.queryParameters['username'];
    final photoUrl = uri.queryParameters['photo_url'];
    final error = uri.queryParameters['error'];

    if (error != null && error.isNotEmpty) {
      debugPrint('❌ Discord auth error: $error');
      AppSnackbar.error(
        navigatorKey.currentContext!,
        'Discord login failed: $error',
      );
      return;
    }

    if (token != null && userId != null) {
      // Save credentials
      const storage = FlutterSecureStorage();
      await storage.write(key: 'auth_token', value: token);
      await storage.write(key: 'user_id', value: userId);
      if (username != null) {
        await storage.write(key: 'username', value: username);
      }
      if (photoUrl != null) {
        await storage.write(key: 'photo_url', value: photoUrl);
      }

      debugPrint('✅ Discord login successful, navigating to home');

      // Navigate to home screen
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } else {
      debugPrint('❌ Discord auth missing token or user_id');
      AppSnackbar.error(
        navigatorKey.currentContext!,
        'Discord login failed: Invalid response',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'KioKuu',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
          primary: Colors.white,
          secondary: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Colors.white,
          contentTextStyle: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w500,
          ),
          actionTextColor: Colors.black,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      home: const SplashScreen(),
    );
  }
}
