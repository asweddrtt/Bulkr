import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/progress_stats.dart';
import '../core/unit_converter.dart';
import '../cubit/auth/auth_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../go_router/app_routes.dart';
import '../models/insight.dart';
import '../models/nutrition_plan.dart';
import '../models/user_profile.dart';
import '../models/weight_entry.dart';
import '../styles/app_color.dart';
import '../widgets/account_sheet.dart';
import '../widgets/animations/entrance.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/insight_list.dart';
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
              insights: context.read<ProfileCubit>().insights,
              historyErrorDetail: state.historyErrorDetail,
              isSaving: state.isSaving,
              onRefresh: () => context.read<ProfileCubit>().refresh(),
              onLogWeight: (kg) => context.read<ProfileCubit>().logWeight(kg),
              onEditTarget: (kg) =>
                  context.read<ProfileCubit>().updateTargetWeight(kg),
              onRecalculate: () => _openRecalculateSheet(context),
              onOpenAccount: () => _openAccountSheet(context),
            );
        }
      },
      ),
    );
  }

  /// Which account am I in, and how do I get out of it.
  ///
  /// Signing out is followed by an explicit navigation: the router's guard only
  /// runs on route changes, so without this the user would sit on a profile
  /// belonging to a session that no longer exists.
  Future<void> _openAccountSheet(BuildContext context) async {
    final AuthCubit auth = context.read<AuthCubit>();
    final GoRouter router = GoRouter.of(context);
    final String username =
        context.read<ProfileCubit>().state.profile?.username ?? '';

    await AccountSheet.show(
      context,
      email: auth.state.user?.email,
      username: username,
      onSignOut: () async {
        await auth.signOut();
        router.go(AppRoutes.welcome);
      },
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

    // BMR needs an age, and `date_of_birth` is nullable. Without it the sheet
    // could only offer a disabled button, so say what is missing instead.
    if (cubit.planForPace(cubit.suggestedWeeklyGainKg) == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A2A2A),
            content: Text(
              'recalculate_needs_biometrics'.tr(),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
            ),
          ),
        );
      return;
    }

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
    required this.insights,
    required this.historyErrorDetail,
    required this.isSaving,
    required this.onRefresh,
    required this.onLogWeight,
    required this.onEditTarget,
    required this.onRecalculate,
    required this.onOpenAccount,
  });

  final UserProfile profile;
  final List<WeightEntry> weightHistory;

  /// Trend figures over [weightHistory], calculated by the cubit.
  final ProgressStats progress;

  /// Today's advice, ordered most urgent first.
  final List<Insight> insights;

  /// Set when the weigh-in history could not be read at all.
  final String? historyErrorDetail;

  final bool isSaving;
  final Future<void> Function() onRefresh;
  final ValueChanged<double> onLogWeight;
  final ValueChanged<double> onEditTarget;
  final Future<void> Function() onRecalculate;
  final VoidCallback onOpenAccount;

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
                _buildWeightProgress(context),
                SizedBox(height: 16.h),
                _buildWeightCards(context),
                SizedBox(height: 16.h),
                _buildFocus(context),
                SizedBox(height: 16.h),
                _buildNutritionPlan(context),
                SizedBox(height: 16.h),
                _buildMacroTargets(),
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
          PressScale(
            child: GestureDetector(
              onTap: onOpenAccount,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(4.w),
                child: Icon(Icons.settings_outlined,
                    color: ProfileScreen.textMuted, size: 24.sp),
              ),
            ),
          ),
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

  Widget _buildWeightProgress(BuildContext context) {
    final remaining = profile.remainingKg;
    final prefix = remaining >= 0 ? '+' : '';

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
                Text(
                  '$prefix${_weight(remaining)} $_unitLabel '
                  '${'to_target'.tr()}',
                  style: GoogleFonts.inter(
                    color: ProfileScreen.accentColor,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
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
            if (historyErrorDetail != null) ...[
              SizedBox(height: 12.h),
              _buildHistoryError(historyErrorDetail!),
            ],
            SizedBox(height: 20.h),
            _buildLogWeightButton(context),
          ],
        ),
      ),
    );
  }

  /// An empty chart because the table refused to be read is a different thing
  /// from an empty chart because nothing has been logged. Say which.
  Widget _buildHistoryError(String detail) {
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A0A),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: const Color(0xFFFF9E3D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: const Color(0xFFFF9E3D), size: 16.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'history_unavailable'.tr(),
                  style: GoogleFonts.inter(
                    color: const Color(0xFFFF9E3D),
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  detail,
                  style: GoogleFonts.robotoMono(
                    color: const Color(0xFFFF9E3D),
                    fontSize: 10.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The primary action on this screen. The pencils on the cards do the same
  /// thing, but a weigh-in is the one thing the user comes back to do, so it
  /// gets a button of its own rather than hiding behind an icon.
  Widget _buildLogWeightButton(BuildContext context) {
    return PressScale(
      child: SizedBox(
        width: double.infinity,
        height: 46.h,
        child: ElevatedButton.icon(
          onPressed: isSaving
              ? null
              : () => _pickWeight(
                    context,
                    title: 'log_weight_title'.tr(),
                    currentKg: profile.currentWeightKg,
                    onPicked: onLogWeight,
                  ),
          style: ElevatedButton.styleFrom(
            backgroundColor: ProfileScreen.accentColor,
            foregroundColor: Colors.black,
            disabledBackgroundColor: ProfileScreen.borderColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4.r),
            ),
          ),
          icon: Icon(Icons.monitor_weight_outlined, size: 18.sp),
          label: Text(
            'log_weight_btn'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  /// Dynamic focus section: what to do today, from the user's own numbers.
  Widget _buildFocus(BuildContext context) {
    if (insights.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 2.w, bottom: 10.h),
          child: Text(
            'focus_title'.tr().toUpperCase(),
            style: GoogleFonts.anton(
              color: Colors.white,
              fontSize: 14.sp,
              letterSpacing: 1.5,
            ),
          ),
        ),
        InsightList(
          insights: insights,
          onAction: (action) => _runInsightAction(context, action),
        ),
      ],
    );
  }

  void _runInsightAction(BuildContext context, InsightAction action) {
    if (isSaving) return;

    switch (action) {
      case InsightAction.logWeight:
        _pickWeight(
          context,
          title: 'log_weight_title'.tr(),
          currentKg: profile.currentWeightKg,
          onPicked: onLogWeight,
        );
      case InsightAction.recalculate:
        onRecalculate();
      case InsightAction.none:
        break;
    }
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
              'nutrition_plan_desc'.tr(
                namedArgs: {'activity': profile.activityLevel.titleKey.tr()},
              ),
              style: GoogleFonts.inter(
                color: const Color(0xFFD1D5DB),
                fontSize: 13.sp,
                height: 1.5,
              ),
            ),
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
