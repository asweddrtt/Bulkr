import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ProfileScreen extends StatelessWidget {
  final String displayName;
  final String? avatarUrl;
  final double currentWeight;
  final double targetWeight;
  final int calorieTarget;
  final String activityLevel;

  const ProfileScreen({
    Key? key,
    required this.displayName,
    this.avatarUrl,
    required this.currentWeight,
    required this.targetWeight,
    required this.calorieTarget,
    required this.activityLevel,
  }) : super(key: key);


  // Theme Constants
  static const Color bgColor = Color(0xFF121212);
  static const Color cardColor = Color(0xFF1A1A1A);
  static const Color accentColor = Color(0xFFCBF026);
  static const Color borderColor = Color(0xFF333333);
  static const Color textMuted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWeightProgress(),
                  SizedBox(height: 16.h),
                  _buildWeightCards(),
                  SizedBox(height: 16.h),
                  _buildNutritionPlan(),
                  SizedBox(height: 16.h),
                  _buildFocusAreas(),
                  SizedBox(height: 32.h),
                ],
              ),
            ),
          ),
        ],
    );
  }
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor, width: 2.w),
                ),
                child: CircleAvatar(
                  radius: 18.r,
                  backgroundColor: borderColor,
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
                  child: avatarUrl == null
                      ? Icon(Icons.person, color: textMuted, size: 20.sp)
                      : null,
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                displayName.toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          Icon(Icons.settings_outlined, color: textMuted, size: 24.sp),
        ],
      ),
    );
  }

  Widget _buildDashedWrapper({required Widget child}) {
    return Container(
      padding: EdgeInsets.all(2.w),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1.5.w),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: child,
    );
  }

  Widget _buildWeightProgress() {
      final targetDiff = targetWeight - currentWeight;
      final diffPrefix = targetDiff >= 0 ? '+' : '';
      final formattedDiff = '$diffPrefix${targetDiff.toStringAsFixed(1)}';

      return _buildDashedWrapper(
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(8.r),
          ),
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'weight_progress'.tr(),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'target_kg'.tr(args: [formattedDiff]),
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            SizedBox(height: 24.h),
            SizedBox(
              height: 120.h,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          accentColor.withOpacity(0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  CustomPaint(
                    size: Size(double.infinity, 120.h),
                    painter: ChartMockPainter(),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('days_ago'.tr(args: ['30']), style: _chartLabelStyle),
                Text('days_ago'.tr(args: ['15']), style: _chartLabelStyle),
                Text('today'.tr(), style: _chartLabelStyle),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static final TextStyle _chartLabelStyle = TextStyle(
    color: textMuted,
    fontSize: 10.sp,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
  );

  Widget _buildWeightCards() {
    return Row(
      children: [
        Expanded(
          child: _buildDashedWrapper(
            child: _buildSingleWeightCard(
                'current_weight'.tr(),
                currentWeight.toStringAsFixed(1)
            ),
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: _buildDashedWrapper(
            child: _buildSingleWeightCard(
                'target_weight'.tr(),
                targetWeight.toStringAsFixed(1)
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleWeightCard(String label, String value) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8.r),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  height: 1.4,
                ),
              ),
              Icon(Icons.edit, color: textMuted, size: 14.sp),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36.sp,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 4.w),
              Text(
                'kg'.tr(),
                style: TextStyle(
                  color: textMuted,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionPlan() {
    // Adds the comma separator for thousands, e.g., 3550 -> 3,550
    final formattedCalories = calorieTarget.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (Match m) => '${m[1]},'
    );

    return _buildDashedWrapper(
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8.r),
        ),
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'nutrition_plan'.tr(),
              style: TextStyle(
                color: textMuted,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'current_daily_goal'.tr(args: [formattedCalories]),
              style: TextStyle(
                color: Colors.white,
                fontSize: 18.sp,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              // Assuming your JSON takes the activity level as an argument here
              'nutrition_plan_desc'.tr(args: [activityLevel.tr()]),
              style: TextStyle(
                color: const Color(0xFFD1D5DB),
                fontSize: 13.sp,
                height: 1.5,
              ),
            ),
            SizedBox(height: 20.h),
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: accentColor, width: 2.w),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                child: Text(
                  'recalculate'.tr(),
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusAreas() {
    return _buildDashedWrapper(
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8.r),
        ),
        padding: EdgeInsets.only(top: 8.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
              child: Text(
                'focus_areas'.tr(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            SizedBox(height: 8.h),
            _buildFocusRow('quadriceps'.tr(), 'heavy'.tr(), true),
            SizedBox(height: 2.h),
            _buildFocusRow('back'.tr(), 'volume'.tr(), true),
            SizedBox(height: 2.h),
            _buildFocusRow('delts'.tr(), 'resting'.tr(), false),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusRow(String area, String status, bool isActive) {
    return Container(
      color: cardColor,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Row(
        children: [
          Container(
            width: 4.w,
            height: 16.h,
            color: isActive ? accentColor : borderColor,
          ),
          SizedBox(width: 12.w),
          Text(
            area,
            style: TextStyle(
              color: isActive ? const Color(0xFFD1D5DB) : textMuted,
              fontSize: 11.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          Text(
            status,
            style: TextStyle(
              color: isActive ? Colors.white : textMuted,
              fontSize: 11.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter for the mock line chart
class ChartMockPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = ProfileScreen.accentColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();

    // Mock data points mapping to UI
    final points = [
      Offset(0, size.height * 0.9),
      Offset(size.width * 0.2, size.height * 0.75),
      Offset(size.width * 0.4, size.height * 0.65),
      Offset(size.width * 0.6, size.height * 0.45),
      Offset(size.width * 0.8, size.height * 0.3),
      Offset(size.width, size.height * 0.15),
    ];

    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      // Using quadratic bezier for smooth curves between points
      final p0 = points[i - 1];
      final p1 = points[i];
      final midX = (p0.dx + p1.dx) / 2;
      path.quadraticBezierTo(midX, p0.dy, midX, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(midX, p1.dy, p1.dx, p1.dy);
    }

    canvas.drawPath(path, linePaint);

    // Draw the white dots at the actual data points
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}