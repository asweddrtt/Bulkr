import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
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
class WeightChart extends StatefulWidget {
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
  State<WeightChart> createState() => _WeightChartState();
}

class _WeightChartState extends State<WeightChart> {
  int? _selectedIndex;

  void _updateSelection(double dx, double width) {
    if (widget.entries.length < 2 || width <= 0) return;
    // Map the local X coordinate to a percentage, then find the closest data index
    final percent = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _selectedIndex = (percent * (widget.entries.length - 1)).round();
    });
  }

  void _clearSelection() {
    if (_selectedIndex != null) {
      setState(() => _selectedIndex = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.length < 2) {
      return SizedBox(
        height: widget.height.h,
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
      height: widget.height.h,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            // Handles both tapping a single point and dragging across the graph
            onTapDown: (details) => _updateSelection(details.localPosition.dx, constraints.maxWidth),
            onHorizontalDragUpdate: (details) => _updateSelection(details.localPosition.dx, constraints.maxWidth),
            onTapUp: (_) => _clearSelection(),
            onTapCancel: _clearSelection,
            onHorizontalDragEnd: (_) => _clearSelection(),
            onHorizontalDragCancel: _clearSelection,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: Motion.scaled(context, Motion.reveal),
              curve: Motion.emphasis,
              builder: (context, progress, _) => CustomPaint(
                size: Size(double.infinity, widget.height.h),
                painter: _WeightChartPainter(
                  entries: widget.entries,
                  progress: progress,
                  isMetric: widget.units.isMetric,
                  selectedIndex: _selectedIndex, // Pass the active index down
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


class _WeightChartPainter extends CustomPainter {
  _WeightChartPainter({
    required this.entries,
    required this.progress,
    required this.isMetric,
    this.selectedIndex,
  });

  final List<WeightEntry> entries;
  final double progress;
  final bool isMetric;
  final int? selectedIndex;

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

    if (selectedIndex != null && progress > 0.98) {
      final point = points[selectedIndex!];
      final entry = entries[selectedIndex!];
      final weight = isMetric ? entry.weightKg : UnitConverter.kgToLb(entry.weightKg);
      final unit = isMetric ? 'kg_unit'.tr().toLowerCase() : 'lb_unit'.tr().toLowerCase();
      final dateStr = DateFormat.MMMd().format(entry.loggedAt);

      // 1. Draw vertical scrubber line
      canvas.drawLine(
        Offset(point.dx, 0),
        Offset(point.dx, size.height),
        Paint()
          ..color = AppColors.textGray.withValues(alpha: 0.3)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke,
      );

      // 2. Draw highlighted dot
      canvas.drawCircle(point, 6, Paint()..color = AppColors.primaryNeon);
      // Using a dark center to punch it out of the background
      canvas.drawCircle(point, 4, Paint()..color = const Color(0xFF1A1A1A));

      // 3. Draw tooltip label using TextPainter
      final text = '$dateStr • ${weight.toStringAsFixed(1)} $unit';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: GoogleFonts.inter(
            fontSize: 10.sp,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Keep tooltip strictly inside horizontal bounds
      var textX = point.dx - tp.width / 2;
      if (textX < 0) textX = 0;
      if (textX + tp.width > size.width) textX = size.width - tp.width;

      // Keep tooltip inside vertical bounds (flip it underneath the point if too high)
      var textY = point.dy - 16.h - tp.height;
      if (textY < 0) textY = point.dy + 16.h;

      final bgRect = RRect.fromLTRBR(
        textX - 8.w,
        textY - 4.h,
        textX + tp.width + 8.w,
        textY + tp.height + 4.h,
        Radius.circular(6.r),
      );

      canvas.drawRRect(bgRect, Paint()..color = const Color(0xFF2A2A2A));
      tp.paint(canvas, Offset(textX, textY));

    } else if (progress > 0.98) {
      // Default behavior when not touching: only the most recent point gets a marker
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
          oldDelegate.isMetric != isMetric ||
          oldDelegate.selectedIndex != selectedIndex;
}
