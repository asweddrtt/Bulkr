import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/insight.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';

/// The profile's focus section: whatever the user should pay attention to
/// today, from weighing in to drinking enough.
///
/// Rows with an action are tappable; the rest are advice and stay inert.
class InsightList extends StatelessWidget {
  const InsightList({
    super.key,
    required this.insights,
    required this.onAction,
  });

  final List<Insight> insights;
  final ValueChanged<InsightAction> onAction;

  static const Color _cardColor = Color(0xFF1A1A1A);
  static const Color _warning = Color(0xFFFF9E3D);

  static Color _accent(InsightTone tone) {
    switch (tone) {
      case InsightTone.warning:
        return _warning;
      case InsightTone.positive:
      case InsightTone.neutral:
        return AppColors.primaryNeon;
    }
  }

  static IconData _icon(InsightKind kind) {
    switch (kind) {
      case InsightKind.weighIn:
        return Icons.monitor_weight_outlined;
      case InsightKind.plan:
        return Icons.calculate_outlined;
      case InsightKind.pace:
        return Icons.speed_outlined;
      case InsightKind.nutrition:
        return Icons.restaurant_outlined;
      case InsightKind.hydration:
        return Icons.water_drop_outlined;
      case InsightKind.habit:
        return Icons.self_improvement_outlined;
      case InsightKind.milestone:
        return Icons.emoji_events_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final Insight insight in insights)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: _buildRow(insight),
          ),
      ],
    );
  }

  Widget _buildRow(Insight insight) {
    final Color accent = _accent(insight.tone);
    final bool isActionable = insight.action != InsightAction.none;

    final Widget row = Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(6.r),
        border: Border(left: BorderSide(color: accent, width: 3.w)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon(insight.kind), color: accent, size: 18.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.titleKey.tr(namedArgs: insight.args).toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  insight.bodyKey.tr(namedArgs: insight.args),
                  style: GoogleFonts.inter(
                    color: const Color(0xFF9CA3AF),
                    fontSize: 11.sp,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (isActionable) ...[
            SizedBox(width: 8.w),
            Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Icon(Icons.chevron_right, color: accent, size: 18.sp),
            ),
          ],
        ],
      ),
    );

    if (!isActionable) return row;

    return PressScale(
      child: GestureDetector(
        onTap: () => onAction(insight.action),
        behavior: HitTestBehavior.opaque,
        child: row,
      ),
    );
  }
}
