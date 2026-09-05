import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../styles/app_color.dart';
import 'animations/motion.dart';

/// The day's calories against the day's target, as a ring.
///
/// A ring rather than the bar used elsewhere in the app because this is the
/// one number the tracker exists to state, and it needs to read from across
/// the room. The bars on the dashboard compare several things to each other;
/// this compares one thing to one target.
///
/// Deliberately does not wrap past full. [isOver] is what says the target has
/// been passed — a second lap would render 3,100 of 3,000 as a ring barely
/// started, which is the opposite of the truth.
class CalorieRing extends StatelessWidget {
  const CalorieRing({
    super.key,
    required this.progress,
    required this.isOver,
    required this.child,
    this.size = 190,
    this.stroke = 13,
  });

  /// 0..1, already clamped by the caller.
  final double progress;

  /// Recolours the ring rather than lengthening it.
  final bool isOver;

  /// What sits in the middle — the remaining-calories headline.
  final Widget child;

  /// Logical pixels before screenutil scaling.
  final double size;
  final double stroke;

  /// Amber rather than red. Going over on a bulk is a normal Tuesday, not a
  /// failure, and an alarm colour would be editorialising.
  static const Color overColor = Color(0xFFFF9E3D);

  @override
  Widget build(BuildContext context) {
    final double diameter = size.w;

    return SizedBox(
      width: diameter,
      height: diameter,
      child: TweenAnimationBuilder<double>(
        // Sweeps up to the value rather than appearing at it, for the same
        // reason the plan reveal counts up: the number reads as something
        // being worked out rather than printed.
        tween: Tween<double>(begin: 0, end: progress),
        duration: Motion.scaled(context, Motion.reveal),
        curve: Motion.emphasis,
        builder: (context, value, _) {
          return CustomPaint(
            painter: _CalorieRingPainter(
              progress: Motion.reduced(context) ? progress : value,
              color: isOver ? overColor : AppColors.primaryNeon,
              stroke: stroke.w,
            ),
            child: Center(child: child),
          );
        },
      ),
    );
  }
}

class _CalorieRingPainter extends CustomPainter {
  const _CalorieRingPainter({
    required this.progress,
    required this.color,
    required this.stroke,
  });

  final double progress;
  final Color color;
  final double stroke;

  /// Twelve o'clock. Canvas angles start at three, so the sweep is rotated
  /// back a quarter turn to start where a reader expects a dial to.
  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset centre = Offset(size.width / 2, size.height / 2);
    final double radius = (size.shortestSide - stroke) / 2;
    final Rect box = Rect.fromCircle(center: centre, radius: radius);

    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.darkBorder;

    canvas.drawCircle(centre, radius, track);

    if (progress <= 0) return;

    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    // A glow under the arc, matching the neon treatment the plan reveal and
    // the nav bar already use. Drawn first so the arc sits on top of it.
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final double sweep = 2 * math.pi * progress.clamp(0.0, 1.0);

    canvas.drawArc(box, _startAngle, sweep, false, glow);
    canvas.drawArc(box, _startAngle, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_CalorieRingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}
