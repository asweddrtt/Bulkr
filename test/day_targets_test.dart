import 'package:bulkr/models/activity_level.dart';
import 'package:bulkr/models/gender.dart';
import 'package:bulkr/models/unit_system.dart';
import 'package:bulkr/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which numbers apply on which day.
///
/// The whole feature is one question — "is today a lifting day?" — asked by
/// every screen that shows a target. Getting it wrong is not a cosmetic bug:
/// it means somebody's calorie goal silently drops by 600 on a day they
/// trained, and the app tells them they overate when they did not.
void main() {
  UserProfile profile({
    int calories = 3200,
    int protein = 180,
    int carbs = 380,
    int fat = 90,
    int? restCalories,
    int? restProtein,
    int? restCarbs,
    int? restFat,
    List<int> trainingDays = const <int>[],
  }) {
    return UserProfile(
      id: 'user-1',
      username: 'maxgains',
      heightCm: 180,
      currentWeightKg: 80,
      targetWeightKg: 90,
      activityLevel: ActivityLevel.moderatelyActive,
      units: UnitSystem.metric,
      gender: Gender.male,
      dailyCalorieTarget: calories,
      proteinTargetG: protein,
      carbsTargetG: carbs,
      fatTargetG: fat,
      onboardingCompleted: true,
      restDayCalorieTarget: restCalories,
      restDayProteinG: restProtein,
      restDayCarbsG: restCarbs,
      restDayFatG: restFat,
      trainingDays: trainingDays,
    );
  }

  // 2026-09-14 is a Monday, so +n days walks the week from there.
  final DateTime monday = DateTime(2026, 9, 14);
  DateTime day(int offset) => monday.add(Duration(days: offset));

  group('an account with one set of numbers', () {
    test('uses them every day', () {
      final UserProfile user = profile();

      for (int offset = 0; offset < 7; offset++) {
        expect(user.targetsFor(day(offset)).calories, 3200);
      }
    });

    test('reports no day type at all', () {
      // The tracker hides the label on this, rather than calling every day a
      // training day to somebody who never told it what one is.
      expect(profile().hasDayTypes, isFalse);
    });

    test('and counts every day as training, so nothing reads as a rest day',
        () {
      expect(profile().isTrainingDay(monday), isTrue);
      expect(profile().isTrainingDay(day(6)), isTrue);
    });
  });

  group('an account that lifts Monday, Wednesday, Friday', () {
    final UserProfile user = profile(
      restCalories: 2600,
      restProtein: 180,
      restCarbs: 220,
      restFat: 85,
      trainingDays: const <int>[1, 3, 5],
    );

    test('gets the training numbers on those days', () {
      for (final int offset in const <int>[0, 2, 4]) {
        final DayTargets targets = user.targetsFor(day(offset));
        expect(targets.calories, 3200, reason: 'day $offset');
        expect(targets.isTraining, isTrue);
      }
    });

    test('and the rest numbers on the others', () {
      for (final int offset in const <int>[1, 3, 5, 6]) {
        final DayTargets targets = user.targetsFor(day(offset));
        expect(targets.calories, 2600, reason: 'day $offset');
        expect(targets.carbsG, 220);
        expect(targets.isTraining, isFalse);
      }
    });

    test('protein holds across both, which is the point of the split', () {
      // Carbs move, protein does not. If this ever inverted, the feature would
      // be actively harmful advice.
      expect(user.targetsFor(monday).proteinG, 180);
      expect(user.targetsFor(day(1)).proteinG, 180);
    });

    test('Sunday is day seven, not day zero', () {
      // `DateTime.weekday` is ISO — Monday 1 through Sunday 7 — and a zero
      // based reading would shift every day by one, which is the kind of bug
      // that looks like the feature working until somebody checks a Tuesday.
      expect(day(6).weekday, DateTime.sunday);
      expect(user.isTrainingDay(day(6)), isFalse);
    });
  });

  group('half-configured states resolve to something usable', () {
    test('days chosen but no rest calories is not day types', () {
      // Otherwise a rest day would apply a calorie goal of zero, and the ring
      // would be full on the first bite.
      final UserProfile user = profile(trainingDays: const <int>[1, 3, 5]);

      expect(user.hasDayTypes, isFalse);
      expect(user.targetsFor(day(1)).calories, 3200);
    });

    test('rest calories but no days chosen is not day types', () {
      final UserProfile user = profile(restCalories: 2600);

      expect(user.hasDayTypes, isFalse);
      expect(user.targetsFor(day(1)).calories, 3200);
    });

    test('a missing rest macro falls back to its training value', () {
      // A form filled in halfway. Zero protein on a rest day would read as
      // "met" the moment anything was logged.
      final UserProfile user = profile(
        restCalories: 2600,
        trainingDays: const <int>[1],
      );

      final DayTargets rest = user.targetsFor(day(1));
      expect(rest.calories, 2600);
      expect(rest.proteinG, 180);
      expect(rest.fatG, 90);
    });
  });

  group('reading training_days off the row', () {
    UserProfile parse(Object? days) => UserProfile.fromMap(<String, dynamic>{
          'id': 'user-1',
          'username': 'maxgains',
          'height_cm': 180,
          'current_weight_kg': 80,
          'target_weight_kg': 90,
          'activity_level': 'moderately_active',
          'unit_system': 'metric',
          'daily_calorie_target': 3200,
          'protein_target_g': 180,
          'carbs_target_g': 380,
          'fat_target_g': 90,
          'onboarding_completed': true,
          'rest_day_calorie_target': 2600,
          'training_days': days,
        });

    test('a normal array comes through sorted', () {
      expect(parse(<int>[5, 1, 3]).trainingDays, <int>[1, 3, 5]);
    });

    test('null is simply no day types', () {
      // Every row written before the column existed.
      expect(parse(null).trainingDays, isEmpty);
      expect(parse(null).hasDayTypes, isFalse);
    });

    test('a day that is not a day is dropped, not trusted', () {
      // A stray 0 would otherwise sit in the set meaning nothing, and an 8
      // likewise — both silently making a real day read as rest.
      expect(parse(<int>[0, 3, 8, 7]).trainingDays, <int>[3, 7]);
    });

    test('rubbish in the column does not throw', () {
      expect(parse('every other day').trainingDays, isEmpty);
      expect(parse(<Object>['1', 2]).trainingDays, <int>[1, 2]);
    });
  });
}
