import 'dart:async';

import 'package:bulkr/core/dispose_after.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dialog's controller has nowhere to be disposed.
///
/// `_askWeight`, `_askGrams` and the water goal sheet are plain functions that
/// build a `TextEditingController`, hand it to `showDialog`, and return. There
/// is no `State` and so no `dispose`, and all three simply dropped it — which
/// a `ChangeNotifier` survives, holding its listeners and everything they close
/// over, for the life of the process. Each of those dialogs is opened again
/// every time somebody weighs in, edits a portion, or changes their water goal.
///
/// `disposing` ties the controller to the dialog's future instead. The cases
/// below are the ways that future can end, because "disposed on the happy path
/// only" is the shape this is meant to rule out — and a dialog dismissed by
/// tapping outside is *not* the happy path, it is the common one.
void main() {
  test('disposes when the future completes with a value', () async {
    final _SpyController controller = _SpyController();

    await Future<double?>.value(72.5).disposing(controller);

    expect(controller.disposeCount, 1);
  });

  test('disposes when the dialog is dismissed and answers null', () async {
    // What tapping outside an AlertDialog does: completes normally, with null.
    // Nothing distinguishes it from the happy path at this level, which is
    // exactly why it is easy to leak.
    final _SpyController controller = _SpyController();

    await Future<double?>.value(null).disposing(controller);

    expect(controller.disposeCount, 1);
  });

  test('disposes when the future throws, and rethrows', () async {
    final _SpyController controller = _SpyController();
    final Future<double?> failing =
        Future<double?>.error(StateError('navigator went away'));

    await expectLater(
      failing.disposing(controller),
      throwsA(isA<StateError>()),
    );

    expect(controller.disposeCount, 1);
  });

  test('passes the result through unchanged', () async {
    final _SpyController controller = _SpyController();

    final double? result =
        await Future<double?>.value(81.2).disposing(controller);

    expect(result, 81.2);
  });

  test('waits for the future rather than disposing immediately', () async {
    final _SpyController controller = _SpyController();
    final Completer<int?> pending = Completer<int?>();

    final Future<int?> guarded = pending.future.disposing(controller);

    // The dialog is still open, so the controller is still the live one the
    // text field reads and writes. Disposing here would be worse than leaking.
    controller.text = '2000';
    expect(controller.disposeCount, 0);

    pending.complete(2000);
    await guarded;

    expect(controller.disposeCount, 1);
  });

  test('disposes exactly once', () async {
    // Disposing a ChangeNotifier twice throws in debug builds, which would
    // turn a leak into a crash on the way out of a dialog.
    final _SpyController controller = _SpyController();

    await Future<String?>.value('ok').disposing(controller);

    expect(controller.disposeCount, 1);
  });
}

/// A controller that records having been disposed.
///
/// Counted rather than checked by poking at the disposed object: reading
/// `controller.text` after `dispose` does *not* throw — the getter reads a
/// plain field — so a test written that way passes whether or not the fix is
/// there. That is the test this replaced.
class _SpyController extends TextEditingController {
  int disposeCount = 0;

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }
}
