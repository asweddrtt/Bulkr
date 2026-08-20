import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/progress_stats.dart';
import '../core/unit_converter.dart';
import '../cubit/profile/profile_cubit.dart';
import '../models/nutrition_plan.dart';
import '../models/plan_breakdown.dart';
import '../models/user_profile.dart';
import '../models/weight_entry.dart';
import '../styles/app_color.dart';
import '../widgets/animations/entrance.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/recalculate_sheet.dart';
import '../widgets/weight_chart.dart';
import '../widgets/wheel_picker_sheet.dart';

/// Reads the signed-in user's row and renders it.
///
/// Split into a connected shell and a presentational view: the view takes a
/// [UserProfile] and knows nothing about where it came from, which keeps it
/// trivial to render for a test or a preview.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // Theme constants, kept as aliases of the shared palette so this screen
  // can't drift away from the rest of the app.
  static const Color bgColor = Color(0xFF121212);
  static const Color cardColor = Color(0xFF1A1A1A);
  static const Color accentColor = AppColors.primaryNeon;
  static const Color borderColor = AppColors.darkBorder;
  static const Color textMuted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    // A failed write leaves the loaded screen intact, so the only way the user
    // hears about it is here.
    return BlocListener<ProfileCubit, ProfileState>(
      listenWhen: (previous, current) =>
          current.actionErrorKey != null &&
          previous.actionErrorKey != current.actionErrorKey,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2A2A2A),
              content: Text(
                state.actionErrorKey!.tr(),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
              ),
            ),
          );
        context.read<ProfileCubit>().clearActionError();
      },
      child: BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        switch (state.status) {
          case ProfileStatus.initial:
          case ProfileStatus.loading:
            return const Center(
              child: CircularProgressIndicator(color: accentColor),
            );

          case ProfileStatus.missing:
            return _ProfileMessage(
              icon: Icons.person_off_outlined,
              message: 'profile_missing'.tr(),
              actionLabel: 'retry'.tr(),
              onAction: () => context.read<ProfileCubit>().load(),
            );

          case ProfileStatus.failure:
            return _ProfileMessage(
              icon: Icons.cloud_off_outlined,
              message: state.errorMessage ?? 'profile_load_failed'.tr(),
              actionLabel: 'retry'.tr(),
              onAction: () => context.read<ProfileCubit>().load(),
            );

          case ProfileStatus.ready:
            return _ProfileView(
              profile: state.profile!,
              weightHistory: state.weightHistory,
              progress: context.read<ProfileCubit>().progress!,
              breakdown: context.read<ProfileCubit>().planBreakdown,
              isSaving: state.isSaving,
              onRefresh: () => context.read<ProfileCubit>().refresh(),
              onLogWeight: (kg) => context.read<ProfileCubit>().logWeight(kg),
              onEditTarget: (kg) =>
                  context.read<ProfileCubit>().updateTargetWeight(kg),
              onRecalculate: () => _openRecalculateSheet(context),
            );
        }
      },
      ),
    );
  }

  /// Opens the recalculation sheet and saves whatever it resolves with.
  ///
  /// The sheet is handed the cubit's calculator rather than a finished plan, so
  /// the numbers track the pace slider without a round trip.
  Future<void> _openRecalculateSheet(BuildContext context) async {
    final ProfileCubit cubit = context.read<ProfileCubit>();
    final UserProfile? profile = cubit.state.profile;
    if (profile == null) return;

    final NutritionPlan? plan = await RecalculateSheet.show(
      context,
      initialWeeklyGainKg: cubit.suggestedWeeklyGainKg,
      currentCalories: profile.dailyCalorieTarget,
      units: profile.units,
      planForPace: cubit.planForPace,
      minWeeklyGainKg: ProfileCubit.minWeeklyGainKg,
      maxWeeklyGainKg: ProfileCubit.maxWeeklyGainKg,
    );

    if (plan != null) await cubit.applyPlan(plan);
  }
}

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    required this.profile,
    required this.weightHistory,
    required this.progress,
    required this.breakdown,
    required this.isSaving,
    required this.onRefresh,
    required this.onLogWeight,
    required this.onEditTarget,
    required this.onRecalculate,
  });

  final UserProfile profile;
  final List<WeightEntry> weightHistory;

  /// Trend figures over [weightHistory], calculated by the cubit.
  final ProgressStats progress;

  /// What the stored calorie target is made of. Null when the row has no
  /// date of birth, without which BMR cannot be computed.
  final PlanBreakdown? breakdown;

  final bool isSaving;
  final Future<void> Function() onRefresh;
  final ValueChanged<double> onLogWeight;
  final ValueChanged<double> onEditTarget;
  final Future<void> Function() onRecalculate;

  bool get _isMetric => profile.units.isMetric;

  String get _unitLabel =>
      _isMetric ? 'kg_unit'.tr().toLowerCase() : 'lb_unit'.tr().toLowerCase();

  /// Weights are stored in kilograms; the display unit is the user's choice
  /// from onboarding.
  String _weight(double kg) => _isMetric
      ? kg.toStringAsFixed(1)
      : UnitConverter.kgToLb(kg).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: ProfileScreen.accentColor,
            backgroundColor: ProfileScreen.cardColor,
            child: ListView(
              padding: EdgeInsets.all(16.w),
              children: staggered([
                _buildWeightProgress(),
                SizedBox(height: 16.h),
                _buildWeightCards(context),
                SizedBox(height: 16.h),
                _buildNutritionPlan(context),
                SizedBox(height: 16.h),
                _buildMacroTargets(),
                SizedBox(height: 16.h),
                _buildBodyStats(),
                SizedBox(height: 32.h),
              ]),
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
        border: Border(bottom: BorderSide(color: ProfileScreen.borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: ProfileScreen.accentColor, width: 2.w),
                  ),
                  child: CircleAvatar(
                    radius: 18.r,
                    backgroundColor: ProfileScreen.borderColor,
                    backgroundImage: profile.avatarUrl == null
                        ? null
                        : NetworkImage(profile.avatarUrl!),
                    child: profile.avatarUrl == null
                        ? Icon(Icons.person,
                            color: ProfileScreen.textMuted, size: 20.sp)
                        : null,
                  ),
                ),
                SizedBox(width: 12.w),
                // Flexible: a long OAuth display name would otherwise overflow
                // the row and paint the yellow-and-black stripes.
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profile.preferredName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.anton(
                          color: Colors.white,
                          fontSize: 20.sp,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        '@${profile.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: ProfileScreen.textMuted,
                          fontSize: 11.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.settings_outlined,
              color: ProfileScreen.textMuted, size: 24.sp),
        ],
      ),
    );
  }

  Widget _buildBorderedCard({required Widget child, Color? fill}) {
    return Container(
      padding: EdgeInsets.all(2.w),
      decoration: BoxDecoration(
        color: ProfileScreen.bgColor,
        border: Border.all(color: ProfileScreen.borderColor, width: 1.5.w),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: fill ?? ProfileScreen.cardColor,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: child,
      ),
    );
  }

  Widget _buildWeightProgress() {
    return _buildBorderedCard(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'weight_progress'.tr(),
                  style: GoogleFonts.anton(
                    color: Colors.white,
                    fontSize: 14.sp,
                    letterSpacing: 1.5,
                  ),
                ),
                _buildMonthlyChange(),
              ],
            ),
            SizedBox(height: 24.h),
            WeightChart(entries: weightHistory, units: profile.units),
            SizedBox(height: 12.h),
            if (weightHistory.length >= 2)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_chartDate(weightHistory.first.loggedAt),
                      style: _chartLabelStyle),
                  Text('today'.tr(), style: _chartLabelStyle),
                ],
              ),
            SizedBox(height: 20.h),
            _buildTargetProgressBar(),
            SizedBox(height: 20.h),
            _buildTrendStats(),
          ],
        ),
      ),
    );
  }

  /// The headline trend: change over the last 30 days. Stays quiet rather than
  /// printing 0.0 when there is only one weigh-in to go on.
  Widget _buildMonthlyChange() {
    final monthly = progress.monthlyChangeKg;
    if (monthly == null) {
      return Text(
        'no_trend_yet'.tr(),
        style: GoogleFonts.inter(
          color: ProfileScreen.textMuted,
          fontSize: 10.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      );
    }

    return Text(
      'change_this_month'.tr(
        namedArgs: {
          'delta': '${monthly >= 0 ? '+' : '-'}${_weight(monthly.abs())}',
          'unit': _unitLabel,
        },
      ),
      style: GoogleFonts.inter(
        color: monthly >= 0
            ? ProfileScreen.accentColor
            : const Color(0xFFFF9E3D),
        fontSize: 10.sp,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }

  /// How far along the run from the starting weigh-in to the target.
  Widget _buildTargetProgressBar() {
    final fraction = progress.fractionToTarget;
    final reached = progress.isTargetReached;
    final percent = fraction == null ? null : (fraction * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              reached ? 'target_reached'.tr() : 'progress_to_target'.tr(),
              style: GoogleFonts.inter(
                color: ProfileScreen.textMuted,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              percent == null ? '--' : '$percent%',
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 13.sp,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(3.r),
          child: Container(
            height: 6.h,
            color: ProfileScreen.borderColor,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction ?? 0,
              child: Container(color: ProfileScreen.accentColor),
            ),
          ),
        ),
      ],
    );
  }

  /// Four figures the raw chart can't state outright.
  Widget _buildTrendStats() {
    final rate = progress.weeklyRateKg;
    final total = progress.totalChangeKg;
    final remaining = progress.remainingKg;
    final eta = progress.projectedTargetDate;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildStatTile(
                'stat_total_change'.tr(),
                total == null
                    ? null
                    : '${total >= 0 ? '+' : '-'}${_weight(total.abs())}',
                total == null ? null : _unitLabel,
              ),
            ),
            Expanded(
              child: _buildStatTile(
                'stat_weekly_rate'.tr(),
                rate == null
                    ? null
                    : '${rate >= 0 ? '+' : '-'}${_weight(rate.abs())}',
                rate == null ? null : '$_unitLabel${'per_week_short'.tr()}',
              ),
            ),
          ],
        ),
        SizedBox(height: 16.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildStatTile(
                'to_target'.tr(),
                remaining == null || progress.isTargetReached
                    ? null
                    : _weight(remaining.abs()),
                remaining == null || progress.isTargetReached
                    ? null
                    : _unitLabel,
              ),
            ),
            Expanded(
              child: _buildStatTile(
                'stat_projected_date'.tr(),
                eta == null ? null : DateFormat.MMMd().format(eta),
                eta == null ? null : DateFormat.y().format(eta),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// A single figure. [value] of null renders a dash — the honest answer when
  /// there isn't enough history to compute it yet.
  Widget _buildStatTile(String label, String? value, String? unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            color: ProfileScreen.textMuted,
            fontSize: 9.sp,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: 4.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value ?? '--',
              style: GoogleFonts.anton(
                color: value == null ? ProfileScreen.textMuted : Colors.white,
                fontSize: 18.sp,
                letterSpacing: 0.5,
              ),
            ),
            if (unit != null) ...[
              SizedBox(width: 4.w),
              Text(
                unit,
                style: GoogleFonts.inter(
                  color: ProfileScreen.textMuted,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  static String _chartDate(DateTime date) => DateFormat.MMMd().format(date);

  static TextStyle get _chartLabelStyle => GoogleFonts.inter(
        color: ProfileScreen.textMuted,
        fontSize: 10.sp,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      );

  Widget _buildWeightCards(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _buildBorderedCard(
            child: _buildSingleWeightCard(
              'current_weight'.tr(),
              _weight(profile.currentWeightKg),
              caption: _lastLoggedCaption(),
              onEdit: () => _pickWeight(
                context,
                title: 'log_weight_title'.tr(),
                currentKg: profile.currentWeightKg,
                onPicked: onLogWeight,
              ),
            ),
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: _buildBorderedCard(
            child: _buildSingleWeightCard(
              'target_weight'.tr(),
              _weight(profile.targetWeightKg),
              onEdit: () => _pickWeight(
                context,
                title: 'edit_target_title'.tr(),
                currentKg: profile.targetWeightKg,
                onPicked: onEditTarget,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// When the last weigh-in was, so a stale headline number says so itself.
  String? _lastLoggedCaption() {
    final days = progress.daysSinceLastWeighIn;
    if (days == null) return null;
    if (days <= 0) return 'logged_today'.tr();
    if (days == 1) return 'logged_yesterday'.tr();
    return 'logged_days_ago'.tr(namedArgs: {'days': '$days'});
  }

  /// Wheel picker over the user's display unit, resolved back to kilograms —
  /// the only unit the database stores.
  Future<void> _pickWeight(
    BuildContext context, {
    required String title,
    required double currentKg,
    required ValueChanged<double> onPicked,
  }) async {
    final bool metric = _isMetric;
    final double initial =
        metric ? currentKg : UnitConverter.kgToLb(currentKg);

    final double? picked = await WheelPickerSheet.showValue(
      context: context,
      title: title,
      initialValue: initial,
      min: metric ? 35 : UnitConverter.kgToLb(35).roundToDouble(),
      max: metric ? 250 : UnitConverter.kgToLb(250).roundToDouble(),
      step: metric ? 0.1 : 0.2,
      unitLabel: _unitLabel,
      decimals: 1,
    );
    if (picked == null) return;

    onPicked(metric ? picked : UnitConverter.lbToKg(picked));
  }

  Widget _buildSingleWeightCard(
    String label,
    String value, {
    String? caption,
    VoidCallback? onEdit,
  }) {
    return PressScale(
      child: GestureDetector(
        onTap: isSaving ? null : onEdit,
        behavior: HitTestBehavior.opaque,
        child: _buildWeightCardBody(label, value, caption, onEdit != null),
      ),
    );
  }

  Widget _buildWeightCardBody(
    String label,
    String value,
    String? caption,
    bool isEditable,
  ) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: ProfileScreen.textMuted,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    height: 1.4,
                  ),
                ),
              ),
              if (isEditable)
                Icon(Icons.edit,
                    color: ProfileScreen.textMuted, size: 14.sp),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.anton(
                    color: Colors.white,
                    fontSize: 34.sp,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              Text(
                _unitLabel,
                style: GoogleFonts.inter(
                  color: ProfileScreen.textMuted,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          if (caption != null) ...[
            SizedBox(height: 6.h),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: ProfileScreen.textMuted,
                fontSize: 9.sp,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNutritionPlan(BuildContext context) {
    return _buildBorderedCard(
      child: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'nutrition_plan'.tr(),
              style: GoogleFonts.inter(
                color: ProfileScreen.textMuted,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'current_daily_goal'.tr(
                namedArgs: {
                  'calories':
                      NumberFormat('#,###').format(profile.dailyCalorieTarget),
                },
              ),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 18.sp,
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              _planDescription(),
              style: GoogleFonts.inter(
                color: const Color(0xFFD1D5DB),
                fontSize: 13.sp,
                height: 1.5,
              ),
            ),
            if (breakdown != null) ...[
              SizedBox(height: 16.h),
              _buildPlanBreakdown(breakdown!),
            ],
            SizedBox(height: 20.h),
            PressScale(
              child: SizedBox(
                width: double.infinity,
                height: 48.h,
                child: OutlinedButton(
                  onPressed: isSaving ? null : () => onRecalculate(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: ProfileScreen.accentColor, width: 2.w),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                  child: Text(
                    'recalculate'.tr(),
                    style: GoogleFonts.inter(
                      color: ProfileScreen.accentColor,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// States the pace the stored target actually buys, recovered from the
  /// target itself since the pace is never persisted. Falls back to the
  /// activity-only wording when there is no date of birth to compute BMR from.
  String _planDescription() {
    final PlanBreakdown? plan = breakdown;
    if (plan == null || plan.surplus <= 0) {
      return 'nutrition_plan_desc'.tr(
        namedArgs: {'activity': profile.activityLevel.titleKey.tr()},
      );
    }

    return 'nutrition_plan_desc_pace'.tr(
      namedArgs: {
        'activity': profile.activityLevel.titleKey.tr(),
        'pace': _weight(plan.impliedWeeklyGainKg),
        'unit': _unitLabel,
      },
    );
  }

  /// Splits the stored target into BMR, maintenance and the surplus on top, so
  /// the number on the card stops being a figure the user has to take on trust.
  Widget _buildPlanBreakdown(PlanBreakdown plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBreakdownRow('plan_bmr'.tr(), plan.bmr),
        SizedBox(height: 8.h),
        _buildBreakdownRow('plan_maintenance'.tr(), plan.maintenance),
        SizedBox(height: 8.h),
        _buildBreakdownRow(
          'plan_surplus'.tr(),
          plan.surplus,
          signed: true,
          accent: plan.isStale
              ? const Color(0xFFFF5722)
              : ProfileScreen.accentColor,
        ),
        if (plan.isStale) ...[
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: const Color(0xFFFF5722), size: 14.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'plan_stale_notice'.tr(),
                  style: GoogleFonts.inter(
                    color: const Color(0xFFFF5722),
                    fontSize: 11.sp,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildBreakdownRow(
    String label,
    int kcal, {
    bool signed = false,
    Color? accent,
  }) {
    final String prefix = signed && kcal > 0 ? '+' : '';

    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            color: ProfileScreen.textMuted,
            fontSize: 10.sp,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Container(height: 1.h, color: ProfileScreen.borderColor),
        ),
        SizedBox(width: 8.w),
        Text(
          '$prefix${NumberFormat('#,###').format(kcal)}',
          style: GoogleFonts.anton(
            color: accent ?? Colors.white,
            fontSize: 13.sp,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  /// Replaces the mocked "focus areas" list. Those values were invented —
  /// there's no workout data in the schema to drive them — whereas these
  /// macro targets are the ones actually stored on the user's row.
  Widget _buildMacroTargets() {
    return _buildBorderedCard(
      fill: ProfileScreen.bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 8.h),
            child: Text(
              'macros_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 14.sp,
                letterSpacing: 1.5,
              ),
            ),
          ),
          _buildMacroRow('macro_protein'.tr(), profile.proteinTargetG,
              AppColors.primaryNeon),
          SizedBox(height: 2.h),
          _buildMacroRow(
              'macro_carbs'.tr(), profile.carbsTargetG, const Color(0xFF6FD3FF)),
          SizedBox(height: 2.h),
          _buildMacroRow(
              'macro_fat'.tr(), profile.fatTargetG, const Color(0xFFFF9E3D)),
          SizedBox(height: 2.h),
        ],
      ),
    );
  }

  Widget _buildMacroRow(String label, int grams, Color accent) {
    return Container(
      color: ProfileScreen.cardColor,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Row(
        children: [
          Container(width: 4.w, height: 16.h, color: accent),
          SizedBox(width: 12.w),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: const Color(0xFFD1D5DB),
              fontSize: 11.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          Text(
            '${grams}g',
            style: GoogleFonts.anton(
              color: Colors.white,
              fontSize: 14.sp,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Everything else already on the user's row that had nowhere to be seen:
  /// height, age, gender, the multiplier behind their target, and BMI.
  Widget _buildBodyStats() {
    final int? age = profile.age;
    final double? bmi = progress.bmi(profile.heightCm);

    return _buildBorderedCard(
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'body_stats_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 14.sp,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 16.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildStatTile(
                    'height_label'.tr(),
                    _heightValue(),
                    _isMetric ? 'cm_unit'.tr().toLowerCase() : null,
                  ),
                ),
                Expanded(
                  child: _buildStatTile(
                    'stat_age'.tr(),
                    age?.toString(),
                    age == null ? null : 'stat_years_short'.tr(),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildStatTile(
                    'gender_label'.tr(),
                    profile.gender?.labelKey.tr(),
                    null,
                  ),
                ),
                Expanded(
                  child: _buildStatTile(
                    'stat_bmi'.tr(),
                    bmi?.toStringAsFixed(1),
                    null,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            _buildStatTile(
              'stat_activity'.tr(),
              profile.activityLevel.titleKey.tr(),
              '${profile.activityLevel.multiplier}x',
            ),
          ],
        ),
      ),
    );
  }

  /// Height in the user's own units: centimetres, or feet and inches.
  String _heightValue() {
    if (profile.heightCm <= 0) return '--';
    if (_isMetric) return profile.heightCm.round().toString();

    final feetInches = UnitConverter.cmToFeetInches(profile.heightCm);
    return "${feetInches.feet}'${feetInches.inches}\"";
  }
}

class _ProfileMessage extends StatelessWidget {
  const _ProfileMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40.sp, color: ProfileScreen.textMuted),
            SizedBox(height: 16.h),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                color: ProfileScreen.textMuted,
                height: 1.5,
              ),
            ),
            SizedBox(height: 20.h),
            PressScale(
              child: OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: ProfileScreen.accentColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                child: Text(
                  actionLabel.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: ProfileScreen.accentColor,
                    fontSize: 12.sp,
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
}
