import 'package:bulkr/core/calorie_engine.dart';
import 'package:bulkr/core/insight_engine.dart';
import 'package:bulkr/core/progress_stats.dart';
import 'package:bulkr/models/activity_level.dart';
import 'package:bulkr/models/gender.dart';
import 'package:bulkr/models/insight.dart';
import 'package:bulkr/models/plan_breakdown.dart';
import 'package:bulkr/models/unit_system.dart';
import 'package:bulkr/models/user_profile.dart';
import 'package:bulkr/models/weight_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const InsightEngine engine = InsightEngine();
  final DateTime now = DateTime(2026, 8, 20, 9);

  UserProfile profile({
    double currentWeightKg = 88.5,
    double targetWeightKg = 95,
    int calories = 3400,
    int protein = 159,
    ActivityLevel activity = ActivityLevel.moderatelyActive,
    UnitSystem units = UnitSystem.metric,
  }) {
    return UserProfile(
      id: 'u1',
      username: 'maxgains',
      gender: Gender.male,
      dateOfBirth: DateTime(1996, 1, 1),
      heightCm: 180,
      currentWeightKg: currentWeightKg,
      targetWeightKg: targetWeightKg,
      activityLevel: activity,
      units: units,
      dailyCalorieTarget: calories,
      proteinTargetG: protein,
      carbsTargetG: 400,
      fatTargetG: 94,
      onboardingCompleted: true,
    );
  }

  WeightEntry entry(int daysAgo, double kg) => WeightEntry(
        weightKg: kg,
        loggedAt: now.subtract(Duration(days: daysAgo)),
      );

  ProgressStats stats(List<WeightEntry> history, {double target = 95}) =>
      ProgressStats(history: history, targetWeightKg: target, asOf: now);

  PlanBreakdown breakdown(int storedCalories, {double weightKg = 88.5}) =>
      CalorieEngine.breakdown(
        gender: Gender.male,
        weightKg: weightKg,
        heightCm: 180,
        age: 30,
        activityLevel: ActivityLevel.moderatelyActive,
        storedCalories: storedCalories,
      );

  List<String> idsFor({
    required UserProfile user,
    required ProgressStats progress,
    PlanBreakdown? plan,
    int limit = 4,
  }) {
    return engine
        .build(
          profile: user,
          progress: progress,
          breakdown: plan,
          asOf: now,
          limit: limit,
        )
        .map((insight) => insight.id)
        .toList();
  }

  group('what needs acting on comes first', () {
    test('asks for a first weigh-in when there is no history', () {
      final ids = idsFor(user: profile(), progress: stats(const []));

      expect(ids.first, 'weigh_in_first');
    });

    test('chases a weigh-in once it has gone stale', () {
      final ids = idsFor(
        user: profile(),
        progress: stats([entry(20, 86.0), entry(6, 88.5)]),
      );

      expect(ids.first, 'weigh_in_stale');
    });

    test('does not chase a weigh-in logged today', () {
      final ids = idsFor(
        user: profile(),
        progress: stats([entry(14, 87.0), entry(0, 88.5)]),
      );

      expect(ids, isNot(contains('weigh_in_stale')));
    });

    test('flags a plan maintenance has caught up with', () {
      final ids = idsFor(
        user: profile(calories: 2500),
        progress: stats([entry(14, 87.0), entry(0, 88.5)]),
        plan: breakdown(2500),
      );

      expect(ids, contains('plan_stale'));
    });

    test('celebrates a target that has been reached', () {
      final ids = idsFor(
        user: profile(currentWeightKg: 95.4),
        progress: stats([entry(30, 88.0), entry(0, 95.4)]),
        plan: breakdown(3400, weightKg: 95.4),
      );

      expect(ids, contains('target_reached'));
      // Pace advice is irrelevant once the goal is met.
      expect(ids, isNot(contains('pace_fast')));
    });
  });

  group('pace advice', () {
    test('warns above the lean bulk ceiling', () {
      // +1.2 kg/week.
      final ids = idsFor(
        user: profile(),
        progress: stats([entry(14, 86.1), entry(0, 88.5)]),
        plan: breakdown(3400),
      );

      expect(ids, contains('pace_fast'));
    });

    test('calls out a scale that has not moved', () {
      final ids = idsFor(
        user: profile(),
        progress: stats([entry(14, 88.5), entry(0, 88.5)]),
        plan: breakdown(3400),
      );

      expect(ids, contains('pace_stalled'));
    });

    test('calls out gaining well under the target pace', () {
      // Target pace is ~0.46 kg/week; this is 0.1.
      final ids = idsFor(
        user: profile(),
        progress: stats([entry(14, 88.3), entry(0, 88.5)]),
        plan: breakdown(3400),
      );

      expect(ids, contains('pace_behind'));
    });

    test('stays quiet when the pace is on track', () {
      // ~0.5 kg/week against a ~0.46 target.
      final ids = idsFor(
        user: profile(),
        progress: stats([entry(14, 87.5), entry(0, 88.5)]),
        plan: breakdown(3400),
      );

      expect(ids, isNot(contains('pace_fast')));
      expect(ids, isNot(contains('pace_behind')));
      expect(ids, isNot(contains('pace_stalled')));
    });
  });

  group('everyday advice', () {
    test('fills the remaining slots with habits', () {
      final result = engine.build(
        profile: profile(),
        progress: stats([entry(14, 87.5), entry(0, 88.5)]),
        breakdown: breakdown(3400),
        asOf: now,
      );

      expect(result, hasLength(4));
      expect(result.every((i) => i.titleKey.isNotEmpty), isTrue);
    });

    test('personalises hydration to bodyweight', () {
      final result = engine.build(
        profile: profile(),
        progress: stats([entry(14, 87.5), entry(0, 88.5)]),
        asOf: now,
        limit: 10,
      );

      final water = result.firstWhere((i) => i.id == 'hydration');
      // 88.5 kg * 35 ml = 3.1 L, about 12 glasses of 250 ml
      expect(water.args['litres'], '3.1');
      expect(water.args['glasses'], '12');
      expect(water.kind, InsightKind.hydration);
    });

    test('states hydration in ounces for an imperial user', () {
      final result = engine.build(
        profile: profile(units: UnitSystem.imperial),
        progress: stats([entry(14, 87.5), entry(0, 88.5)]),
        asOf: now,
        limit: 10,
      );

      final water = result.firstWhere((i) => i.id == 'hydration');
      // 3097.5 ml is about 105 fl oz, or 13 eight-ounce glasses.
      expect(water.titleKey, 'insight_water_title_oz');
      expect(water.args['ounces'], '105');
      expect(water.args['glasses'], '13');
      expect(water.args.containsKey('litres'), isFalse);
    });

    test('splits the stored protein target across meals', () {
      final result = engine.build(
        profile: profile(protein: 160),
        progress: stats([entry(0, 88.5)]),
        asOf: now,
        limit: 10,
      );

      final protein = result.firstWhere((i) => i.id == 'protein');
      expect(protein.args['grams'], '160');
      expect(protein.args['perMeal'], '40');
    });

    test('nudges a sedentary user to move', () {
      final ids = idsFor(
        user: profile(activity: ActivityLevel.sedentary),
        progress: stats([entry(14, 87.5), entry(0, 88.5)]),
        limit: 10,
      );

      expect(ids, contains('move_more'));
    });

    test('rotates the habit advice by day, without repeating', () {
      ProgressStats onTrack() => stats([entry(14, 87.5), entry(0, 88.5)]);

      List<String> onDay(DateTime day) => engine
          .build(
            profile: profile(),
            progress: ProgressStats(
              history: [entry(14, 87.5), entry(0, 88.5)],
              targetWeightKg: 95,
              asOf: day,
            ),
            breakdown: breakdown(3400),
            asOf: day,
          )
          .map((i) => i.id)
          .toList();

      final first = onDay(DateTime(2026, 8, 20, 9));
      final second = onDay(DateTime(2026, 8, 21, 9));

      expect(onTrack().hasTrend, isTrue);
      expect(first, isNot(equals(second)));
      expect(first.toSet(), hasLength(first.length));
    });

    test('is deterministic for the same day', () {
      final day = DateTime(2026, 8, 20, 18);
      final a = engine.build(
        profile: profile(),
        progress: stats([entry(14, 87.5), entry(0, 88.5)]),
        breakdown: breakdown(3400),
        asOf: day,
      );
      final b = engine.build(
        profile: profile(),
        progress: stats([entry(14, 87.5), entry(0, 88.5)]),
        breakdown: breakdown(3400),
        asOf: day,
      );

      expect(a, equals(b));
    });
  });

  group('actions', () {
    test('weigh-in advice offers logging, plan advice offers recalculating', () {
      final logging = engine
          .build(profile: profile(), progress: stats(const []), asOf: now)
          .firstWhere((i) => i.id == 'weigh_in_first');
      final plan = engine
          .build(
            profile: profile(calories: 2500),
            progress: stats([entry(14, 87.0), entry(0, 88.5)]),
            breakdown: breakdown(2500),
            asOf: now,
          )
          .firstWhere((i) => i.id == 'plan_stale');

      expect(logging.action, InsightAction.logWeight);
      expect(plan.action, InsightAction.recalculate);
    });

    test('plain advice has no action attached', () {
      final water = engine
          .build(
            profile: profile(),
            progress: stats([entry(14, 87.5), entry(0, 88.5)]),
            asOf: now,
            limit: 10,
          )
          .firstWhere((i) => i.id == 'hydration');

      expect(water.action, InsightAction.none);
    });
  });
}
