import 'package:bulkr/go_router/app_routes.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../state/profile_scope.dart';
import '../styles/app_color.dart';
import '../widgets/metric_edit_sheet.dart';
import '../widgets/standardmetriccard.dart';

class BaselineScreen extends StatefulWidget {
  const BaselineScreen({super.key});

  @override
  State<BaselineScreen> createState() => _BaselineScreenState();
}

class _BaselineScreenState extends State<BaselineScreen> {
  // Seeded from the signed-in athlete's profile, or these starting metrics
  // when they have not filled in a baseline yet.
  int _age = 28;
  int _height = 165;
  double _currentMass = 85.0;
  double _targetMass = 95.0;
  bool _seededFromProfile = false;

  double get _deltaMass => _targetMass - _currentMass;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededFromProfile) return;

    final profile = ProfileScope.read(context).profile;
    if (profile != null) {
      _age = profile.ageYears;
      _height = profile.heightCm;
      _currentMass = profile.currentWeightKg ?? _currentMass;
      _targetMass = profile.targetWeightKg;
    }
    _seededFromProfile = true;
  }

  Future<void> _editAge() async {
    final double? value = await MetricEditSheet.show(
      context,
      title: 'age_label'.tr(),
      initialValue: _age.toDouble(),
      unitLabel: 'yrs_unit'.tr(),
      min: 14,
      max: 100,
      decimals: 0,
    );
    if (value != null && mounted) setState(() => _age = value.round());
  }

  Future<void> _editHeight() async {
    final double? value = await MetricEditSheet.show(
      context,
      title: 'height_label'.tr(),
      initialValue: _height.toDouble(),
      unitLabel: 'cm_unit'.tr(),
      min: 120,
      max: 250,
      decimals: 0,
    );
    if (value != null && mounted) setState(() => _height = value.round());
  }

  Future<void> _editCurrentMass() async {
    final double? value = await MetricEditSheet.show(
      context,
      title: 'current_mass_label'.tr(),
      initialValue: _currentMass,
      unitLabel: 'kg_unit'.tr(),
      min: 30,
      max: 300,
    );
    if (value != null && mounted) setState(() => _currentMass = value);
  }

  Future<void> _editTargetMass() async {
    final double? value = await MetricEditSheet.show(
      context,
      title: 'target_mass_goal'.tr(),
      initialValue: _targetMass,
      unitLabel: 'kg_unit'.tr(),
      min: 30,
      max: 300,
    );
    if (value != null && mounted) setState(() => _targetMass = value);
  }

  /// Persists the baseline against the signed-in athlete, logging today's
  /// weight as their first weigh-in, then moves on to the activity step.
  Future<void> _continue() async {
    await ProfileScope.read(context).saveBaseline(
      ageYears: _age,
      heightCm: _height,
      currentWeightKg: _currentMass,
      targetWeightKg: _targetMass,
    );
    if (!mounted) return;
    context.push(AppRoutes.activityLevel);
  }

  // Reusing your progress indicator from previous screens
  Widget _buildProgressIndicator() {
    Widget dot(bool isActive) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 4.w),
        width: isActive ? 24.w : 6.w,
        height: 6.h,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryNeon : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(10.r),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(false),
        dot(true), // 2nd step: baseline metrics
        dot(false),
        dot(false),
        dot(false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
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
          child: Column(
            children: [
              SizedBox(height: 20.h,),
              _buildProgressIndicator(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  children: [
                    // --- HEADER ---
                    Text(
                      'baseline_title'.tr(),
                      style: GoogleFonts.anton(
                        fontSize: 30.sp, // Reduced from 36
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 8.h), // Reduced from 12
                    Text(
                      'baseline_subtitle'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 14.sp, // Reduced from 16
                        fontWeight: FontWeight.w500,
                        color: AppColors.offWhiteMuted,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 22.h),

                    // --- INPUT CARDS ---
                    StandardMetricCard(
                      label: 'age_label'.tr(),
                      value: _age.toString(),
                      unit: 'yrs_unit'.tr(),
                      onEdit: _editAge,
                    ),
                    StandardMetricCard(
                      label: 'height_label'.tr(),
                      value: _height.toString(),
                      unit: 'cm_unit'.tr(),
                      onEdit: _editHeight,
                    ),
                    InlineMetricCard(
                      label: 'current_mass_label'.tr(),
                      value: _currentMass.toStringAsFixed(1),
                      unit: 'kg_unit'.tr(),
                      onEdit: _editCurrentMass,
                    ),

                    // --- TARGET CARD ---
                    TargetMassCard(
                      targetValue: _targetMass.toStringAsFixed(1),
                      deltaValue: _deltaMass.toStringAsFixed(1),
                      isGain: _deltaMass > 0,
                      onEdit: _editTargetMass,
                    ),
                  ],
                ),
              ),

              // --- FOOTER SECTION ---
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 0.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _continue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryNeon,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'continue_btn'.tr(),
                              style: GoogleFonts.anton(
                                fontSize: 20.sp,
                                letterSpacing: 1,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Icon(Icons.arrow_forward, size: 20.sp),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}