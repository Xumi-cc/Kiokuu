import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../providers/music_provider.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<MusicProvider>(
      builder: (context, provider, _) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Column(
            children: [
              _buildProgressBar(context, provider),
              const SizedBox(height: 20),
              _buildControlButtons(context, provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProgressBar(BuildContext context, MusicProvider provider) {
    final position = provider.currentPosition;
    final duration = provider.totalDuration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withOpacity(0.1),
            thumbColor: const Color(0xFFAAAAAA),
            overlayColor: Colors.white.withOpacity(0.2),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChanged: (value) {
              final newPosition = Duration(
                milliseconds: (value * duration.inMilliseconds).round(),
              );
              provider.seekTo(newPosition);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControlButtons(BuildContext context, MusicProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildIconButton(
          icon: Icons.shuffle_rounded,
          onPressed: provider.toggleShuffle,
          isActive: provider.isShuffled,
          size: 22, // Reduced for mobile
        ),
        _buildIconButton(
          icon: Icons.skip_previous_rounded,
          onPressed: provider.playPrevious,
          size: 32, // Reduced from 40
        ),
        _buildPlayPauseButton(provider),
        _buildIconButton(
          icon: Icons.skip_next_rounded,
          onPressed: provider.playNext,
          size: 32, // Reduced from 40
        ),
        _buildIconButton(
          icon: _getRepeatIcon(provider.repeatMode),
          onPressed: provider.toggleRepeat,
          isActive: provider.repeatMode != RepeatMode.off,
          size: 22, // Reduced for mobile
        ),
      ],
    );
  }

  IconData _getRepeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.one:
        return Icons.repeat_one_rounded;
      case RepeatMode.all:
        return Icons.repeat_rounded;
      case RepeatMode.off:
        return Icons.repeat_rounded;
    }
  }

  Widget _buildPlayPauseButton(MusicProvider provider) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFAAAAAA)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: provider.isLoading ? null : provider.togglePlayPause,
          customBorder: const CircleBorder(),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: provider.isLoading
                  ? SizedBox(
                      key: const ValueKey('controls_loading'),
                      width: 28,
                      height: 28,
                      child: LoadingAnimationWidget.threeArchedCircle(
                        color: Colors.black,
                        size: 28,
                      ),
                    )
                  : Icon(
                      key: ValueKey('controls_${provider.isPlaying ? "pause" : "play"}'),
                      provider.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 28,
                      color: Colors.black,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isActive = false,
    double size = 28,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
        shape: BoxShape.circle,
        border: isActive ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: IconButton(
        icon: Icon(icon, size: size),
        onPressed: onPressed,
        color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}
