import 'dart:io';

import 'package:bulkr/widgets/bulkr_nav_bar.dart';
import 'package:bulkr/widgets/bulkr_snack_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every message in the app, floating and clear of the navigation bar.
///
/// Two bugs are being held off here, and they are different in kind.
///
/// The first is a layout one: Material's default snackbar is welded to the
/// bottom edge, and Bulkr's navigation bar floats over exactly that strip. A
/// message that appears behind the bar has not been shown, it has been
/// swallowed — and it looks fine in a screenshot of a screen with no bar.
///
/// The second is drift. Before `BulkrSnackBar` there were forty-odd
/// hand-written `SnackBar`s, each repeating the same grey and the same text
/// style, and the two that had drifted were the ones nobody noticed. So the
/// second group is a source lint: a new call site that builds its own is
/// caught here rather than by somebody spotting a square grey bar in week
/// three.
void main() {
  const Size viewport = Size(390, 844);

  /// designSize == viewport, so `1.h` is one logical pixel and the numbers
  /// below are the numbers on the device.
  Future<void> pump(
    WidgetTester tester,
    void Function(BuildContext context) act,
  ) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late BuildContext captured;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: viewport,
        builder: (_, __) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                captured = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );

    act(captured);
    await tester.pump();
  }

  SnackBar shown(WidgetTester tester) =>
      tester.widget<SnackBar>(find.byType(SnackBar));

  group('how it is drawn', () {
    testWidgets('floats rather than filling the bottom edge', (tester) async {
      await pump(tester, (context) => BulkrSnackBar.show(context, 'hello'));

      expect(shown(tester).behavior, SnackBarBehavior.floating);
    });

    testWidgets('is lifted clear of the navigation bar', (tester) async {
      await pump(tester, (context) => BulkrSnackBar.show(context, 'hello'));

      final EdgeInsets margin = shown(tester).margin! as EdgeInsets;

      // The assertion is the clearance, not the arithmetic: whatever the lift
      // is computed from, the message must start above where the bar ends.
      expect(
        margin.bottom,
        greaterThanOrEqualTo(BulkrNavBar.barHeight + BulkrNavBar.barMargin),
        reason: 'a message under the navigation bar has not been shown',
      );
    });

    testWidgets('a pushed route is not lifted, having no bar under it', (
      tester,
    ) async {
      await pump(
        tester,
        (context) =>
            BulkrSnackBar.show(context, 'hello', clearsNavBar: false),
      );

      final EdgeInsets margin = shown(tester).margin! as EdgeInsets;

      expect(margin.bottom, lessThan(BulkrNavBar.barHeight));
      // Still inset from the edge, or it is not floating, it is just detached.
      expect(margin.bottom, greaterThan(0));
    });

    testWidgets('the tone decides the colour, and every tone has one', (
      tester,
    ) async {
      final Set<Color?> colours = <Color?>{};

      for (final SnackTone tone in SnackTone.values) {
        await pump(
          tester,
          (context) => BulkrSnackBar.show(context, 'hello', tone: tone),
        );
        colours.add(shown(tester).backgroundColor);
      }

      expect(colours, hasLength(SnackTone.values.length),
          reason: 'two tones share a colour, so one of them says nothing');
      expect(colours, isNot(contains(null)));
    });

    testWidgets('an action is carried through with the tone accent', (
      tester,
    ) async {
      bool tapped = false;

      await pump(
        tester,
        (context) => BulkrSnackBar.show(
          context,
          'hidden',
          actionLabel: 'UNDO',
          onAction: () => tapped = true,
        ),
      );

      // Settled first. A floating snackbar slides in behind an IgnorePointer,
      // so a tap on the frame after `show` lands on a widget that is on
      // screen, at the right offset, and not yet accepting pointers — which
      // fails as a miss rather than as anything that names the cause.
      await tester.pumpAndSettle();

      await tester.tap(find.text('UNDO'));
      expect(tapped, isTrue);
    });

    testWidgets('a second message replaces the first', (tester) async {
      // Queued instead, somebody waits four seconds to read news that is
      // already stale.
      await pump(tester, (context) {
        BulkrSnackBar.show(context, 'first');
        BulkrSnackBar.show(context, 'second');
      });
      // Settled rather than pumped a fixed amount, so the first one's exit
      // animation is finished rather than probably finished.
      await tester.pumpAndSettle();

      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
    });
  });

  group('nothing builds its own', () {
    /// The two files allowed to name `SnackBar` directly.
    ///
    /// `bulkr_snack_bar.dart` is the one that builds them. The startup failure
    /// screen is deliberate: it is what shows when the app did not start, so
    /// it uses none of the app — not the theme, not the translations, and not
    /// a widget that could itself be the thing that is broken.
    const Set<String> allowed = <String>{
      'lib/widgets/bulkr_snack_bar.dart',
      'lib/screens/startup_failure_screen.dart',
    };

    test('every message goes through BulkrSnackBar', () {
      final List<String> offenders = <String>[];

      for (final File file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((File f) => f.path.endsWith('.dart'))) {
        final String path = file.path.replaceAll(r'\', '/');
        if (allowed.contains(path)) continue;

        if (file.readAsStringSync().contains('showSnackBar(')) {
          offenders.add(path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'these show a snackbar directly, so they do not float, do not '
            'clear the navigation bar, and do not share the tone colours. '
            'Use BulkrSnackBar.show or BulkrSnackBar.showOn',
      );
    });

    test('the lint is looking at real files', () {
      // A source scan passes just as happily when it reads nothing.
      for (final String path in allowed) {
        expect(File(path).existsSync(), isTrue, reason: '$path has moved');
      }
      expect(
        File('lib/widgets/bulkr_snack_bar.dart')
            .readAsStringSync()
            .contains('showSnackBar('),
        isTrue,
        reason: 'the pattern the lint searches for no longer appears anywhere',
      );
    });
  });
}
