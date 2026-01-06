import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Service to pre-compile shaders on platforms where they cause jank.
/// This is especially important on Windows where shader compilation
/// can cause noticeable stuttering on first use.
class ShaderWarmupService {
  static final ShaderWarmupService _instance = ShaderWarmupService._internal();
  static ShaderWarmupService get instance => _instance;
  ShaderWarmupService._internal();

  bool _isWarmedUp = false;
  bool get isWarmedUp => _isWarmedUp;

  /// Check if shader warmup is needed for the current platform
  static bool get needsWarmup => !kIsWeb && Platform.isWindows;

  /// Warm up common shaders by rendering them off-screen.
  /// This prevents jank when these effects are first used.
  ///
  /// [onProgress] is called with a value between 0.0 and 1.0
  /// [onStatusChange] is called with human-readable status messages
  Future<void> warmUp({
    void Function(double progress)? onProgress,
    void Function(String status)? onStatusChange,
  }) async {
    if (_isWarmedUp || !needsWarmup) {
      _isWarmedUp = true;
      return;
    }

    debugPrint('🎨 Starting shader warmup for Windows...');

    final steps = [
      _WarmupStep('Preparing graphics engine...', _warmUpBasicShaders),
      _WarmupStep('Optimizing blur effects...', _warmUpBlurShaders),
      _WarmupStep('Loading gradient shaders...', _warmUpGradientShaders),
      _WarmupStep('Compiling image filters...', _warmUpImageFilterShaders),
      _WarmupStep('Finalizing optimizations...', _warmUpMiscShaders),
    ];

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      onStatusChange?.call(step.status);
      onProgress?.call(i / steps.length);

      try {
        await step.action();
      } catch (e) {
        debugPrint('⚠️ Shader warmup step failed: ${step.status} - $e');
      }

      // Small delay to allow UI to update and shaders to compile
      await Future.delayed(const Duration(milliseconds: 100));
    }

    onProgress?.call(1.0);
    onStatusChange?.call('Ready!');

    _isWarmedUp = true;
    debugPrint('✅ Shader warmup complete');
  }

  /// Warm up basic shaders (colors, simple shapes)
  Future<void> _warmUpBasicShaders() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(100, 100);

    // Basic filled rectangles with different colors
    final paint = Paint();
    for (final color in [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.white,
      Colors.black,
    ]) {
      paint.color = color;
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    }

    // Rounded rectangles
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 10, 80, 80),
        const Radius.circular(12),
      ),
      paint,
    );

    // Circles
    canvas.drawCircle(const Offset(50, 50), 40, paint);

    // Finalize
    final picture = recorder.endRecording();
    await picture.toImage(size.width.toInt(), size.height.toInt());
    picture.dispose();
  }

  /// Warm up blur shaders (BackdropFilter, ImageFilter.blur)
  Future<void> _warmUpBlurShaders() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(100, 100);

    // Draw base content
    final paint = Paint()..color = Colors.blue;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Apply blur filters with different sigma values
    for (final sigma in [5.0, 10.0, 15.0, 20.0]) {
      final blurFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      final blurPaint = Paint()..imageFilter = blurFilter;
      canvas.saveLayer(null, blurPaint);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
      canvas.restore();
    }

    final picture = recorder.endRecording();
    await picture.toImage(size.width.toInt(), size.height.toInt());
    picture.dispose();
  }

  /// Warm up gradient shaders
  Future<void> _warmUpGradientShaders() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(100, 100);

    // Linear gradients
    final linearGradient = LinearGradient(
      colors: [Colors.red, Colors.blue, Colors.green],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = linearGradient,
    );

    // Radial gradients
    final radialGradient = RadialGradient(
      colors: [Colors.white, Colors.black],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = radialGradient,
    );

    // Sweep gradients
    final sweepGradient = SweepGradient(
      colors: [Colors.red, Colors.blue, Colors.red],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = sweepGradient,
    );

    final picture = recorder.endRecording();
    await picture.toImage(size.width.toInt(), size.height.toInt());
    picture.dispose();
  }

  /// Warm up image filter shaders (used for effects)
  Future<void> _warmUpImageFilterShaders() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(100, 100);

    final paint = Paint()..color = Colors.purple;

    // Matrix color filter (used for tinting)
    final colorFilter = ColorFilter.mode(
      Colors.red.withValues(alpha: 0.5),
      BlendMode.overlay,
    );
    canvas.saveLayer(null, Paint()..colorFilter = colorFilter);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    canvas.restore();

    // Compose filters
    final composedFilter = ui.ImageFilter.compose(
      outer: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      inner: ui.ImageFilter.dilate(radiusX: 1, radiusY: 1),
    );
    canvas.saveLayer(null, Paint()..imageFilter = composedFilter);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    canvas.restore();

    final picture = recorder.endRecording();
    await picture.toImage(size.width.toInt(), size.height.toInt());
    picture.dispose();
  }

  /// Warm up miscellaneous shaders
  Future<void> _warmUpMiscShaders() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = const Size(100, 100);

    // Text rendering
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'KioKuu',
        style: TextStyle(fontSize: 24, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset.zero);

    // Shadows
    final shadowPaint = Paint()
      ..color = Colors.black
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRect(Rect.fromLTWH(10, 10, 80, 80), shadowPaint);

    // Strokes
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(20, 20, 60, 60), strokePaint);

    final picture = recorder.endRecording();
    await picture.toImage(size.width.toInt(), size.height.toInt());
    picture.dispose();
  }
}

class _WarmupStep {
  final String status;
  final Future<void> Function() action;

  _WarmupStep(this.status, this.action);
}
