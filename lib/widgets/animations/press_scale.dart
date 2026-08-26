import 'package:flutter/material.dart';

import 'motion.dart';

/// Dips its child slightly while a finger is down.
///
/// Built on [Listener] rather than [GestureDetector] on purpose: Listener
/// observes raw pointer events without competing in the gesture arena, so
/// wrapping a button or an existing GestureDetector adds the feedback without
/// swallowing the tap. That makes it safe to drop around anything.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = 0.97,
    this.enabled = true,
  });

  final Widget child;

  /// How far to dip. Subtle by design — a deep squash reads as a toy.
  final double scale;

  /// Set false for disabled controls, which shouldn't respond to touch.
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _isDown = false;

  void _setDown(bool value) {
    if (!widget.enabled || _isDown == value) return;
    setState(() => _isDown = value);
  }

  @override
  Widget build(BuildContext context) {
    final isPressed = _isDown && widget.enabled;

    return Listener(
      onPointerDown: (_) => _setDown(true),
      onPointerUp: (_) => _setDown(false),
      onPointerCancel: (_) => _setDown(false),
      child: AnimatedScale(
        scale: isPressed ? widget.scale : 1,
        // Quicker going down than coming back up: the press should feel
        // immediate, the release relaxed.
        duration: Motion.scaled(
          context,
          isPressed ? const Duration(milliseconds: 90) : Motion.fast,
        ),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
