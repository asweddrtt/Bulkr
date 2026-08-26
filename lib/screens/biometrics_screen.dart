import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/unit_converter.dart';
import '../cubit/onboarding/onboarding_cubit.dart';
import '../data/username_generator.dart';
import '../go_router/app_routes.dart';
import '../styles/app_color.dart';
import '../widgets/gender_selector.dart';
import '../widgets/metric_card.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/unit_toggle.dart';
import '../widgets/wheel_picker_sheet.dart';

/// Step 2 — the physical data the calorie maths runs on, grouped so it reads
/// as one conceptual step rather than four separate questions.
class BiometricsScreen extends StatefulWidget {
  const BiometricsScreen({super.key});

  @override
  State<BiometricsScreen> createState() => _BiometricsScreenState();
}

class _BiometricsScreenState extends State<BiometricsScreen> {
  late final TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    // Pre-filled from the OAuth identity. `users.username` is NOT NULL UNIQUE
    // but no provider supplies one, so we propose a handle and let the user
    // overwrite it rather than adding a whole screen for it.
    _usernameController = TextEditingController(
      text: context.read<OnboardingCubit>().state.username,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingCubit, OnboardingState>(
      builder: (context, state) {
        final cubit = context.read<OnboardingCubit>();
        final isMetric = state.unitSystem.isMetric;

        return OnboardingScaffold(
          step: 2,
          title: 'baseline_title'.tr(),
          subtitle: 'baseline_subtitle'.tr(),
          onContinue: state.isBiometricsComplete
              ? () => context.push(AppRoutes.activityLevel)
              : null,
          children: [
            UnitToggle(
              value: state.unitSystem,
              onChanged: cubit.setUnitSystem,
            ),
            SizedBox(height: 20.h),

            _FieldLabel(text: 'username_label'.tr()),
            SizedBox(height: 8.h),
            _UsernameField(
              controller: _usernameController,
              onChanged: cubit.setUsername,
              value: state.username,
              availability: state.usernameAvailability,
            ),
            SizedBox(height: 20.h),

            _FieldLabel(text: 'gender_label'.tr()),
            SizedBox(height: 8.h),
            GenderSelector(value: state.gender, onChanged: cubit.setGender),
            SizedBox(height: 20.h),

            // Date of birth rather than age: age drifts, a birthday doesn't,
            // and the engine derives the age it needs at calculation time.
            MetricCard(
              label: 'dob_label'.tr(),
              value: state.dateOfBirth == null
                  ? 'dob_placeholder'.tr()
                  : DateFormat.yMMMd().format(state.dateOfBirth!),
              unit: state.dateOfBirth == null
                  ? ''
                  : 'age_years'.tr(namedArgs: {'age': '${state.age}'}),
              isPlaceholder: state.dateOfBirth == null,
              onTap: () => _pickDateOfBirth(context, state, cubit),
            ),

            MetricCard(
              label: 'height_label'.tr(),
              value: _heightValue(state.heightCm, isMetric),
              unit: isMetric ? 'cm_unit'.tr() : '',
              onTap: () => _pickHeight(context, state, cubit),
            ),

            MetricCard(
              label: 'current_mass_label'.tr(),
              value: _weightValue(state.currentWeightKg, isMetric),
              unit: isMetric ? 'kg_unit'.tr() : 'lb_unit'.tr(),
              onTap: () => _pickWeight(context, state, cubit),
            ),

            SizedBox(height: 4.h),
            Text(
              'baseline_footnote'.tr(),
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                height: 1.4,
                color: AppColors.textGray,
              ),
            ),
          ],
        );
      },
    );
  }

  static String _heightValue(double cm, bool isMetric) {
    if (isMetric) return cm.round().toString();
    final imperial = UnitConverter.cmToFeetInches(cm);
    return "${imperial.feet}' ${imperial.inches}\"";
  }

  static String _weightValue(double kg, bool isMetric) => isMetric
      ? kg.toStringAsFixed(1)
      : UnitConverter.kgToLb(kg).toStringAsFixed(1);

  Future<void> _pickDateOfBirth(
    BuildContext context,
    OnboardingState state,
    OnboardingCubit cubit,
  ) async {
    final now = DateTime.now();

    // 13 is the floor most app stores expect; 100 is a generous ceiling.
    final earliest = DateTime(now.year - 100, now.month, now.day);
    final latest = DateTime(now.year - 13, now.month, now.day);
    final initial = state.dateOfBirth ?? DateTime(now.year - 25, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: latest,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primaryNeon,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF141414)),
        ),
        child: child!,
      ),
    );

    if (picked != null) cubit.setDateOfBirth(picked);
  }

  Future<void> _pickHeight(
    BuildContext context,
    OnboardingState state,
    OnboardingCubit cubit,
  ) async {
    final result = state.unitSystem.isMetric
        ? await WheelPickerSheet.showValue(
            context: context,
            title: 'height_label'.tr(),
            initialValue: state.heightCm,
            min: 120,
            max: 230,
            step: 1,
            unitLabel: 'cm_unit'.tr().toLowerCase(),
          )
        : await WheelPickerSheet.showFeetInches(
            context: context,
            title: 'height_label'.tr(),
            initialCm: state.heightCm,
          );

    if (result != null) cubit.setHeightCm(result);
  }

  Future<void> _pickWeight(
    BuildContext context,
    OnboardingState state,
    OnboardingCubit cubit,
  ) async {
    final isMetric = state.unitSystem.isMetric;

    final result = await WheelPickerSheet.showValue(
      context: context,
      title: 'current_mass_label'.tr(),
      initialValue: isMetric
          ? state.currentWeightKg
          : UnitConverter.kgToLb(state.currentWeightKg),
      min: isMetric ? 35 : 77,
      max: isMetric ? 250 : 550,
      step: isMetric ? 0.5 : 1,
      decimals: isMetric ? 1 : 0,
      unitLabel: isMetric ? 'kg_unit'.tr().toLowerCase() : 'lb_unit'.tr().toLowerCase(),
    );

    if (result == null) return;
    // Always stored metric; the toggle only decides how it's shown.
    cubit.setCurrentWeightKg(isMetric ? result : UnitConverter.lbToKg(result));
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 10.sp,
        fontWeight: FontWeight.w600,
        color: AppColors.offWhiteMuted,
        letterSpacing: 2,
      ),
    );
  }
}

