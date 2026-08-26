import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

/// Fades and lifts its child into place once, on first build.
///
/// Deliberately fire-once: the animation runs when the widget is first
/// inserted and never replays on rebuild, so a cubit emitting new state does
/// not make the whole screen flicker.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = Motion.entranceOffset,
    this.duration = Motion.entrance,
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curve;
  late final Animation<Offset> _slide;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    // Held as a field, not built in build(): CurvedAnimation owns resources and
    // has to be disposed.
    _curve = CurvedAnimation(parent: _controller, curve: Motion.enter);
    _slide = Tween<Offset>(begin: widget.offset, end: Offset.zero)
        .animate(_curve);

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context)) return widget.child;

    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Wraps each child in an [Entrance] with an increasing delay.
///
/// Two details that matter:
///
/// * Bare [SizedBox] spacers are passed through untouched and do not consume a
///   beat. Otherwise a column of ten widgets and nine spacers would take twice
///   as long to arrive as it looks like it should.
/// * The delay is capped, so a long list still finishes arriving promptly
///   rather than trickling in for a second and a half.
List<Widget> staggered(
  List<Widget> children, {
  Duration step = Motion.stagger,
  int maxSteps = 8,
  Duration initialDelay = Duration.zero,
}) {
  var slot = 0;

  return children.map((child) {
    if (child is SizedBox && child.child == null) return child;

    final delay = initialDelay + step * math.min(slot, maxSteps);
    slot++;
    return Entrance(delay: delay, child: child);
  }).toList();
}
