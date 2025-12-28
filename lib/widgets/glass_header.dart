import 'dart:ui';
import 'package:flutter/material.dart';

class GlassHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final double height;
  final EdgeInsetsGeometry? padding;

  const GlassHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.height = 70,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: height,
          padding:
              padding ??
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(
              0.05,
            ), // Very transparent to blend with ambilight
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.05),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Leading widget (optional)
              if (leading != null) ...[leading!, const SizedBox(width: 12)],

              // Title
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),

              const Spacer(),

              // Action widgets (optional)
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}
