import 'package:bulkr/core/progress_stats.dart';
import 'package:bulkr/models/weight_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed clock so windowed figures don't drift with the wall clock.
  final DateTime now = DateTime(2026, 8, 20, 12);

  WeightEntry entry(int daysAgo, double kg) => WeightEntry(
        weightKg: kg,
        loggedAt: now.subtract(Duration(days: daysAgo)),
      );

  ProgressStats stats(List<WeightEntry> history, {double target = 95}) =>
      ProgressStats(history: history, targetWeightKg: target, asOf: now);

  group('change over a window', () {
    test('reports the change across the last 30 days', () {
      final subject = stats([
        entry(28, 84.3),
        entry(14, 86.1),
        entry(0, 88.5),
      ]);

      expect(subject.monthlyChangeKg, closeTo(4.2, 0.001));
      expect(subject.totalChangeKg, closeTo(4.2, 0.001));
    });

    test('a single weigh-in is a dot, not a trend', () {
      final subject = stats([entry(0, 88.5)]);

      expect(subject.hasTrend, isFalse);
      expect(subject.monthlyChangeKg, isNull);
      expect(subject.totalChangeKg, isNull);
      expect(subject.weeklyRateKg, isNull);
    });

    test('older entries still count towards the total but not the month', () {
      final subject = stats([
        entry(200, 70.0),
        entry(120, 80.0),
        entry(0, 88.5),
      ]);

      expect(subject.totalChangeKg, closeTo(18.5, 0.001));
      // Only one weigh-in falls inside the last 30 days.
      expect(subject.monthlyChangeKg, isNull);
    });

    test('accepts history in any order', () {
      final subject = stats([
        entry(0, 88.5),
        entry(28, 84.3),
      ]);

      expect(subject.startWeightKg, 84.3);
      expect(subject.latestWeightKg, 88.5);
      expect(subject.monthlyChangeKg, closeTo(4.2, 0.001));
    });
  });

  group('weeklyRateKg', () {
    test('is measured over the recent window when it has two points', () {
      // 2.4 kg across 14 days = 1.2 kg/week, despite a flatter early history.
      final subject = stats([
        entry(90, 80.0),
        entry(14, 86.1),
        entry(0, 88.5),
      ]);

      expect(subject.weeklyRateKg, closeTo(1.2, 0.001));
    });

    test('falls back to the whole history when the month has one point', () {
      // 8.5 kg across 100 days.
      final subject = stats([entry(100, 80.0), entry(0, 88.5)]);

      expect(subject.weeklyRateKg, closeTo(8.5 / 100 * 7, 0.001));
    });

    test('two weigh-ins on the same day describe a scale, not a week', () {
      final subject = stats([
        WeightEntry(weightKg: 88.0, loggedAt: now.subtract(const Duration(hours: 6))),
        WeightEntry(weightKg: 88.4, loggedAt: now),
      ]);

      expect(subject.weeklyRateKg, isNull);
    });
  });

  group('fractionToTarget', () {
    test('measures from the starting weigh-in to the target', () {
      // 85 -> 95 target, now at 88.5: 3.5 of 10 kg.
      final subject = stats([entry(30, 85.0), entry(0, 88.5)]);

      expect(subject.fractionToTarget, closeTo(0.35, 0.001));
    });

    test('clamps once the target is passed', () {
      final subject = stats([entry(30, 85.0), entry(0, 97.0)]);

      expect(subject.fractionToTarget, 1.0);
      expect(subject.isTargetReached, isTrue);
    });

    test('works when the target is below the starting weight', () {
      final subject = stats([entry(30, 100.0), entry(0, 95.0)], target: 90);

      expect(subject.fractionToTarget, closeTo(0.5, 0.001));
      expect(subject.isTargetReached, isFalse);
    });

    test('has no fraction when the target was already met at the start', () {
      final subject = stats([entry(30, 95.0), entry(0, 96.0)]);

      expect(subject.fractionToTarget, isNull);
    });
  });

  group('projectedTargetDate', () {
    test('extrapolates the observed rate to the target', () {
      // +1 kg/week with 6.5 kg to go => 6.5 weeks, rounded up to 46 days.
      final subject = stats([entry(14, 86.5), entry(0, 88.5)]);

      final projected = subject.projectedTargetDate;
      expect(projected, isNotNull);
      expect(projected!.difference(now).inDays, 46);
    });

    test('refuses to project when the trend points away from the target', () {
      final subject = stats([entry(14, 90.0), entry(0, 88.5)]);

      expect(subject.projectedTargetDate, isNull);
    });

    test('refuses to project a date years out', () {
      // 0.0117 kg/week against 6.5 kg to go is over ten years.
      final subject = stats([entry(30, 88.45), entry(0, 88.5)]);

      expect(subject.projectedTargetDate, isNull);
    });

    test('has nothing to project once the target is reached', () {
      final subject = stats([entry(14, 93.0), entry(0, 95.5)]);

      expect(subject.isTargetReached, isTrue);
      expect(subject.projectedTargetDate, isNull);
    });
  });

  group('freshness and body stats', () {
    test('counts the days since the last weigh-in', () {
      expect(stats([entry(3, 88.0)]).daysSinceLastWeighIn, 3);
      expect(stats([entry(0, 88.0)]).daysSinceLastWeighIn, 0);
    });

    test('has no weigh-in figures at all without history', () {
      final subject = stats(const []);

      expect(subject.logCount, 0);
      expect(subject.latestWeightKg, isNull);
      expect(subject.remainingKg, isNull);
      expect(subject.daysSinceLastWeighIn, isNull);
      expect(subject.bmi(180), isNull);
    });

    test('computes BMI from the latest weigh-in', () {
      // 88.5 / 1.8^2
      expect(stats([entry(0, 88.5)]).bmi(180), closeTo(27.31, 0.01));
    });

    test('reports what is left to gain', () {
      expect(stats([entry(0, 88.5)]).remainingKg, closeTo(6.5, 0.001));
    });
  });
}
