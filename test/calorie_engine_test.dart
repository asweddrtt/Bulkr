import 'package:bulkr/core/calorie_engine.dart';
import 'package:bulkr/models/activity_level.dart';
import 'package:bulkr/models/gender.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ageFromDateOfBirth', () {
    final dob = DateTime(1990, 6, 15);

    test('counts a birthday that has already passed this year', () {
      expect(
        CalorieEngine.ageFromDateOfBirth(dob, asOf: DateTime(2026, 8, 9)),
        36,
      );
    });

    test('does not count a birthday still to come this year', () {
      expect(
        CalorieEngine.ageFromDateOfBirth(dob, asOf: DateTime(2026, 5, 1)),
        35,
      );
    });

    test('counts the birthday itself', () {
      expect(
        CalorieEngine.ageFromDateOfBirth(dob, asOf: DateTime(2026, 6, 15)),
        36,
      );
    });
  });

  group('bmr (Mifflin-St Jeor)', () {
    // 10*80 + 6.25*180 - 5*30 + 5 = 800 + 1125 - 150 + 5
    test('male uses the +5 constant', () {
      expect(
        CalorieEngine.bmr(
          gender: Gender.male,
          weightKg: 80,
          heightCm: 180,
          age: 30,
        ),
        closeTo(1780, 0.001),
      );
    });

    // 10*65 + 6.25*165 - 5*28 - 161 = 650 + 1031.25 - 140 - 161
    test('female uses the -161 constant', () {
      expect(
        CalorieEngine.bmr(
          gender: Gender.female,
          weightKg: 65,
          heightCm: 165,
          age: 28,
        ),
        closeTo(1380.25, 0.001),
      );
    });

    // 10*70 + 6.25*170 - 5*25 - 78 = 700 + 1062.5 - 125 - 78
    test('other averages the two constants (-78) rather than overestimating',
        () {
      expect(
        CalorieEngine.bmr(
          gender: Gender.other,
          weightKg: 70,
          heightCm: 170,
          age: 25,
        ),
        closeTo(1559.5, 0.001),
      );
    });

    test('other sits exactly between male and female', () {
      double bmrFor(Gender gender) => CalorieEngine.bmr(
            gender: gender,
            weightKg: 70,
            heightCm: 170,
            age: 25,
          );

      expect(
        bmrFor(Gender.other),
        closeTo((bmrFor(Gender.male) + bmrFor(Gender.female)) / 2, 0.001),
      );
    });
  });

  group('activity multipliers', () {
    test('match the documented factors', () {
      expect(ActivityLevel.sedentary.multiplier, 1.2);
      expect(ActivityLevel.lightlyActive.multiplier, 1.375);
      expect(ActivityLevel.moderatelyActive.multiplier, 1.55);
      expect(ActivityLevel.veryActive.multiplier, 1.725);
      expect(ActivityLevel.extraActive.multiplier, 1.9);
    });

    test('all five levels are present', () {
      expect(ActivityLevel.values, hasLength(5));
    });

    test('db values match the Postgres activity_level enum labels', () {
      expect(
        ActivityLevel.values.map((a) => a.dbValue),
        ['sedentary', 'lightly_active', 'moderately_active', 'very_active',
          'extra_active'],
      );
    });

    test('tdee scales bmr by the multiplier', () {
      expect(
        CalorieEngine.tdee(bmr: 1780, activityLevel: ActivityLevel.sedentary),
        closeTo(2136, 0.001),
      );
      expect(
        CalorieEngine.tdee(bmr: 1780, activityLevel: ActivityLevel.extraActive),
        closeTo(3382, 0.001),
      );
    });
  });

  group('dailySurplus', () {
    test('0.5 kg/week works out at 550 kcal/day', () {
      expect(CalorieEngine.dailySurplus(0.5), closeTo(550, 0.001));
    });

    test('0.25 kg/week works out at 275 kcal/day', () {
      expect(CalorieEngine.dailySurplus(0.25), closeTo(275, 0.001));
    });

    test('scales linearly', () {
      expect(
        CalorieEngine.dailySurplus(0.5),
        closeTo(CalorieEngine.dailySurplus(0.25) * 2, 0.001),
      );
    });
  });

  group('buildPlan', () {
    final plan = CalorieEngine.buildPlan(
      gender: Gender.male,
      weightKg: 80,
      heightCm: 180,
      age: 30,
      activityLevel: ActivityLevel.moderatelyActive,
      weeklyGainKg: 0.5,
    );

    test('reports the intermediate figures it used', () {
      expect(plan.bmr, 1780);
      expect(plan.tdee, 2759); // 1780 * 1.55
      expect(plan.dailySurplus, 550);
    });

    test('rounds the target to the nearest 10', () {
      // 2759 + 550 = 3309 -> 3310
      expect(plan.calories, 3310);
      expect(plan.calories % 10, 0);
    });

    test('anchors protein to bodyweight at 1.8 g/kg', () {
      expect(plan.proteinG, 144); // 1.8 * 80
    });

    test('takes 25% of calories from fat', () {
      expect(plan.fatG, 92); // 3310 * 0.25 / 9
    });

    test('macro split reconciles with the calorie target', () {
      // Gram targets are whole numbers, so a few kcal of rounding drift is
      // expected — but the split must not silently lose hundreds.
      expect((plan.macroCalories - plan.calories).abs(), lessThanOrEqualTo(10));
    });

    test('a faster pace raises the target but not the protein anchor', () {
      final faster = CalorieEngine.buildPlan(
        gender: Gender.male,
        weightKg: 80,
        heightCm: 180,
        age: 30,
        activityLevel: ActivityLevel.moderatelyActive,
        weeklyGainKg: 0.75,
      );

      expect(faster.calories, greaterThan(plan.calories));
      expect(faster.proteinG, plan.proteinG);
    });

    test('never produces a negative or absurd macro across the input range',
        () {
      // Sweeps the whole space the pickers can actually produce. The carb
      // clamp inside buildPlan is defensive — with a 1.2x floor multiplier and
      // protein at 1.8 g/kg, protein plus fat cannot outrun TDEE for any
      // reachable combination — so this asserts the property rather than
      // pretending to exercise the clamp.
      for (final gender in Gender.values) {
        for (final level in ActivityLevel.values) {
          for (final weight in [35.0, 80.0, 250.0]) {
            for (final height in [120.0, 175.0, 230.0]) {
              for (final age in [13, 30, 100]) {
                for (final pace in [0.1, 0.5, 0.75]) {
                  final result = CalorieEngine.buildPlan(
                    gender: gender,
                    weightKg: weight,
                    heightCm: height,
                    age: age,
                    activityLevel: level,
                    weeklyGainKg: pace,
                  );

                  final context =
                      '$gender/$level/${weight}kg/${height}cm/${age}y/$pace';

                  expect(result.carbsG, greaterThanOrEqualTo(0), reason: context);
                  expect(result.proteinG, greaterThan(0), reason: context);
                  expect(result.fatG, greaterThan(0), reason: context);
                  expect(result.calories, greaterThan(0), reason: context);
                  expect(
                    (result.macroCalories - result.calories).abs(),
                    lessThanOrEqualTo(10),
                    reason: context,
                  );
                }
              }
            }
          }
        }
      }
    });
  });
}
