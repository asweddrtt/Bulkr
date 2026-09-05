import 'package:bulkr/cubit/tracker/tracker_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackerState.hasStreak', () {
    // One day is not a streak, it is a Tuesday. Drawing a card that says
    // "1 days in a row" on somebody's first ever log is worse than drawing
    // nothing.
    test('needs more than one day', () {
      expect(TrackerState(day: DateTime(2026), streak: 0).hasStreak, isFalse);
      expect(TrackerState(day: DateTime(2026), streak: 1).hasStreak, isFalse);
      expect(TrackerState(day: DateTime(2026), streak: 2).hasStreak, isTrue);
    });

    // Zero doubles as "not available" — the migration not run, or the read
    // failed — and both have to render as no card rather than a broken one.
    test('an unavailable streak is indistinguishable from none, on purpose',
        () {
      expect(TrackerState(day: DateTime(2026)).streak, 0);
      expect(TrackerState(day: DateTime(2026)).hasStreak, isFalse);
    });
  });
}
