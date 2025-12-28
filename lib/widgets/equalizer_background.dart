import 'dart:math';
import 'package:flutter/material.dart';

class EqualizerBackground extends StatefulWidget {
  final bool isPlaying;

  const EqualizerBackground({
    super.key,
    required this.isPlaying,
  });

  @override
  State<EqualizerBackground> createState() => _EqualizerBackgroundState();
}

class _EqualizerBackgroundState extends State<EqualizerBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<double> _barHeights = [];
  final Random _random = Random();
  final int _barCount = 6;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    for (int i = 0; i < _barCount; i++) {
      _barHeights.add(_random.nextDouble());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPlaying) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _EqualizerPainter(
            animationValue: _controller.value,
            barHeights: _barHeights,
            isPlaying: widget.isPlaying,
            barCount: _barCount,
          ),
        );
      },
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final double animationValue;
  final List<double> barHeights;
  final bool isPlaying;
  final int barCount;

  _EqualizerPainter({
    required this.animationValue,
    required this.barHeights,
    required this.isPlaying,
    required this.barCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    final barWidth = 10.0;
    final spacing = 6.0;
    final totalVisualizerWidth =
        (barWidth * barCount) + (spacing * (barCount - 1));
    
    // We want bars primarily on the sides, extending outwards
    // Or just a full row behind? The image shows bars sticking out from sides.
    // Let's draw bars centered vertically.

    for (int i = 0; i < barCount; i++) {
      // Calculate dynamic height based on animation
      // Use sine waves with different phases for each bar for smoothness
      double heightFactor;
      if (isPlaying) {
        final phase = i * 0.5;
        final speed = 2.0 * pi;
        // Combine a slow wave and a fast jitter
        final wave = sin((animationValue * speed) + phase);
        final jitter = sin((animationValue * speed * 3) + phase * 2) * 0.3;
        heightFactor = 0.4 + ((wave + jitter).abs() * 0.6);
      } else {
        heightFactor = 0.2; // Static low height when paused
      }

      final h = size.height * 0.6 * heightFactor * barHeights[i];
      
      // Draw left side bars (extending left from center-left)
      // Actually, easier to just draw a symmetric pattern behind
      
      // Let's create a symmetrical standardized visualizer look relative to the center
      // But since this is BEHIND a 400x400 image, we need it to be wider than 400.
      
      // Calculate x position relative to center
      // We will draw pairs moving outwards from center
      
      final centerX = size.width / 2;
      final halfWidth = size.width / 2; // Use actual half width
      
      // Right side bars
      final xRight = centerX + halfWidth + 4 + (i * (barWidth + spacing));
      final rectRight = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(xRight, size.height / 2),
          width: barWidth,
          height: h,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(rectRight, paint);

      // Left side bars
      final xLeft = centerX - halfWidth - 4 - (i * (barWidth + spacing));
      final rectLeft = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(xLeft, size.height / 2),
          width: barWidth,
          height: h,
        ),
        const Radius.circular(6),
      );
      canvas.drawRRect(rectLeft, paint);
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter oldDelegate) => true;
}
