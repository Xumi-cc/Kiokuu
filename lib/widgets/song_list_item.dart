import 'package:flutter/material.dart';
import '../models/song.dart';
import '../services/api_service.dart';

class SongListItem extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final bool isPlaying;
  final bool isCurrent;
  final int index; // Optional, for display #
  final VoidCallback? onMenuTap;
  final VoidCallback? onLike;
  final bool isLiked;
  final bool
  isDisabled; // For songs user doesn't own - grey out and disable tap
  final String?
  subtitle; // Optional custom subtitle (e.g., stream count) - defaults to artist name

  const SongListItem({
    super.key,
    required this.song,
    required this.onTap,
    this.isPlaying = false,
    this.isCurrent = false,
    this.index = -1,
    this.onMenuTap,
    this.onLike,
    this.isLiked = false,
    this.isDisabled = false,
    this.subtitle,
  });

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    // Determine colors based on disabled state
    final textColor = isDisabled
        ? Colors.white.withValues(alpha: 0.3)
        : (isCurrent ? const Color(0xFF1DB954) : Colors.white);
    final subtitleColor = isDisabled
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.6);
    final iconColor = isDisabled
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.white.withValues(alpha: 0.5);

    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent && !isDisabled
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            if (index >= 0) ...[
              SizedBox(
                width: 24,
                child: isCurrent && !isDisabled
                    ? Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 16,
                      )
                    : isDisabled
                    ? Icon(Icons.lock_outline, color: iconColor, size: 14)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(color: iconColor, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 12),
            ],

            // Artwork
            SizedBox(
              width: 42,
              height: 42,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(
                    alpha: isDisabled ? 0.05 : 0.1,
                  ),
                  image:
                      // Prefer coverUrl (full URL from API), fallback to artworkPath
                      (song.coverUrl ?? song.artworkPath) != null &&
                          (song.coverUrl ?? song.artworkPath)!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(
                            song.coverUrl ??
                                (song.artworkPath!.startsWith('http')
                                    ? song.artworkPath!
                                    : '${ApiService.baseUrl}/${song.artworkPath}'),
                          ),
                          fit: BoxFit.cover,
                          colorFilter: isDisabled
                              ? const ColorFilter.mode(
                                  Colors.grey,
                                  BlendMode.saturation,
                                )
                              : null,
                        )
                      : null,
                ),
                child: song.artworkPath == null
                    ? Center(
                        child: Icon(
                          Icons.music_note,
                          color: iconColor,
                          size: 20,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),

            // Title & Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (isDisabled) ...[
                        Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: subtitleColor,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          subtitle ?? song.artist,
                          style: TextStyle(color: subtitleColor, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Like Button (Heart) - Hidden when disabled
            if (onLike != null && !isDisabled) ...[
              IconButton(
                icon: Icon(
                  isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.4),
                  size: 18,
                ),
                onPressed: onLike,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                splashRadius: 20,
              ),
              const SizedBox(width: 8),
            ],

            // Duration
            Text(
              _formatDuration(song.duration),
              style: TextStyle(
                color: isDisabled
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),

            // Menu - Hidden when disabled
            if (onMenuTap != null && !isDisabled)
              IconButton(
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: Colors.white.withValues(alpha: 0.4),
                  size: 18,
                ),
                onPressed: onMenuTap,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                splashRadius: 20,
              ),
          ],
        ),
      ),
    );
  }
}
