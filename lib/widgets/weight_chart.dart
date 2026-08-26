import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/unit_converter.dart';
import '../models/unit_system.dart';
import '../models/weight_entry.dart';
import '../styles/app_color.dart';
import 'animations/motion.dart';

/// Weigh-in history plotted from real `weight_logs` rows.
///
/// Replaces the hardcoded mock curve: that always sloped up and to the right
/// regardless of what the user actually weighed, which is worse than showing
/// nothing — it silently congratulates people on progress they haven't made.
class WeightChart extends StatelessWidget {
  const WeightChart({
    super.key,
    required this.entries,
    required this.units,
    this.height = 120,
  });

  final List<WeightEntry> entries;
  final UnitSystem units;
  final double height;

  @override
  Widget build(BuildContext context) {
    // One point is a dot, not a trend. Say so rather than drawing a
    // meaningless flat line.
    if (entries.length < 2) {
      return SizedBox(
        height: height.h,
        child: Center(
          child: Text(
            'chart_needs_more_data'.tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              color: AppColors.textGray,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: height.h,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Motion.scaled(context, Motion.reveal),
        curve: Motion.emphasis,
        builder: (context, progress, _) => CustomPaint(
          size: Size(double.infinity, height.h),
          painter: _WeightChartPainter(
            entries: entries,
            progress: progress,
            isMetric: units.isMetric,
          ),
        ),
      ),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  _WeightChartPainter({
    required this.entries,
    required this.progress,
    required this.isMetric,
  });

  final List<WeightEntry> entries;

  /// 0..1 draw-in factor.
  final double progress;

  final bool isMetric;

  @override
  void paint(Canvas canvas, Size size) {
    final values = entries
        .map((e) => isMetric ? e.weightKg : UnitConverter.kgToLb(e.weightKg))
        .toList();

    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);

    // A perfectly flat series would divide by zero. Give it artificial range
    // so it renders as a line through the middle.
    var range = maxValue - minValue;
    if (range < 0.5) {
      final midpoint = (minValue + maxValue) / 2;
      minValue = midpoint - 1;
      maxValue = midpoint + 1;
      range = maxValue - minValue;
    } else {
      // Breathing room so the extremes don't touch the edges.
      final padding = range * 0.15;
      minValue -= padding;
      maxValue += padding;
      range = maxValue - minValue;
    }

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * (i / (values.length - 1));
      // Canvas y grows downward, so a higher weight has to map to a smaller y.
      final y = size.height * (1 - (values[i] - minValue) / range);
      points.add(Offset(x, y));
    }

    final path = _smoothPath(points);

    // Fill under the line first so the stroke sits on top of it.
    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primaryNeon.withValues(alpha: 0.25),
            AppColors.primaryNeon.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.primaryNeon
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();

    // Only the most recent point gets a marker. A dot on every entry turns
    // into noise once there are more than a handful.
    if (progress > 0.98) {
      final last = points.last;
      canvas.drawCircle(
        last,
        5,
        Paint()..color = AppColors.primaryNeon.withValues(alpha: 0.25),
      );
      canvas.drawCircle(last, 3.5, Paint()..color = Colors.white);
    }
  }

  /// Monotone-ish smoothing: control points sit on the horizontal midpoint
  /// between neighbours, which curves the line without letting it overshoot
  /// above or below the real data values.
  Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midX = (previous.dx + current.dx) / 2;
      path.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }

    return path;
  }

  @override
  bool shouldRepaint(covariant _WeightChartPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.entries != entries ||
      oldDelegate.isMetric != isMetric;
}
