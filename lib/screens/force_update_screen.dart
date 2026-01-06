import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../widgets/custom_title_bar.dart';

/// A blocking screen shown when a forced update is required.
class ForceUpdateScreen extends StatelessWidget {
  final UpdateInfo updateInfo;

  const ForceUpdateScreen({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

    final content = Stack(
      children: [
        // Subtle radial glow behind content
        Positioned.fill(
          child: Center(
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [Colors.white.withAlpha(6), Colors.transparent],
                ),
              ),
            ),
          ),
        ),

        // Main content
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                // Push content down slightly to account for title bar
                const Spacer(flex: 3),

                // App logo with filled background
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/images/kiokuu_white.svg',
                      width: 40,
                      height: 40,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Title
                Text(
                  'Update Required',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 10),

                // Version chip
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'v${updateInfo.currentVersion}  →  v${updateInfo.minimumVersion}',
                    style: GoogleFonts.inter(
                      color: Colors.grey[500],
                      fontSize: 13,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Subtitle
                Text(
                  'A new version is available with\nimportant improvements',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.grey[600],
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 40),

                // Update button
                ElevatedButton(
                  onPressed: () => _openDownloadLink(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Update Now',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Release notes link
                TextButton(
                  onPressed: () => _openChangelog(context),
                  child: Text(
                    'View changelog',
                    style: GoogleFonts.inter(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ),

                // Bottom spacer to balance the content
                const Spacer(flex: 4),
              ],
            ),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: isDesktop
            ? Column(
                children: [
                  const CustomTitleBar(height: 40, showTitle: true),
                  Expanded(child: content),
                ],
              )
            : content,
      ),
    );
  }

  Future<void> _openDownloadLink(BuildContext context) async {
    final url = updateInfo.downloadUrl ?? updateInfo.changelogUrl;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to open download link: $e');
    }
  }

  Future<void> _openChangelog(BuildContext context) async {
    try {
      final uri = Uri.parse(updateInfo.changelogUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to open changelog: $e');
    }
  }
}
