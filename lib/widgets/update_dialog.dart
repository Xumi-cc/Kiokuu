import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';

/// Dialog shown when an optional update is available.
/// Simple, centered design.
class UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;
  final VoidCallback? onDismiss;

  const UpdateDialog({super.key, required this.updateInfo, this.onDismiss});

  /// Show the update dialog
  static Future<void> show(BuildContext context, UpdateInfo updateInfo) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => UpdateDialog(
        updateInfo: updateInfo,
        onDismiss: () {
          UpdateService().dismissUpdate(updateInfo.latestVersion);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App logo
            SvgPicture.asset(
              'assets/images/kiokuu_white.svg',
              width: 56,
              height: 56,
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              'Update Available',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            // Version info
            Text(
              'v${updateInfo.currentVersion} → v${updateInfo.latestVersion}',
              style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 14),
            ),

            if (updateInfo.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                updateInfo.releaseNotes,
                style: GoogleFonts.inter(
                  color: Colors.grey[600],
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 28),

            // Update button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _openDownloadLink(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
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
            ),

            const SizedBox(height: 12),

            // Later button
            TextButton(
              onPressed: onDismiss ?? () => Navigator.of(context).pop(),
              child: Text(
                'Maybe Later',
                style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
              ),
            ),
          ],
        ),
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
}
