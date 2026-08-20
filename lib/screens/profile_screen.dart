import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../go_router/app_routes.dart';
import '../styles/app_color.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/editable_metric_card.dart';
import '../widgets/focus_area_tile.dart';
import '../widgets/nutrition_plan_card.dart';
import '../widgets/profile_header.dart';
import '../widgets/weight_edit_sheet.dart';
import '../widgets/weight_progress_chart.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // TODO: hydrate from the onboarding data / backend instead of these stubs.
  static const int _progressSpanInDays = 30;

  final String _athleteName = 'Max Gains';
  final int _dailyCalories = 3400;
  final double _weeklyGainKg = 0.5;
  double _currentWeight = 88.5;
  double _targetWeight = 95.0;

  /// Daily weigh-ins for the last [_progressSpanInDays] days, oldest first.
  late List<double> _weightHistory = _buildWeightHistory();

  final List<FocusArea> _focusAreas = const [
    FocusArea(nameKey: 'muscle_quadriceps', intensity: FocusIntensity.heavy),
    FocusArea(nameKey: 'muscle_back', intensity: FocusIntensity.volume),
    FocusArea(nameKey: 'muscle_delts', intensity: FocusIntensity.resting),
  ];

  /// Stand-in series ending on the current weight, gently trending upwards.
  List<double> _buildWeightHistory() {
    const double gainedOverSpan = 4.2;
    final double start = _currentWeight - gainedOverSpan;
    return List<double>.generate(_progressSpanInDays + 1, (int day) {
      final double progress = day / _progressSpanInDays;
      // Sine wobble keeps the line from looking like a straight ramp.
      final double wobble = math.sin(day / 3.2) * 0.25;
      return start + gainedOverSpan * progress + wobble;
    });
  }

  double get _monthlyDelta => _weightHistory.last - _weightHistory.first;

  Future<void> _editWeight({required bool isTarget}) async {
    final double? updated = await WeightEditSheet.show(
      context,
      title: isTarget
          ? 'edit_target_weight'.tr()
          : 'edit_current_weight'.tr(),
      initialValue: isTarget ? _targetWeight : _currentWeight,
    );
    if (updated == null || !mounted) return;

    setState(() {
      if (isTarget) {
        _targetWeight = updated;
      } else {
        _currentWeight = updated;
        _weightHistory = _buildWeightHistory();
      }
    });
  }

  void _onTabSelected(AppTab tab) {
    if (tab == AppTab.profile) return;
    // TODO: route to the dashboard / workouts / progress screens once they exist.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.cardDark,
        content: Text(
          'coming_soon'.tr(),
          style: GoogleFonts.inter(fontSize: 12.sp, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.anton(
                fontSize: 20.sp,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String deltaSign = _monthlyDelta >= 0 ? '+' : '-';

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.profile,
        onTabSelected: _onTabSelected,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.fill,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileHeader(
                  name: _athleteName,
                  onSettingsTap: () {
                    // TODO: open the settings screen once it exists.
                  },
                ),
                SizedBox(height: 16.h),

                // --- WEIGHT PROGRESS ---
                _buildSectionTitle(
                  'weight_progress_title'.tr(),
                  trailing: Padding(
                    padding: EdgeInsets.only(bottom: 2.h),
                    child: Text(
                      'delta_this_month'.tr(
                        namedArgs: {
                          'delta':
                              '$deltaSign${_monthlyDelta.abs().toStringAsFixed(1)}',
                        },
                      ).toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryNeon,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                WeightProgressChart(
                  weights: _weightHistory,
                  spanInDays: _progressSpanInDays,
                ),
                SizedBox(height: 12.h),

                // --- WEIGHT METRICS ---
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: EditableMetricCard(
                          label: 'current_weight_label'.tr(),
                          value: _currentWeight.toStringAsFixed(1),
                          unit: 'kg_unit'.tr(),
                          onEdit: () => _editWeight(isTarget: false),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: EditableMetricCard(
                          label: 'target_weight_label'.tr(),
                          value: _targetWeight.toStringAsFixed(1),
                          unit: 'kg_unit'.tr(),
                          onEdit: () => _editWeight(isTarget: true),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),

                // --- NUTRITION PLAN ---
                NutritionPlanCard(
                  dailyCalories: _dailyCalories,
                  weeklyGainKg: _weeklyGainKg,
                  onRecalculate: () => context.push(AppRoutes.surplus),
                ),
                SizedBox(height: 20.h),

                // --- FOCUS AREAS ---
                _buildSectionTitle('focus_areas_title'.tr()),
                ..._focusAreas.map((area) => FocusAreaTile(area: area)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
