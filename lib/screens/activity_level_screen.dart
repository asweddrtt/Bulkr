import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubit/onboarding/onboarding_cubit.dart';
import '../go_router/app_routes.dart';
import '../models/activity_level.dart';
import '../widgets/activity_level_card.dart';
import '../widgets/onboarding_scaffold.dart';

/// Step 3 — the TDEE multiplier.
///
/// Most people overestimate how active they are, so each card spells out what
/// the label means in concrete terms and shows the multiplier it applies.
class ActivityLevelScreen extends StatelessWidget {
  const ActivityLevelScreen({super.key});

  static const Map<ActivityLevel, IconData> _icons = {
    ActivityLevel.sedentary: Icons.chair_outlined,
    ActivityLevel.lightlyActive: Icons.directions_walk,
    ActivityLevel.moderatelyActive: Icons.directions_run,
    ActivityLevel.veryActive: Icons.fitness_center,
    ActivityLevel.extraActive: Icons.local_fire_department,
  };

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingCubit, OnboardingState>(
      builder: (context, state) {
        final cubit = context.read<OnboardingCubit>();

        return OnboardingScaffold(
          step: 3,
          title: 'activity_level_title'.tr(),
          subtitle: 'activity_level_subtitle'.tr(),
          centerHeader: true,
          onBack: () => context.pop(),
          onContinue: () => context.push(AppRoutes.targetPace),
          children: [
            // Driven off the enum so the list and the multipliers can't drift
            // apart — the previous hand-written list was missing Extra Active.
            for (final level in ActivityLevel.values)
              ActivityLevelCard(
                icon: _icons[level]!,
                title: level.titleKey.tr(),
                description: level.descriptionKey.tr(),
                multiplier: level.multiplier,
                isSelected: state.activityLevel == level,
                onTap: () => cubit.setActivityLevel(level),
              ),
          ],
        );
      },
    );
  }
}
