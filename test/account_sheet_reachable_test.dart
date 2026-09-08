import 'package:bulkr/widgets/account_sheet.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet whose whole purpose is signing out could not be scrolled to the
/// sign-out button.
///
/// `showModalBottomSheet` caps a sheet at nine sixteenths of the screen unless
/// told otherwise, and the content — five rows with helper text, sign out,
/// delete account — is taller than that. With a non-scrolling Column inside a
/// fixed cap, the overflow is not clipped-but-reachable. It is unreachable, and
/// the only symptom is a button that is not there.
///
/// So the test is not "does it render" but "can a finger get to it", on a
/// viewport short enough that the answer used to be no.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // easy_localization keeps the locale in shared_preferences, whose platform
    // channel does not exist under flutter_test.
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAll') return <String, Object>{};
          return null;
        });

    await EasyLocalization.ensureInitialized();
  });

  /// A short phone. The bug needs the content to exceed the cap, and it does
  /// so most obviously here.
  const Size viewport = Size(390, 640);

  Future<int Function()> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    int signedOut = 0;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ScreenUtilInit(
          designSize: viewport,
          builder: (context, child) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: Builder(
              builder: (inner) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => AccountSheet.show(
                      inner,
                      email: 'someone@example.com',
                      username: 'maxgains',
                      onSignOut: () async => signedOut++,
                      onManageBlocked: () {},
                      onDeleteAccount: () {},
                      onSavedPosts: () {},
                      onCreateGroup: () {},
                      onChallenges: () {},
                      onEditProfile: () {},
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // ScreenUtilInit does not build its child on the first frame, so nothing
    // is findable until this settles.
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A closure rather than the value: the count is read after the tap, and
    // returning the int here would always return the zero it had before.
    return () => signedOut;
  }

  testWidgets('sign out is reachable and works on a short screen', (
    tester,
  ) async {
    final int Function() signedOut = await openSheet(tester);

    // One test rather than two on purpose: ScreenUtil keeps its configuration
    // in a static, so a second `testWidgets` in this file inherits the first
    // one's viewport and fails for reasons that have nothing to do with the
    // sheet. Everything worth asserting happens in one pass anyway.
    expect(
      find.byType(SingleChildScrollView),
      findsWidgets,
      reason: 'a sheet taller than its cap has to be scrollable',
    );

    final Finder signOut = find.widgetWithText(OutlinedButton, 'SIGN OUT');
    final Finder delete = find.widgetWithText(TextButton, 'Delete my account');

    expect(
      signOut,
      findsOneWidget,
      reason: 'the sign-out button is not in the tree at all',
    );

    // Delete account is the last thing in the column, below sign out. Getting
    // to it means the whole sheet is traversable, not just the part that fit.
    await tester.scrollUntilVisible(delete, 120);
    await tester.pumpAndSettle();

    // The point of the file. `scrollUntilVisible` throws outright if nothing
    // scrolls, which is exactly what used to happen: the widget existed, was
    // laid out past the bottom of a fixed-height sheet, and no gesture could
    // bring it into view.
    await tester.scrollUntilVisible(signOut, -120);
    await tester.pumpAndSettle();

    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(
      signedOut(),
      1,
      reason:
          'the tap reached the button but not the '
          'callback behind it',
    );
  });
}
