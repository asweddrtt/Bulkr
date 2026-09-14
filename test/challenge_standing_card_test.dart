import 'package:bulkr/data/challenge_repository.dart';
import 'package:bulkr/models/challenge.dart';
import 'package:bulkr/widgets/challenge_standing_card.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The dashboard's challenge card.
///
/// Written after `dashboard_screen_render_test` was found to be exercising
/// none of it: the card reads its repository out of the widget tree, that test
/// provides none, and the card's own catch turned the resulting
/// `ProviderNotFoundException` into a debug line and an empty box. The screen
/// rendered, the test passed, and the card had never drawn a single pixel
/// under test.
///
/// That degradation is the right behaviour — a standing that cannot be read is
/// not worth a red box on the home screen of a food app — which is exactly why
/// it needed a test of its own. Silence is indistinguishable from working.
class _FakeChallengeRepository extends ChallengeRepository {
  _FakeChallengeRepository(this.standings)
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-key',
            // Without this the auth client starts a periodic refresh timer,
            // and flutter_test fails any test that leaves one pending.
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final List<MyChallengeStanding> standings;

  @override
  Future<List<MyChallengeStanding>> fetchMyStandings() async => standings;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // easy_localization stores the chosen locale in shared_preferences, whose
    // platform channel does not exist under flutter_test.
    const MethodChannel channel =
        MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return null;
    });

    await EasyLocalization.ensureInitialized();
  });

  MyChallengeStanding standing({
    ChallengeMetric metric = ChallengeMetric.weightGain,
    double? score = 2.4,
    int rank = 2,
    int participants = 7,
    double goal = 4,
    double? aheadScore = 3.0,
    String? aheadName = 'Sara',
    int daysLeft = 4,
  }) =>
      MyChallengeStanding(
        challengeId: 'c1',
        postId: 'p1',
        title: 'Winter Bulk',
        metric: metric,
        goalAmount: goal,
        startsAt: DateTime.now().subtract(const Duration(days: 3)),
        // Plus an hour, so `daysLeft` floors to the number asked for rather
        // than to one less on a clock that has moved during the test.
        endsAt: DateTime.now().add(Duration(days: daysLeft, hours: 1)),
        participantCount: participants,
        rank: rank,
        score: score,
        hasData: score != null,
        aheadScore: aheadScore,
        aheadName: aheadName,
      );

  Future<void> pumpCard(
    WidgetTester tester,
    List<MyChallengeStanding> standings,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Built once, outside the tree. Constructing it in `build` would make a
    // fresh SupabaseClient on every rebuild, and this pumps a lot of them.
    final ChallengeRepository repository = _FakeChallengeRepository(standings);

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const <Locale>[Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (BuildContext context, Widget? child) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            home: RepositoryProvider<ChallengeRepository>.value(
              value: repository,
              child: const Scaffold(
                body: SingleChildScrollView(child: ChallengeStandingCard()),
              ),
            ),
          ),
        ),
      ),
    );

    // easy_localization loads its asset asynchronously and gates its child on
    // it, and the card's own read is a future too. Pump until the words are
    // real rather than a fixed count.
    for (int i = 0; i < 40; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      if (find.textContaining('Winter Bulk').evaluate().isNotEmpty) break;
    }
  }

  testWidgets('an account in nothing gets no card at all', (tester) async {
    // No empty state, no "join a challenge!" prompt. Most accounts are in
    // nothing most of the time, and a home screen that advertises an unused
    // feature every visit is a home screen with an advert on it.
    await pumpCard(tester, const <MyChallengeStanding>[]);

    // The progress bar is drawn by every tile and by nothing else here, so
    // its absence is the card's absence. `find.byType(Card)` would have
    // asserted nothing at all — the tile is a Container.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Winter Bulk'), findsNothing);
  });

  testWidgets('the card names the challenge, the rank and the field', (
    tester,
  ) async {
    await pumpCard(tester, <MyChallengeStanding>[standing()]);

    expect(find.text('Winter Bulk'), findsOneWidget);
    // "#2" rather than "2nd": an ordinal needs a rule per language.
    expect(find.text('#2'), findsOneWidget);
    expect(find.text('of 7'), findsOneWidget);
    expect(find.text('4 days left'), findsOneWidget);
  });

  testWidgets('the score is written in the metric\'s own units', (
    tester,
  ) async {
    await pumpCard(tester, <MyChallengeStanding>[standing()]);
    expect(find.text('2.4 / 4 kg'), findsOneWidget);

    await pumpCard(tester, <MyChallengeStanding>[
      standing(metric: ChallengeMetric.daysLogged, score: 11, goal: 20),
    ]);
    // Whole, and "days" — not "11.0 / 20.0 kg".
    expect(find.text('11 / 20 days'), findsOneWidget);
  });

  testWidgets('the last line is who to catch', (tester) async {
    // The whole reason `my_challenge_standings()` returns the row above yours.
    // "You are second" is a fact; this is a reason to come back tomorrow.
    await pumpCard(tester, <MyChallengeStanding>[standing()]);

    expect(find.text('Sara is 0.6 kg ahead of you.'), findsOneWidget);
  });

  testWidgets('leading says so instead of naming nobody', (tester) async {
    await pumpCard(tester, <MyChallengeStanding>[
      standing(rank: 1, aheadScore: null, aheadName: null),
    ]);

    expect(find.text("You're top. Keep it."), findsOneWidget);
  });

  testWidgets('being level with the person above is not a gap', (tester) async {
    // A gap of zero renders as "Sara is 0 kg ahead of you", which is a
    // sentence about nothing.
    await pumpCard(tester, <MyChallengeStanding>[
      standing(score: 3, aheadScore: 3),
    ]);

    expect(find.text("You're level with the person above you."), findsOneWidget);
    expect(find.textContaining('0 kg ahead'), findsNothing);
  });

  testWidgets('a participant with no weight logged reads as no data', (
    tester,
  ) async {
    // Not as zero, which would place them ahead of everyone who has lost
    // weight and behind everyone who has gained.
    await pumpCard(tester, <MyChallengeStanding>[standing(score: null)]);

    expect(find.text('no data'), findsOneWidget);
  });

  testWidgets('a repository that throws leaves the dashboard alone', (
    tester,
  ) async {
    // The behaviour that hid this widget from its own test. It is still the
    // right one — but now something asserts it rather than nothing noticing.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => const MaterialApp(
          // No RepositoryProvider above it at all.
          home: Scaffold(body: ChallengeStandingCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
