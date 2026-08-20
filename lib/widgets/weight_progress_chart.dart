import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../styles/app_color.dart';

/// Neon area chart of the athlete's logged weigh-ins, with the axis captions
/// rendered underneath it ("30 DAYS AGO / 15 DAYS AGO / TODAY").
class WeightProgressChart extends StatelessWidget {
  /// Weigh-ins in chronological order, oldest first.
  final List<WeighIn> entries;

  /// How far back the chart reaches.
  final int spanInDays;

  const WeightProgressChart({
    super.key,
    required this.entries,
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

  /// Shown until there are two points to draw a curve between.
  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Text(
          'chart_needs_more_data'.tr(),
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12.sp,
            color: AppColors.textGray,
            height: 1.4,
          ),
        ),
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
            child: entries.length < 2
                ? _emptyState()
                : CustomPaint(
                    painter: _WeightChartPainter(
                      entries: entries,
                      spanInDays: spanInDays,
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
  final List<WeighIn> entries;
  final int spanInDays;
  final double lineWidth;
  final double dotRadius;

  _WeightChartPainter({
    required this.entries,
    required this.spanInDays,
    required this.lineWidth,
    required this.dotRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (entries.length < 2 || size.width <= 0 || size.height <= 0) return;

    final List<double> weights = entries.map((e) => e.kg).toList();
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

    // Points are placed by date, so a gap between weigh-ins reads as a gap.
    final DateTime last = entries.last.date;
    final DateTime first = entries.first.date;
    final double windowMs =
        Duration(days: spanInDays).inMilliseconds.toDouble();
    final double spannedMs =
        last.difference(first).inMilliseconds.toDouble().clamp(1, windowMs);
    final double leadingMs = (windowMs - spannedMs).clamp(0, windowMs);

    final List<Offset> points = <Offset>[];
    for (final WeighIn entry in entries) {
      final double offsetMs =
          leadingMs + entry.date.difference(first).inMilliseconds.toDouble();
      final double dx = size.width * (offsetMs / windowMs).clamp(0.0, 1.0);
      final double normalized = (entry.kg - minWeight) / range;
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
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
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

    // One marker per weigh-in, with today's reading emphasised.
    final Paint dotPaint = Paint()..color = Colors.white;
    final Paint dotBorder = Paint()
      ..color = AppColors.primaryNeon
      ..style = PaintingStyle.stroke
      ..strokeWidth = lineWidth / 2;
    for (int i = 0; i < points.length; i++) {
      final double radius = i == points.length - 1 ? dotRadius * 1.2 : dotRadius;
      canvas.drawCircle(points[i], radius, dotPaint);
      canvas.drawCircle(points[i], radius, dotBorder);
    }
  }

  @override
  bool shouldRepaint(_WeightChartPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.spanInDays != spanInDays ||
        oldDelegate.lineWidth != lineWidth ||
        oldDelegate.dotRadius != dotRadius;
  }
}
