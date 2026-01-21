import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../providers/music_provider.dart';
import 'dark_dropdown_menu.dart';

class PlaylistSongActionsMenu {
  static Future<void> show(
    BuildContext context, {
    required String songId,
    required String songTitle,
    required String? uploadedBy,
    required String? currentUserId,
    required VoidCallback onSongDeleted,
    required Offset? menuPosition,
  }) async {
    final options = <DropdownMenuOption>[];

    // Add to queue option
    options.add(
      DropdownMenuOption(
        label: 'Add to Queue',
        icon: Icons.queue_music,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Added to queue'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      ),
    );

    // Only show delete if user is the uploader
    if (uploadedBy != null &&
        currentUserId != null &&
        uploadedBy == currentUserId) {
      options.add(
        DropdownMenuOption(
          label: 'Delete Song',
          icon: Icons.delete_outline,
          color: Colors.red.shade400,
          onTap: () => _showDeleteConfirmation(
            context,
            songId: songId,
            songTitle: songTitle,
            onDeleted: onSongDeleted,
          ),
        ),
      );
    }

    if (options.isNotEmpty) {
      await showDarkDropdownMenu(
        context,
        options: options,
        position: menuPosition,
      );
    }
  }

  static Future<void> _showDeleteConfirmation(
    BuildContext context, {
    required String songId,
    required String songTitle,
    required VoidCallback onDeleted,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white12, width: 0.5),
        ),
        title: Text(
          'Delete Song?',
          style: Theme.of(
            dialogContext,
          ).textTheme.titleLarge?.copyWith(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete "$songTitle"? This cannot be undone.',
          style: Theme.of(
            dialogContext,
          ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSong(context, songId, onDeleted);
    }
  }

  static Future<void> _deleteSong(
    BuildContext context,
    String songId,
    VoidCallback onDeleted,
  ) async {
    try {
      final response = await ApiService().deleteSong(songId);
      if (response.$1) {
        // Also remove from playback queue if present
        if (context.mounted) {
          Provider.of<MusicProvider>(
            context,
            listen: false,
          ).removeSongById(songId);

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Song deleted successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
        onDeleted();
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.$2),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting song: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
