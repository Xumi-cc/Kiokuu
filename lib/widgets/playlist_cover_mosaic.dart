import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// A 2x2 mosaic of album covers for playlists
/// Shows up to 4 images in a grid, filling the entire available space
class PlaylistCoverMosaic extends StatelessWidget {
  final List<String> coverImages;
  final double? size;
  final double borderRadius;

  const PlaylistCoverMosaic({
    super.key,
    required this.coverImages,
    this.size,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // No images - show placeholder
          if (coverImages.isEmpty) {
            return _buildPlaceholder();
          }

          // Only 1 image - show single large image
          if (coverImages.length == 1) {
            return _buildSingleImage(coverImages[0]);
          }

          // 2-4 images - show mosaic grid
          return _buildMosaic();
        },
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey[800]!, Colors.grey[900]!],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.grey[600],
          size: 64,
        ),
      ),
    );
  }

  Widget _buildSingleImage(String imagePath) {
    // Use imagePath directly if it's already a full URL
    final url = imagePath.startsWith('http')
        ? imagePath
        : '${ApiService.baseUrl}/$imagePath';
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => _buildPlaceholder(),
    );
  }

  Widget _buildMosaic() {
    const gap = 2.0;

    // Get image paths, rotating if less than 4
    final images = List.generate(4, (i) {
      if (i < coverImages.length) {
        return coverImages[i];
      }
      // Rotate: for index 2 use image 0, for index 3 use image 1 (if we have 2 images)
      return coverImages[i % coverImages.length];
    });

    return Column(
      children: [
        // Top row
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildCell(images[0])),
              const SizedBox(width: gap),
              Expanded(child: _buildCell(images[1])),
            ],
          ),
        ),
        const SizedBox(height: gap),
        // Bottom row
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildCell(images[2])),
              const SizedBox(width: gap),
              Expanded(child: _buildCell(images[3])),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCell(String imagePath) {
    // Use imagePath directly if it's already a full URL
    final url = imagePath.startsWith('http')
        ? imagePath
        : '${ApiService.baseUrl}/$imagePath';
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey[850],
        child: Center(
          child: Icon(Icons.music_note, color: Colors.grey[700], size: 24),
        ),
      ),
    );
  }
}
