import 'package:flutter/material.dart';
import '../services/api_service.dart';

class EditSongMetadataSheet extends StatefulWidget {
  final String songId;
  final String initialTitle;
  final String initialArtist;
  final String? initialAlbum;
  final VoidCallback? onMetadataUpdated;

  const EditSongMetadataSheet({
    super.key,
    required this.songId,
    required this.initialTitle,
    required this.initialArtist,
    this.initialAlbum,
    this.onMetadataUpdated,
  });

  @override
  State<EditSongMetadataSheet> createState() => _EditSongMetadataSheetState();
}

class _EditSongMetadataSheetState extends State<EditSongMetadataSheet> {
  late TextEditingController _titleController;
  late TextEditingController _artistController;
  late TextEditingController _albumController;
  bool _isLoading = false;
  String? _errorMessage;
  bool _editingEnabled = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _artistController = TextEditingController(text: widget.initialArtist);
    _albumController = TextEditingController(text: widget.initialAlbum ?? '');
    _checkIfEditable();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    super.dispose();
  }

  Future<void> _checkIfEditable() async {
    // In real implementation, you'd check if the song is unverified and has no external IDs
    // For now, assume it's editable (the backend will validate)
    setState(() => _editingEnabled = true);
  }

  Future<void> _saveMetadata() async {
    if (!_editingEnabled) {
      setState(
        () => _errorMessage =
            'Cannot edit metadata for verified or external songs',
      );
      return;
    }

    // Validate that at least title or artist is changed
    if (_titleController.text.isEmpty && _artistController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter at least a title or artist');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final (success, message, metadata) = await ApiService().editSongMetadata(
      widget.songId,
      title: _titleController.text,
      artistName: _artistController.text,
      albumName: _albumController.text,
    );

    if (!mounted) return;

    if (success) {
      setState(() => _errorMessage = null);
      widget.onMetadataUpdated?.call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: Colors.white,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
    } else {
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Update Song Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_editingEnabled)
                Text(
                  'Make it yours. Updates will be visible to everyone in the family.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 14),
                ),

              const SizedBox(height: 32),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              if (!_editingEnabled)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        color: Colors.white54,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'This song has been verified and cannot be edited.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),

              // Title Field
              _buildFriendlyTextField(
                controller: _titleController,
                label: 'Song Title',
                hint: 'What\'s this track called?',
                icon: Icons.music_note_rounded,
                enabled: _editingEnabled && !_isLoading,
              ),
              const SizedBox(height: 16),

              // Artist Field
              _buildFriendlyTextField(
                controller: _artistController,
                label: 'Artist',
                hint: 'Who performed this masterpiece?',
                icon: Icons.person_rounded,
                enabled: _editingEnabled && !_isLoading,
              ),
              const SizedBox(height: 16),

              // Album Field
              _buildFriendlyTextField(
                controller: _albumController,
                label: 'Album',
                hint: 'Which album is it from? (Optional)',
                icon: Icons.album_rounded,
                enabled: _editingEnabled && !_isLoading,
              ),

              const SizedBox(height: 32),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_isLoading || !_editingEnabled)
                          ? null
                          : _saveMetadata,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: Colors.grey[900],
                        disabledForegroundColor: Colors.grey[700],
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.black,
                                ),
                              ),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendlyTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[700]),
            prefixIcon: Icon(icon, color: Colors.grey[600], size: 20),
            filled: true,
            fillColor: Colors.grey[900],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.white, width: 1),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }
}
