import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';

/// A beautiful AMOLED-themed permission request screen.
/// Shows on first launch on devices that require storage/notification permissions.
class PermissionScreen extends StatefulWidget {
  final void Function(BuildContext context) onComplete;

  const PermissionScreen({super.key, required this.onComplete});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();

  /// Check if we need to show the permission screen
  static Future<bool> needsPermissions() async {
    // Web doesn't need mobile permissions
    if (kIsWeb) return false;

    if (!Platform.isAndroid && !Platform.isIOS) {
      return false; // Desktop platforms don't need this
    }

    // Check if we already have all permissions
    final hasNotification = await Permission.notification.isGranted;
    final hasStorage = await _hasStoragePermission();

    // Note: Folder access for auto-import is optional and can be set in Settings
    // Offline storage uses app-specific folder which doesn't need SAF
    return !hasNotification || !hasStorage;
  }

  /// Check if we have media audio permissions (for MediaStore access)
  /// Note: We use SAF (Storage Access Framework) for folder access,
  /// which doesn't require MANAGE_EXTERNAL_STORAGE
  static Future<bool> _hasStoragePermission() async {
    if (kIsWeb) return true; // Web handles storage differently

    if (Platform.isAndroid) {
      // For Android 13+, check audio permission (READ_MEDIA_AUDIO)
      // For older Android, check storage permission
      if (await Permission.audio.isGranted) return true;
      if (await Permission.storage.isGranted) return true;
      // SAF folder access doesn't require permissions, so this is optional
      return false;
    }
    return true; // iOS handles storage differently
  }
}

class _PermissionScreenState extends State<PermissionScreen> {
  // Theme color matching auth screen
  static const _primaryColor = Color(0xFF4F6BF6);

  bool _notificationGranted = false;
  bool _storageGranted = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentPermissions();
  }

  Future<void> _checkCurrentPermissions() async {
    final notification = await Permission.notification.isGranted;
    final storage = await PermissionScreen._hasStoragePermission();
    setState(() {
      _notificationGranted = notification;
      _storageGranted = storage;
    });
  }

  Future<void> _requestNotificationPermission() async {
    setState(() => _isLoading = true);
    final status = await Permission.notification.request();
    setState(() {
      _notificationGranted = status.isGranted;
      _isLoading = false;
    });
  }

  Future<void> _requestStoragePermission() async {
    setState(() => _isLoading = true);

    if (!kIsWeb && Platform.isAndroid) {
      // For Android 13+ (API 33+), request audio permission (READ_MEDIA_AUDIO)
      var status = await Permission.audio.request();
      if (status.isGranted) {
        setState(() {
          _storageGranted = true;
          _isLoading = false;
        });
        return;
      }

      // For older Android (API < 33), request storage permission
      status = await Permission.storage.request();
      setState(() {
        _storageGranted = status.isGranted;
        _isLoading = false;
      });
    } else {
      // Non-Android platforms
      setState(() {
        _storageGranted = true;
        _isLoading = false;
      });
    }
  }

  void _continue() {
    widget.onComplete(context);
  }

  void _skip() {
    widget.onComplete(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Skip button at top right
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Title
              Text(
                'Get Started',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Grant permissions to enable all features.',
                style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 15),
              ),

              const SizedBox(height: 32),

              // Info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _primaryColor.withAlpha(60),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _primaryColor.withAlpha(40),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.security_outlined,
                        color: _primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SECURE & PRIVATE',
                            style: GoogleFonts.inter(
                              color: _primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your data stays on your device. We only access what you allow.',
                            style: GoogleFonts.inter(
                              color: Colors.grey[400],
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Permissions label
              Text(
                'Permissions',
                style: GoogleFonts.inter(
                  color: Colors.grey[500],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 16),

              // Permission cards
              _buildPermissionCard(
                icon: Icons.notifications_outlined,
                iconColor: const Color(0xFFFF6B6B),
                title: 'Notifications',
                description: 'Playback controls & updates',
                isGranted: _notificationGranted,
                onTap: _requestNotificationPermission,
              ),

              const SizedBox(height: 12),

              _buildPermissionCard(
                icon: Icons.folder_outlined,
                iconColor: _primaryColor,
                title: 'Storage Access',
                description: 'Import music files',
                isGranted: _storageGranted,
                onTap: _requestStoragePermission,
              ),

              const Spacer(),

              // Continue button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Footer note
              Center(
                child: Text(
                  'You can change these later in Settings',
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required bool isGranted,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted
              ? _primaryColor.withAlpha(100)
              : Colors.white.withAlpha(10),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isGranted ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: GoogleFonts.inter(
                          color: Colors.grey[500],
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle / Check
                if (_isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _primaryColor,
                    ),
                  )
                else if (isGranted)
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: _primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  )
                else
                  Container(
                    width: 50,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(left: 2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
