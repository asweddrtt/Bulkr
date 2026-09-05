import 'package:bulkr/widgets/bulkr_nav_bar.dart';
import 'package:flutter_test/flutter_test.dart';

/// Five tabs, and a bar wide enough that one tab is 78 logical pixels.
const int _count = 5;
const double _step = 78;

({int index, double remaining}) _drag({
  required int from,
  required double travel,
  int count = _count,
  double step = _step,
}) =>
    BulkrNavBar.resolveDrag(
      current: from,
      count: count,
      travel: travel,
      step: step,
    );

void main() {
  // The whole point of this file. The first version consumed travel with the
  // wrong sign, so `remaining.abs()` grew on every pass and the loop never
  // ended — the UI thread froze the moment a drag crossed one step. Every case
  // below would have hung rather than failed.
  group('terminates', () {
    test('on a long drag in either direction', () {
      expect(_drag(from: 2, travel: -1000).index, isNotNull);
      expect(_drag(from: 2, travel: 1000).index, isNotNull);
    });

    test('on an absurd drag', () {
      expect(_drag(from: 0, travel: -1000000).index, _count - 1);
    });

    test('when the bar has no width to measure a step against', () {
      // Reachable during layout. Without the guard every travel is "at least
      // one step" and the loop is unbounded.
      final result = _drag(from: 2, travel: -500, step: 0);
      expect(result.index, 2);
      expect(result.remaining, 0);
    });
  });

  group('direction', () {
    test('dragging left moves forward, the way a page does', () {
      expect(_drag(from: 1, travel: -_step).index, 2);
    });

    test('dragging right moves back', () {
      expect(_drag(from: 3, travel: _step).index, 2);
    });

    test('travel below one step changes nothing', () {
      final result = _drag(from: 2, travel: -_step + 1);
      expect(result.index, 2);
      // ...and is kept, so a slow drag still gets there.
      expect(result.remaining, closeTo(-_step + 1, 0.0001));
    });
  });

  group('distance', () {
    test('a drag of three steps moves three tabs, not one', () {
      // The stale-read bug this also guards: reading widget.currentIndex per
      // step would re-read a value setState has only scheduled, so every step
      // would pick the same neighbour.
      expect(_drag(from: 0, travel: -_step * 3).index, 3);
    });

    test('consumed travel is subtracted, and the rest carries over', () {
      final result = _drag(from: 0, travel: -_step * 2 - 20);
      expect(result.index, 2);
      expect(result.remaining, closeTo(-20, 0.0001));
    });
  });

  group('ends', () {
    test('stops at the last tab', () {
      expect(_drag(from: 3, travel: -_step * 5).index, _count - 1);
    });

    test('stops at the first tab', () {
      expect(_drag(from: 1, travel: _step * 5).index, 0);
    });

    test('drops leftover travel at an end', () {
      // Otherwise pushing further builds a charge that fires the instant the
      // finger turns round.
      expect(_drag(from: 4, travel: -_step * 3).remaining, 0);
      expect(_drag(from: 0, travel: _step * 3).remaining, 0);
    });
  });

  test('an empty bar is not something to divide by', () {
    final result = _drag(from: 0, travel: -500, count: 0);
    expect(result.index, 0);
    expect(result.remaining, 0);
  });
}
