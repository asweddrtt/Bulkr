import 'package:bulkr/widgets/bulkr_nav_bar.dart';
import 'package:flutter_test/flutter_test.dart';

/// Five tabs across a bar where one tab is 78 logical pixels wide.
const int _count = 5;
const double _slot = 78;

double _drag(double position, double dx) => BulkrNavBar.positionAfterDrag(
      position: position,
      dx: dx,
      slotWidth: _slot,
      count: _count,
    );

void main() {
  group('the highlight tracks the finger', () {
    test('a partial drag lands between tabs', () {
      // The whole point of the rewrite. The stepped version this replaces
      // could only ever return a whole number, which is why it felt like a
      // switch rather than something attached to the finger.
      expect(_drag(2, -_slot / 2), closeTo(1.5, 0.0001));
      expect(_drag(2, _slot / 4), closeTo(2.25, 0.0001));
    });

    test('the highlight goes the way the finger goes', () {
      // Not the PageView convention, deliberately: there you drag content past
      // a fixed frame, here your finger is on the highlight itself.
      expect(_drag(3, -_slot), closeTo(2, 0.0001));
      expect(_drag(1, _slot), closeTo(2, 0.0001));
    });

    test('travel is proportional, so a long drag crosses several tabs', () {
      expect(_drag(4, -_slot * 3), closeTo(1, 0.0001));
    });
  });

  group('what gets selected', () {
    test('is the nearest tab, so content switches at each centre', () {
      // The widget selects `position.round()`, which is what makes the screen
      // behind the glass change as the highlight passes rather than on lift.
      expect(_drag(2, -_slot * 0.49).round(), 2);
      expect(_drag(2, -_slot * 0.51).round(), 1);
    });
  });

  group('ends', () {
    test('clamps at the last tab', () {
      expect(_drag(3, _slot * 5), closeTo(_count - 1, 0.0001));
    });

    test('clamps at the first tab', () {
      expect(_drag(1, -_slot * 5), closeTo(0, 0.0001));
    });

    test('overshooting does not bank travel for the way back', () {
      // Clamping rather than accumulating: pushing well past the end and then
      // turning round should start moving immediately, not after paying back
      // everything that was pushed.
      final double atEnd = _drag(0, -_slot * 10);
      expect(atEnd, closeTo(0, 0.0001));
      expect(_drag(atEnd, _slot), closeTo(1, 0.0001));
    });
  });

  group('degenerate input is answered rather than divided by', () {
    test('a bar with no width leaves the highlight alone', () {
      // Reachable during layout. Dividing by it would put the highlight at
      // infinity, and NaN would propagate into every Positioned on the bar.
      expect(
        BulkrNavBar.positionAfterDrag(
            position: 2, dx: -500, slotWidth: 0, count: _count),
        2,
      );
    });

    test('an empty bar leaves the highlight alone', () {
      expect(
        BulkrNavBar.positionAfterDrag(
            position: 0, dx: -500, slotWidth: _slot, count: 0),
        0,
      );
    });
  });

  group('emphasis', () {
    test('is full on the tab the highlight is centred over', () {
      expect(BulkrNavBar.emphasisFor(2, 2), 1);
    });

    test('is shared between neighbours mid-drag', () {
      // Both partly lit while the pill is between them, so neither blinks.
      expect(BulkrNavBar.emphasisFor(2.5, 2), closeTo(0.5, 0.0001));
      expect(BulkrNavBar.emphasisFor(2.5, 3), closeTo(0.5, 0.0001));
    });

    test('is nothing for a tab the highlight is not touching', () {
      expect(BulkrNavBar.emphasisFor(2, 0), 0);
      expect(BulkrNavBar.emphasisFor(2, 4), 0);
    });

    test('never goes negative, however far away the tab is', () {
      for (int i = 0; i < _count; i++) {
        expect(BulkrNavBar.emphasisFor(0, i), inInclusiveRange(0, 1));
        expect(BulkrNavBar.emphasisFor(4, i), inInclusiveRange(0, 1));
      }
    });
  });
}
