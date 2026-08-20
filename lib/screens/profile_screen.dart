import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../go_router/app_routes.dart';
import '../models/user_profile.dart';
import '../services/nutrition_calculator.dart';
import '../state/profile_controller.dart';
import '../state/profile_scope.dart';
import '../styles/app_color.dart';
import '../widgets/account_sheet.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/editable_metric_card.dart';
import '../widgets/focus_area_tile.dart';
import '../widgets/metric_edit_sheet.dart';
import '../widgets/nutrition_plan_card.dart';
import '../widgets/profile_header.dart';
import '../widgets/weight_progress_chart.dart';

class ProfileScreen extends StatelessWidget {
  /// Window the weight chart and the monthly delta are measured over.
  static const int progressSpanInDays = 30;

  const ProfileScreen({super.key});

  Future<void> _editCurrentWeight(
    BuildContext context,
    ProfileController controller,
    UserProfile profile,
  ) async {
    final double? updated = await MetricEditSheet.show(
      context,
      title: 'edit_current_weight'.tr(),
      initialValue: profile.currentWeightKg ?? profile.targetWeightKg,
      unitLabel: 'kg_unit'.tr(),
      min: 30,
      max: 300,
    );
    // Logs today's weigh-in, which also feeds the chart and the calorie goal.
    if (updated != null) await controller.logWeighIn(updated);
  }

  Future<void> _editTargetWeight(
    BuildContext context,
    ProfileController controller,
    UserProfile profile,
  ) async {
    final double? updated = await MetricEditSheet.show(
      context,
      title: 'edit_target_weight'.tr(),
      initialValue: profile.targetWeightKg,
      unitLabel: 'kg_unit'.tr(),
      min: 30,
      max: 300,
    );
    if (updated != null) await controller.setTargetWeight(updated);
  }

  Future<void> _openAccountSheet(
    BuildContext context,
    ProfileController controller,
    UserProfile profile,
  ) async {
    final String? name = await AccountSheet.show(
      context,
      profile: profile,
      onSignOut: controller.signOut,
    );
    if (name != null) await controller.setDisplayName(name);
  }

  void _onTabSelected(BuildContext context, AppTab tab) {
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

  /// "+4.2KG THIS MONTH", or a prompt to log again when there is no trend yet.
  Widget _buildDeltaLabel(double? delta) {
    final bool hasDelta = delta != null;
    final String text = hasDelta
        ? 'delta_this_month'.tr(
            namedArgs: {
              'delta': '${delta >= 0 ? '+' : '-'}'
                  '${delta.abs().toStringAsFixed(1)}',
            },
          )
        : 'delta_unavailable'.tr();

    return Padding(
      padding: EdgeInsets.only(bottom: 2.h),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          color: hasDelta ? AppColors.primaryNeon : AppColors.textGray,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = ProfileScope.of(context);
    final UserProfile? profile = controller.profile;

    // The router guard keeps signed-out users off this screen; this only
    // covers the frame between signing out and the redirect landing.
    if (profile == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final NutritionPlan? plan = controller.nutritionPlan;
    final double? currentWeight = profile.currentWeightKg;

    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.profile,
        onTabSelected: (tab) => _onTabSelected(context, tab),
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
                  name: profile.displayName,
                  onSettingsTap: () =>
                      _openAccountSheet(context, controller, profile),
                ),
                SizedBox(height: 16.h),

                // --- WEIGHT PROGRESS ---
                _buildSectionTitle(
                  'weight_progress_title'.tr(),
                  trailing:
                      _buildDeltaLabel(profile.weightDelta(progressSpanInDays)),
                ),
                WeightProgressChart(
                  entries: profile.recentWeighIns(progressSpanInDays),
                  spanInDays: progressSpanInDays,
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
                          value: currentWeight?.toStringAsFixed(1) ?? '--',
                          unit: 'kg_unit'.tr(),
                          onEdit: () =>
                              _editCurrentWeight(context, controller, profile),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: EditableMetricCard(
                          label: 'target_weight_label'.tr(),
                          value: profile.targetWeightKg.toStringAsFixed(1),
                          unit: 'kg_unit'.tr(),
                          onEdit: () =>
                              _editTargetWeight(context, controller, profile),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12.h),

                // --- NUTRITION PLAN ---
                NutritionPlanCard(
                  dailyCalories: plan?.dailyGoalKcal,
                  weeklyGainKg: profile.bulkPlan.weeklyGainKg,
                  onRecalculate: () => context.push(AppRoutes.surplus),
                ),
                SizedBox(height: 20.h),

                // --- FOCUS AREAS ---
                _buildSectionTitle('focus_areas_title'.tr()),
                ...profile.focusAreas.map((area) => FocusAreaTile(area: area)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