class _UsernameField extends StatelessWidget {
  const _UsernameField({
    required this.controller,
    required this.onChanged,
    required this.value,
    required this.availability,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String value;
  final UsernameAvailability availability;

  static const Color _errorColor = Color(0xFFFF5722);

  bool get _isMalformed => value.isNotEmpty && !UsernameGenerator.isValid(value);

  bool get _isTaken => availability == UsernameAvailability.taken;

  bool get _hasProblem => _isMalformed || _isTaken;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(4.r),
            border: Border.all(
              color: _hasProblem ? _errorColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  maxLength: UsernameGenerator.maxLength,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: GoogleFonts.anton(
                    fontSize: 20.sp,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    prefixText: '@',
                    prefixStyle: GoogleFonts.anton(
                      fontSize: 20.sp,
                      color: AppColors.primaryNeon,
                    ),
                    hintText: 'username_hint'.tr(),
                    hintStyle: GoogleFonts.anton(
                      fontSize: 20.sp,
                      color: AppColors.textGray,
                    ),
                  ),
                ),
              ),
              _StatusGlyph(availability: availability, isMalformed: _isMalformed),
            ],
          ),
        ),
        if (_hasProblem) ...[
          SizedBox(height: 6.h),
          Text(
            _isMalformed ? 'username_invalid'.tr() : 'username_taken_error'.tr(),
            style: GoogleFonts.inter(fontSize: 11.sp, color: _errorColor),
          ),
        ],
      ],
    );
  }
}

class _StatusGlyph extends StatelessWidget {
  const _StatusGlyph({required this.availability, required this.isMalformed});

  final UsernameAvailability availability;
  final bool isMalformed;

  @override
  Widget build(BuildContext context) {
    if (isMalformed) {
      return Icon(Icons.error_outline,
          size: 18.sp, color: _UsernameField._errorColor);
    }

    switch (availability) {
      case UsernameAvailability.checking:
        return SizedBox(
          height: 14.sp,
          width: 14.sp,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(AppColors.offWhiteMuted),
          ),
        );
      case UsernameAvailability.available:
        return Icon(Icons.check_circle,
            size: 18.sp, color: AppColors.primaryNeon);
      case UsernameAvailability.taken:
        return Icon(Icons.cancel_outlined,
            size: 18.sp, color: _UsernameField._errorColor);
      case UsernameAvailability.unknown:
        return const SizedBox.shrink();
    }
  }
}
