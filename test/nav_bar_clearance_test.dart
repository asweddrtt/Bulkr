import 'package:bulkr/screens/main_screen.dart';
import 'package:bulkr/widgets/bulkr_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The compose button sat under the floating nav bar.
///
/// Lifting it by the bar's height plus its margin looked right and was short by
/// exactly the home indicator: on a 390x844 screen with a 34px bottom inset the
/// button's lower 18px were behind the glass. It would have looked fine on a
/// phone with no indicator, which is the sort of bug that survives testing.
///
/// So this measures rather than recomputes. If the arithmetic in `fabInsetFor`
/// is ever wrong again, the number that matters is the gap between the button's
/// bottom edge and the bar's top edge, and that is what is asserted.
void main() {
  const Size viewport = Size(390, 844);

  /// The shell's structure exactly: an outer Scaffold with `extendBody` and the
  /// real nav bar, a tab's own Scaffold nested in its body, and that Scaffold's
  /// floating action button lifted by the value under test.
  Future<({Rect fab, Rect bar})> layout(
    WidgetTester tester, {
    required double bottomInset,
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: viewport,
          padding: EdgeInsets.only(bottom: bottomInset),
          viewPadding: EdgeInsets.only(bottom: bottomInset),
        ),
        // designSize == viewport, so 1.h is 1 logical pixel and the numbers
        // below are the numbers on the device.
        child: ScreenUtilInit(
          designSize: viewport,
          useInheritedMediaQuery: true,
          builder: (_, __) => MaterialApp(
            home: Scaffold(
              extendBody: true,
              body: SafeArea(
                bottom: false,
                child: Builder(
                  builder: (inner) => Scaffold(
                    backgroundColor: Colors.transparent,
                    floatingActionButton: Padding(
                      padding: EdgeInsets.only(
                        bottom: BulkrNavBar.fabInsetFor(inner),
                      ),
                      child: FloatingActionButton.extended(
                        key: const Key('fab'),
                        onPressed: () {},
                        label: const Text('Compose'),
                      ),
                    ),
                    body: const SizedBox.expand(),
                  ),
                ),
              ),
              bottomNavigationBar: BulkrNavBar(
                key: const Key('bar'),
                destinations: MainScreen.destinations,
                currentIndex: 2,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return (
      fab: tester.getRect(find.byKey(const Key('fab'))),
      // The glass pill, which is what the button must not be behind. The bar
      // widget's own rect includes its SafeArea and margin, so asserting
      // against that would allow an overlap the height of the bar and pass
      // for the bug this file exists to catch.
      bar: tester.getRect(
        find.descendant(
          of: find.byKey(const Key('bar')),
          matching: find.byType(BackdropFilter),
        ),
      ),
    );
  }

  testWidgets('the compose button clears the bar on a phone with a home '
      'indicator', (tester) async {
    final rects = await layout(tester, bottomInset: 34);

    expect(
      rects.fab.bottom,
      lessThanOrEqualTo(rects.bar.top),
      reason: 'button bottom ${rects.fab.bottom} against pill top '
          '${rects.bar.top}. Lifting by barHeight + barMargin alone put this '
          '18px over.',
    );
  });

  testWidgets('and on a phone without one', (tester) async {
    // The case that always looked fine, and so hid the bug. It must not
    // regress into being lifted too far now that the inset is read from the
    // shell rather than hardcoded.
    final rects = await layout(tester, bottomInset: 0);
    expect(rects.fab.bottom, lessThanOrEqualTo(rects.bar.top),
        reason: 'button bottom ${rects.fab.bottom} against pill top '
            '${rects.bar.top}');
  });

  testWidgets('a pushed route with no bar to clear is not lifted',
      (tester) async {
    // Groups and a single group are full-screen routes outside the shell.
    // Their buttons have nothing above them, and their own safe-area inset is
    // not a reason to float one off the bottom of the screen.
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late double inset;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: viewport,
          padding: EdgeInsets.only(bottom: 34),
          viewPadding: EdgeInsets.only(bottom: 34),
        ),
        child: ScreenUtilInit(
          designSize: viewport,
          useInheritedMediaQuery: true,
          builder: (_, __) => MaterialApp(
            home: Builder(builder: (context) {
              inset = BulkrNavBar.fabInsetFor(context);
              return const Scaffold(body: SizedBox.expand());
            }),
          ),
        ),
      ),
    );

    expect(inset, BulkrNavBar.barHeight + BulkrNavBar.barMargin,
        reason: 'outside the shell there is no reported reservation, so the '
            'fallback applies rather than a bare safe-area inset');
  });

  testWidgets('the bar leaves the screen when hidden', (tester) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<Rect> pump({required bool visible}) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: viewport),
          child: ScreenUtilInit(
            designSize: viewport,
            useInheritedMediaQuery: true,
            builder: (_, __) => MaterialApp(
              home: Scaffold(
                extendBody: true,
                body: const SizedBox.expand(),
                bottomNavigationBar: BulkrNavBar(
                  key: const Key('bar'),
                  destinations: MainScreen.destinations,
                  currentIndex: 2,
                  onSelected: (_) {},
                  visible: visible,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The pill, not the widget. `AnimatedSlide` translates at paint time via
      // `FractionalTranslation`, which moves its child and leaves its own
      // layout rect where it was — so measuring the bar's own rect reports no
      // movement however far it has slid.
      return tester.getRect(
        find.descendant(
          of: find.byKey(const Key('bar')),
          matching: find.byType(BackdropFilter),
        ),
      );
    }

    final Rect shown = await pump(visible: true);
    final Rect hidden = await pump(visible: false);

    expect(hidden.top, greaterThan(shown.top),
        reason: 'hiding the bar should move it down, not fade it');
    expect(hidden.top >= viewport.height, isTrue,
        reason: 'it should be off the bottom edge entirely, margin included — '
            'top ${hidden.top} against a ${viewport.height} tall screen');
  });
}
