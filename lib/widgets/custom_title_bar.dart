import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A custom title bar widget that replaces the system window decorations
/// on desktop platforms (Windows, macOS, Linux).
class CustomTitleBar extends StatefulWidget {
  /// Optional child widget to display in the title bar (e.g., navigation, search)
  final Widget? child;

  /// The height of the title bar
  final double height;

  /// Background color of the title bar
  final Color? backgroundColor;

  /// Whether to show the app title/logo
  final bool showTitle;

  /// Custom title text
  final String title;

  const CustomTitleBar({
    super.key,
    this.child,
    this.height = 40,
    this.backgroundColor,
    this.showTitle = true,
    this.title = 'KioKuu',
  });

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;
  bool _isFocused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _updateWindowState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _updateWindowState() async {
    final isMaximized = await windowManager.isMaximized();
    final isFocused = await windowManager.isFocused();
    if (mounted) {
      setState(() {
        _isMaximized = isMaximized;
        _isFocused = isFocused;
      });
    }
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  void onWindowFocus() {
    setState(() => _isFocused = true);
  }

  @override
  void onWindowBlur() {
    setState(() => _isFocused = false);
  }

  @override
  Widget build(BuildContext context) {
    // Only show custom title bar on desktop
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return widget.child ?? const SizedBox.shrink();
    }

    final isMacOS = Platform.isMacOS;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.backgroundColor ?? Colors.black.withOpacity(0.95),
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
          ),
        ),
        child: Row(
          children: [
            // macOS: Traffic lights are on the left, add spacing
            if (isMacOS) const SizedBox(width: 78),

            // Linux/Windows: Show logo on the left
            if (!isMacOS && widget.showTitle) ...[
              const SizedBox(width: 12),
              _buildLogo(),
              const SizedBox(width: 8),
            ],

            // Main content area (expandable)
            Expanded(child: widget.child ?? const SizedBox.shrink()),

            // Window controls (Windows/Linux only - macOS uses native traffic lights)
            if (!isMacOS) _buildWindowControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/images/kiokuu_white.svg',
          width: 22,
          height: 22,
        ),
        const SizedBox(width: 8),
        Text(
          widget.title,
          style: TextStyle(
            color: _isFocused ? Colors.white : Colors.white60,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildWindowControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minimize button
        _WindowButton(
          icon: Icons.remove,
          onPressed: () => windowManager.minimize(),
          hoverColor: Colors.white.withOpacity(0.1),
        ),
        // Maximize/Restore button
        _WindowButton(
          icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _isMaximized ? 14 : 16,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              windowManager.unmaximize();
            } else {
              windowManager.maximize();
            }
          },
          hoverColor: Colors.white.withOpacity(0.1),
        ),
        // Close button
        _WindowButton(
          icon: Icons.close,
          onPressed: () => windowManager.close(),
          hoverColor: const Color(0xFFE81123),
          isClose: true,
        ),
      ],
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color hoverColor;
  final bool isClose;
  final double iconSize;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.hoverColor,
    this.isClose = false,
    this.iconSize = 16,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 40,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _isHovered && widget.isClose ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// A helper widget that wraps your app content with a custom title bar
/// Only applies on desktop platforms
class TitleBarScaffold extends StatelessWidget {
  final Widget body;
  final String title;
  final Widget? titleBarChild;
  final Color? titleBarColor;
  final double titleBarHeight;
  final bool showTitleBarTitle;

  const TitleBarScaffold({
    super.key,
    required this.body,
    this.title = 'KioKuu',
    this.titleBarChild,
    this.titleBarColor,
    this.titleBarHeight = 40,
    this.showTitleBarTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    // On mobile, just return the body
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return body;
    }

    return Column(
      children: [
        CustomTitleBar(
          height: titleBarHeight,
          backgroundColor: titleBarColor,
          showTitle: showTitleBarTitle,
          title: title,
          child: titleBarChild,
        ),
        Expanded(child: body),
      ],
    );
  }
}
