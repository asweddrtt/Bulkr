import 'package:equatable/equatable.dart';

/// What the stored `daily_calorie_target` is actually made of.
///
/// The weekly pace chosen during onboarding is not persisted (there is no
/// column for it), so it is recovered here instead: recompute maintenance at
/// the user's current weight and whatever the stored target sits above it is
/// the surplus they are running, and therefore the pace it buys.
class PlanBreakdown extends Equatable {
  const PlanBreakdown({
    required this.bmr,
    required this.maintenance,
    required this.surplus,
    required this.calories,
    required this.impliedWeeklyGainKg,
  });

  final int bmr;
  final int maintenance;

  /// Stored target minus recomputed maintenance. Negative if the user has
  /// gained enough that their old target is now a deficit.
  final int surplus;

  /// The stored `daily_calorie_target` this was decomposed from.
  final int calories;

  final double impliedWeeklyGainKg;

  /// True once maintenance has caught up with the target, so the plan no
  /// longer buys any gain and is worth recalculating.
  bool get isStale => surplus <= 0;

  @override
  List<Object?> get props => [
        bmr,
        maintenance,
        surplus,
        calories,
        impliedWeeklyGainKg,
      ];
}
