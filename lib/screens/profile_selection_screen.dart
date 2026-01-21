import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../models/profile.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

/// Netflix-style profile selection screen
class ProfileSelectionScreen extends StatefulWidget {
  final bool isInitialSelection;
  final VoidCallback? onProfileSelected;

  const ProfileSelectionScreen({
    super.key,
    this.isInitialSelection = false,
    this.onProfileSelected,
  });

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen>
    with TickerProviderStateMixin {
  final _apiService = ApiService();
  List<Profile> _profiles = [];
  String? _currentUserId;
  String? _ownerId;
  bool _isLoading = true;
  int? _selectedIndex;
  bool _isEditing = false;

  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _loadProfiles();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final result = await _apiService.getProfiles();
    if (result != null && mounted) {
      final profilesList =
          (result['profiles'] as List?)
              ?.map((p) => Profile.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [];

      setState(() {
        _profiles = profilesList;
        _currentUserId = result['current_user_id'] as String?;
        _ownerId = result['owner_id'] as String?;
        _isLoading = false;
      });
      _fadeController.forward();
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  bool get _isOwner => _currentUserId == _ownerId;
  bool get _canAddProfile => _profiles.length < 5 && _isOwner;

  void _selectProfile(int index) {
    if (_isEditing) {
      _showEditProfileDialog(_profiles[index]);
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _selectedIndex = index);

    // Animate selection then proceed
    final profile = _profiles[index];
    // Check if we need to switch (if selected profile is not current user)
    // _currentUserId might be null initially? No, getProfiles fills it.
    final needsSwitch = _currentUserId != null && profile.id != _currentUserId;

    Future.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted) return;

      if (needsSwitch) {
        // Perform the switch
        final result = await _apiService.switchProfile(profile.id);
        if (result == null) {
          if (mounted) {
            setState(() => _selectedIndex = null); // Reset selection
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to switch profile'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      if (mounted) {
        widget.onProfileSelected?.call();
        if (widget.isInitialSelection) {
          // Navigate to HomeScreen after initial profile selection
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else {
          Navigator.of(context).pop(profile);
        }
      }
    });
  }

  void _showEditProfileDialog(Profile profile) {
    final controller = TextEditingController(text: profile.username);
    String selectedColor = profile.color;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Edit Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Profile name',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              const Text(
                'Choose a color',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: Profile.colorMap.entries.map((e) {
                  final isSelected = e.key == selectedColor;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = e.key),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(e.value),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Color(e.value).withOpacity(0.5),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            if (profile.id != _ownerId) // Only show delete if not the owner
              TextButton(
                onPressed: () async {
                  Navigator.pop(context); // Close edit dialog

                  // Show confirmation dialog
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: Colors.grey[900],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: const Text(
                        'Delete Profile',
                        style: TextStyle(color: Colors.white),
                      ),
                      content: Text(
                        'Are you sure you want to delete "${profile.username}"?',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && mounted) {
                    setState(() => _isLoading = true);
                    final success = await _apiService.deleteProfile(profile.id);
                    if (success) {
                      _loadProfiles();
                    } else {
                      setState(() => _isLoading = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to delete profile'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                },
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context);
                setState(() => _isLoading = true);

                final success = await _apiService.updateProfile(
                  username: name,
                  color: selectedColor,
                );

                if (success) {
                  _loadProfiles();
                } else {
                  setState(() => _isLoading = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to update profile'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddProfileDialog() {
    final controller = TextEditingController();
    String selectedColor = 'blue';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Add Profile',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Profile name',
                  hintStyle: TextStyle(color: Colors.grey[500]),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 20),
              const Text(
                'Choose a color',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: Profile.colorMap.entries.map((e) {
                  final isSelected = e.key == selectedColor;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = e.key),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Color(e.value),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Color(e.value).withOpacity(0.5),
                                  blurRadius: 10,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                Navigator.pop(context);
                setState(() => _isLoading = true);

                final result = await _apiService.createProfile(
                  username: name,
                  color: selectedColor,
                );

                if (result != null && result['error'] == null) {
                  _loadProfiles();
                } else {
                  setState(() => _isLoading = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result?['error'] ?? 'Failed to create profile',
                        ),
                        backgroundColor: Colors.red[700],
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.grey[900]!, Colors.black],
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        const SizedBox(height: 60),

                        // Title
                        const Text(
                          "Who's listening?",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),

                        const SizedBox(height: 50),

                        // Profiles grid
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 30,
                                runSpacing: 30,
                                children: [
                                  // Existing profiles
                                  ..._profiles.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final profile = entry.value;
                                    return _ProfileTile(
                                      profile: profile,
                                      isSelected: _selectedIndex == index,
                                      isEditing: _isEditing,
                                      animationDelay: index * 100,
                                      onTap: () => _selectProfile(index),
                                    );
                                  }),

                                  // Add profile button
                                  if (_canAddProfile && !_isEditing)
                                    _AddProfileTile(
                                      onTap: _showAddProfileDialog,
                                      animationDelay: _profiles.length * 100,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Manage profiles button (for owner, not during initial selection)
                        if (_isOwner && !widget.isInitialSelection)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 40),
                            child: _isEditing
                                ? ElevatedButton(
                                    onPressed: () =>
                                        setState(() => _isEditing = false),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 32,
                                        vertical: 12,
                                      ),
                                    ),
                                    child: const Text(
                                      'Done',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : TextButton.icon(
                                    onPressed: () =>
                                        setState(() => _isEditing = true),
                                    icon: const Icon(Icons.edit, size: 18),
                                    label: const Text('Manage Profiles'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.grey[400],
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
          ),

          // Close button (if not initial selection)
          if (!widget.isInitialSelection)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatefulWidget {
  final Profile profile;
  final bool isSelected;
  final bool isEditing;
  final int animationDelay;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.profile,
    required this.isSelected,
    this.isEditing = false,
    required this.animationDelay,
    required this.onTap,
  });

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: widget.animationDelay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileColor = Color(widget.profile.colorValue);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacityAnimation.value,
        child: Transform.scale(
          scale:
              _scaleAnimation.value *
              (widget.isSelected ? 1.1 : (_isHovered ? 1.05 : 1.0)),
          child: child,
        ),
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Avatar
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: widget.isSelected || _isHovered
                        ? Colors.white
                        : Colors.transparent,
                    width: 3,
                  ),
                  boxShadow: widget.isSelected || _isHovered
                      ? [
                          BoxShadow(
                            color: profileColor.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child:
                          widget.profile.photoUrl != null &&
                              widget.profile.photoUrl!.isNotEmpty
                          ? SizedBox.expand(
                              child: Image.network(
                                widget.profile.photoUrl!,
                                key: ValueKey(widget.profile.photoUrl),
                                fit: BoxFit.cover,
                                cacheWidth: 256,
                                cacheHeight: 256,
                                errorBuilder: (_, __, ___) =>
                                    _buildAvatarPlaceholder(profileColor),
                              ),
                            )
                          : _buildAvatarPlaceholder(profileColor),
                    ),

                    // Loading Overlay (shown when profile is selected and switching)
                    if (widget.isSelected && !widget.isEditing)
                      Container(
                        color: Colors.black.withOpacity(0.6),
                        child: Center(
                          child: LoadingAnimationWidget.threeArchedCircle(
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),

                    // Edit Overlay (Netflix style dark overlay with pencil)
                    if (widget.isEditing)
                      Container(
                        color: Colors.black.withOpacity(0.5),
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Name
              Text(
                widget.profile.username,
                style: TextStyle(
                  color: _isHovered || widget.isSelected
                      ? Colors.white
                      : Colors.grey[400],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // Owner badge
              if (widget.profile.isOwner)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Owner',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withOpacity(0.7)],
        ),
      ),
      child: Center(
        child: Text(
          widget.profile.username.isNotEmpty
              ? widget.profile.username[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _AddProfileTile extends StatefulWidget {
  final VoidCallback onTap;
  final int animationDelay;

  const _AddProfileTile({required this.onTap, required this.animationDelay});

  @override
  State<_AddProfileTile> createState() => _AddProfileTileState();
}

class _AddProfileTileState extends State<_AddProfileTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: widget.animationDelay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _opacityAnimation.value,
        child: Transform.scale(scale: _isHovered ? 1.05 : 1.0, child: child),
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isHovered ? Colors.white : Colors.grey[700]!,
                    width: 2,
                  ),
                  color: Colors.grey[900],
                ),
                child: Icon(
                  Icons.add,
                  size: 50,
                  color: _isHovered ? Colors.white : Colors.grey[500],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Add Profile',
                style: TextStyle(
                  color: _isHovered ? Colors.white : Colors.grey[500],
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Screen for editing a profile's username, photo, and color
class _EditProfileScreen extends StatefulWidget {
  final Profile profile;
  final VoidCallback onProfileUpdated;
  final VoidCallback onProfileDeleted;

  const _EditProfileScreen({
    required this.profile,
    required this.onProfileUpdated,
    required this.onProfileDeleted,
  });

  @override
  State<_EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<_EditProfileScreen> {
  final _apiService = ApiService();
  final _usernameController = TextEditingController();
  final _picker = ImagePicker();

  String _selectedColor = 'blue';
  String? _photoUrl;
  bool _isSaving = false;
  bool _hasChanges = false;

  static const _colorOptions = [
    {'name': 'blue', 'color': Color(0xFF4A90D9)},
    {'name': 'purple', 'color': Color(0xFF9B59B6)},
    {'name': 'green', 'color': Color(0xFF27AE60)},
    {'name': 'orange', 'color': Color(0xFFE67E22)},
    {'name': 'pink', 'color': Color(0xFFE91E63)},
    {'name': 'red', 'color': Color(0xFFE74C3C)},
    {'name': 'teal', 'color': Color(0xFF1ABC9C)},
    {'name': 'indigo', 'color': Color(0xFF3F51B5)},
  ];

  @override
  void initState() {
    super.initState();
    _usernameController.text = widget.profile.username;
    _selectedColor = widget.profile.color;
    _photoUrl = widget.profile.photoUrl;
    _usernameController.addListener(_checkChanges);
  }

  void _checkChanges() {
    final hasChanges =
        _usernameController.text != widget.profile.username ||
        _selectedColor != widget.profile.color;
    if (hasChanges != _hasChanges) {
      setState(() => _hasChanges = hasChanges);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );

      if (image == null) return;

      // Read the image bytes
      final imageBytes = await File(image.path).readAsBytes();

      // Show crop dialog
      final croppedBytes = await showDialog<Uint8List>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _ImageCropDialog(imageBytes: imageBytes),
      );

      if (croppedBytes == null) return;

      setState(() => _isSaving = true);

      // Save cropped bytes to temp file
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/cropped_profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(croppedBytes);

      // Upload the cropped photo
      final (success, result) = await _apiService.uploadProfilePhoto(
        tempFile.path,
      );

      // Clean up temp file
      try {
        await tempFile.delete();
      } catch (_) {}

      if (success && mounted) {
        setState(() {
          _photoUrl = result;
        });

        // Clear Flutter's image cache to force reload
        imageCache.clear();

        widget.onProfileUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo updated!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload photo'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges) return;

    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty || newUsername.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Username must be at least 2 characters'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Update profile via API
      final success = await _apiService.updateProfile(
        username: newUsername,
        color: _selectedColor,
      );

      if (success && mounted) {
        widget.onProfileUpdated();
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update profile'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Profile?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'This will permanently delete "${widget.profile.username}" and all their listening history.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);
      final success = await _apiService.deleteProfile(widget.profile.id);
      if (success) {
        widget.onProfileDeleted();
      } else if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete profile'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileColor = Color(widget.profile.colorValue);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          if (_hasChanges)
            TextButton(
              onPressed: _isSaving ? null : _saveChanges,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Profile Photo
            GestureDetector(
              onTap: _isSaving ? null : _pickImage,
              child: Stack(
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: profileColor, width: 3),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(17),
                      child: _photoUrl != null && _photoUrl!.isNotEmpty
                          ? Image.network(
                              _photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildPlaceholder(profileColor),
                            )
                          : _buildPlaceholder(profileColor),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: profileColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  if (_isSaving)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Tap to change photo',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),

            const SizedBox(height: 40),

            // Username Field
            TextField(
              controller: _usernameController,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: 'Username',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: profileColor, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Color Picker
            Text(
              'Profile Color',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: _colorOptions.map((option) {
                final isSelected = option['name'] == _selectedColor;
                final color = option['color'] as Color;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedColor = option['name'] as String;
                      _checkChanges();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 24)
                        : null,
                  ),
                );
              }).toList(),
            ),

            // Delete button (only for non-owner profiles)
            if (!widget.profile.isOwner) ...[
              const SizedBox(height: 60),
              const Divider(color: Colors.grey),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _isSaving ? null : _confirmDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: const Text(
                  'Delete Profile',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withOpacity(0.7)],
        ),
      ),
      child: Center(
        child: Text(
          widget.profile.username.isNotEmpty
              ? widget.profile.username[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 56,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// Dialog for cropping profile images with square aspect ratio
class _ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;

  const _ImageCropDialog({required this.imageBytes});

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  final _cropController = CropController();
  bool _isCropping = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white24, width: 1),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _isCropping
                        ? null
                        : () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const Text(
                    'Crop Photo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: _isCropping ? null : _onCrop,
                    child: _isCropping
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.purple,
                            ),
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Crop area
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Crop(
                    image: widget.imageBytes,
                    controller: _cropController,
                    aspectRatio: 1.0, // Square
                    initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                      size: 0.9,
                    ),
                    withCircleUi: false,
                    baseColor: const Color(0xFF1A1A1A),
                    maskColor: Colors.black.withOpacity(0.6),
                    interactive: true,
                    fixCropRect:
                        true, // Fixed crop area - user moves/zooms image
                    onCropped: (croppedBytes) {
                      Navigator.pop(context, croppedBytes);
                    },
                  ),
                ),
              ),
            ),

            // Instructions
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Text(
                'Drag to move • Pinch or scroll to zoom',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onCrop() {
    setState(() => _isCropping = true);
    _cropController.crop();
  }
}
