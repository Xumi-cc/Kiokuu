import 'package:flutter/material.dart';

class DarkDropdownMenu extends StatefulWidget {
  final List<DropdownMenuOption> options;
  final VoidCallback? onDismissed;
  final Offset? position;

  const DarkDropdownMenu({
    super.key,
    required this.options,
    this.onDismissed,
    this.position,
  });

  @override
  State<DarkDropdownMenu> createState() => _DarkDropdownMenuState();
}

class DropdownMenuOption {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  DropdownMenuOption({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color,
    this.enabled = true,
  });
}

class _DarkDropdownMenuState extends State<DarkDropdownMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Tap to dismiss
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              _animationController.reverse().then((_) {
                Navigator.pop(context);
                widget.onDismissed?.call();
              });
            },
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
        // Menu
        Positioned(
          left: widget.position?.dx ?? 16,
          top: widget.position?.dy ?? 56,
          child: ScaleTransition(
            scale: _scaleAnimation,
            alignment: Alignment.topRight,
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1a1a1a), // Pitch black
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white12,
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    widget.options.length,
                    (index) {
                      final option = widget.options[index];
                      final isLast = index == widget.options.length - 1;

                      return GestureDetector(
                        onTap: option.enabled
                            ? () {
                                _animationController.reverse().then((_) {
                                  Navigator.pop(context);
                                  option.onTap();
                                });
                              }
                            : null,
                        child: Container(
                          decoration: BoxDecoration(
                            border: !isLast
                                ? Border(
                                    bottom: BorderSide(
                                      color: Colors.white10,
                                      width: 0.5,
                                    ),
                                  )
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  option.icon,
                                  size: 18,
                                  color: option.color ??
                                      (option.enabled
                                          ? Colors.white70
                                          : Colors.white30),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  option.label,
                                  style: TextStyle(
                                    color: option.color ??
                                        (option.enabled
                                            ? Colors.white
                                            : Colors.white30),
                                    fontSize: 14,
                                    fontWeight: option.color != null
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Helper function to show dropdown menu
Future<void> showDarkDropdownMenu(
  BuildContext context, {
  required List<DropdownMenuOption> options,
  Offset? position,
}) {
  return showDialog(
    context: context,
    barrierColor: Colors.transparent,
    builder: (context) => DarkDropdownMenu(
      options: options,
      position: position,
    ),
  );
}
