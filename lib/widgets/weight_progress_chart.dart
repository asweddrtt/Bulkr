import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Neon area chart showing the last N weigh-ins, with the axis captions
/// rendered underneath it ("30 DAYS AGO / 15 DAYS AGO / TODAY").
class WeightProgressChart extends StatelessWidget {
  /// Weigh-ins in chronological order (oldest first, today last).
  final List<double> weights;

  /// How far back the first entry reaches, used for the axis captions.
  final int spanInDays;

  const WeightProgressChart({
    super.key,
    required this.weights,
    this.spanInDays = 30,
  });

  Widget _axisLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9.sp,
        fontWeight: FontWeight.w600,
        color: AppColors.textGray,
        letterSpacing: 1.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(12.w, 16.h, 12.w, 8.h),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 118.h,
            width: double.infinity,
            child: CustomPaint(
              painter: _WeightChartPainter(
                weights: weights,
                lineWidth: 3.w,
                dotRadius: 3.5.r,
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _axisLabel(
                'days_ago'.tr(namedArgs: {'days': '$spanInDays'}).toUpperCase(),
              ),
              _axisLabel(
                'days_ago'
                    .tr(namedArgs: {'days': '${(spanInDays / 2).round()}'})
                    .toUpperCase(),
              ),
              _axisLabel('today'.tr().toUpperCase()),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<double> weights;
  final double lineWidth;
  final double dotRadius;

  _WeightChartPainter({
    required this.weights,
    required this.lineWidth,
    required this.dotRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2 || size.width <= 0 || size.height <= 0) return;

    final double lowest = weights.reduce((a, b) => a < b ? a : b);
    final double highest = weights.reduce((a, b) => a > b ? a : b);
    // Pad the range so a flat series still renders mid-card instead of clipped,
    // and so the line never sits flush against the floor or ceiling.
    final double spread =
        (highest - lowest).abs() < 0.01 ? 1.0 : (highest - lowest);
    final double minWeight = lowest - spread * 0.15;
    final double range = spread * 1.25;
    final double top = lineWidth;
    final double usableHeight = size.height - top - lineWidth;

    final List<Offset> points = <Offset>[];
    for (int i = 0; i < weights.length; i++) {
      final double dx = size.width * i / (weights.length - 1);
      final double normalized = (weights[i] - minWeight) / range;
      final double dy = top + usableHeight * (1 - normalized);
      points.add(Offset(dx, dy));
    }

    final Path line = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      // Smooth the series by curving through the midpoint of each segment.
      final Offset previous = points[i - 1];
      final Offset current = points[i];
      final Offset middle = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      line.quadraticBezierTo(previous.dx, previous.dy, middle.dx, middle.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    final Path fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primaryNeon.withValues(alpha: 0.45),
            AppColors.primaryNeon.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primaryNeon
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Weekly markers plus today's weigh-in.
    final Paint dotPaint = Paint()..color = Colors.white;
    final Paint dotBorder = Paint()
      ..color = AppColors.primaryNeon
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth / 2;
    for (int i = 7; i < points.length; i += 7) {
      canvas.drawCircle(points[i], dotRadius, dotPaint);
      canvas.drawCircle(points[i], dotRadius, dotBorder);
    }
    canvas.drawCircle(points.last, dotRadius * 1.2, dotPaint);
    canvas.drawCircle(points.last, dotRadius * 1.2, dotBorder);
  }

  @override
  bool shouldRepaint(_WeightChartPainter oldDelegate) {
    return oldDelegate.weights != weights ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.dotRadius != dotRadius;
  }
}
