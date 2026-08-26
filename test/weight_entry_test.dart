import 'package:bulkr/models/weight_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WeightEntry at(DateTime when, double kg) =>
      WeightEntry(weightKg: kg, loggedAt: when);

  group('latestPerDay', () {
    test('keeps only the last weigh-in of a day', () {
      final collapsed = WeightEntry.latestPerDay([
        at(DateTime(2026, 8, 20, 7, 30), 88.0),
        at(DateTime(2026, 8, 20, 12, 5), 88.6),
        at(DateTime(2026, 8, 20, 21, 45), 88.2),
      ]);

      expect(collapsed, hasLength(1));
      expect(collapsed.single.weightKg, 88.2);
      expect(collapsed.single.loggedAt, DateTime(2026, 8, 20, 21, 45));
    });

    test('is order independent — the clock decides, not the list', () {
      final collapsed = WeightEntry.latestPerDay([
        at(DateTime(2026, 8, 20, 21, 45), 88.2),
        at(DateTime(2026, 8, 20, 7, 30), 88.0),
      ]);

      expect(collapsed.single.weightKg, 88.2);
    });

    test('leaves separate days alone and sorts them oldest first', () {
      final collapsed = WeightEntry.latestPerDay([
        at(DateTime(2026, 8, 21, 8), 89.0),
        at(DateTime(2026, 8, 19, 8), 87.5),
        at(DateTime(2026, 8, 20, 8), 88.0),
        at(DateTime(2026, 8, 20, 19), 88.4),
      ]);

      expect(collapsed.map((e) => e.weightKg).toList(), [87.5, 88.4, 89.0]);
    });

    test('midnight and one minute to midnight are different days', () {
      final collapsed = WeightEntry.latestPerDay([
        at(DateTime(2026, 8, 20, 23, 59), 88.0),
        at(DateTime(2026, 8, 21, 0, 0), 88.1),
      ]);

      expect(collapsed, hasLength(2));
    });

    test('an empty history collapses to an empty history', () {
      expect(WeightEntry.latestPerDay(const []), isEmpty);
    });
  });
}
