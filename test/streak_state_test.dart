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

  group('TrackerState.canRestoreStreak', () {
    // The offer to watch a video and bring back a streak that ended
    // yesterday. Whether it is *allowed* is decided entirely by the server —
    // one missed day, on the day after, once a month — so all this has to get
    // right is not contradicting itself on screen.
    test('is not offered when there is nothing to restore', () {
      expect(TrackerState(day: DateTime(2026)).canRestoreStreak, isFalse);
    });

    test('is not offered alongside a running streak', () {
      // A streak card and an offer to bring one back on the same screen is a
      // contradiction. The server already answers zero here; this is the belt
      // to that braces, for the moment between restoring and the reload.
      const int running = 6;
      expect(
        TrackerState(day: DateTime(2026), streak: running, restorableStreak: 9)
            .canRestoreStreak,
        isFalse,
      );
    });

    test('is offered when a real streak has gone', () {
      expect(
        TrackerState(day: DateTime(2026), streak: 0, restorableStreak: 12)
            .canRestoreStreak,
        isTrue,
      );
    });

    test('a one-day run is not worth restoring', () {
      // `restorable_streak()` returns the length it would come back as, so 2
      // means a single logged day plus the restored one. Nobody mourns that,
      // and it is not worth thirty seconds of anybody's attention.
      expect(
        TrackerState(day: DateTime(2026), restorableStreak: 1)
            .canRestoreStreak,
        isFalse,
      );
      expect(
        TrackerState(day: DateTime(2026), restorableStreak: 2)
            .canRestoreStreak,
        isTrue,
      );
    });
  });
}
