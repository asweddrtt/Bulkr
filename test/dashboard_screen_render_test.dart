import 'package:bulkr/cubit/profile/profile_cubit.dart';
import 'package:bulkr/data/user_repository.dart';
import 'package:bulkr/models/activity_level.dart';
import 'package:bulkr/models/gender.dart';
import 'package:bulkr/models/unit_system.dart';
import 'package:bulkr/models/user_profile.dart';
import 'package:bulkr/models/weight_entry.dart';
import 'package:bulkr/screens/dashboard_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Serves fixtures instead of Supabase, so the screen can be rendered without
/// a session. The base constructor is given a client it never calls.
class _FakeUserRepository extends UserRepository {
  _FakeUserRepository({required this.profile, required this.history})
      : super(
          client: SupabaseClient(
            'https://example.supabase.co',
            'test-key',
            // Without this the auth client starts a periodic refresh timer,
            // and flutter_test fails any test that leaves a timer pending.
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final UserProfile profile;
  final List<WeightEntry> history;

  @override
  Future<UserProfile?> fetchProfile() async => profile;

  @override
  Future<List<WeightEntry>> fetchWeightHistory({int limit = 90}) async =>
      history;
}

/// Letters and digits only, upper case: lets a test match "current_weight"
/// and "CURRENT WEIGHT" with one expectation.
String _normalise(String value) =>
    value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // easy_localization stores the chosen locale in shared_preferences, whose
    // platform channel does not exist under flutter_test.
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAll') return <String, Object>{};
      return null;
    });

    await EasyLocalization.ensureInitialized();
  });

  final DateTime now = DateTime(2026, 8, 21, 9);

  UserProfile fixture() => UserProfile(
        id: 'u1',
        username: 'maxgains',
        displayName: 'Max Gains',
        gender: Gender.male,
        dateOfBirth: DateTime(1996, 3, 2),
        heightCm: 180,
        currentWeightKg: 88.5,
        targetWeightKg: 95,
        activityLevel: ActivityLevel.moderatelyActive,
        units: UnitSystem.metric,
        dailyCalorieTarget: 3400,
        proteinTargetG: 159,
        carbsTargetG: 400,
        fatTargetG: 94,
        onboardingCompleted: true,
      );

  Future<void> pumpProfile(
    WidgetTester tester, {
    required List<WeightEntry> history,
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = ProfileCubit(
      userRepository: _FakeUserRepository(
        profile: fixture(),
        history: history,
      ),
    );
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: ScreenUtilInit(
          designSize: size,
          builder: (context, child) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: BlocProvider.value(
              value: cubit,
              child: const DashboardScreen(),
            ),
          ),
        ),
      ),
    );

    // easy_localization loads its asset asynchronously and gates its child on
    // it, so pump until the page is actually up rather than a fixed count.
    for (var i = 0; i < 40 && find.byType(ListView).evaluate().isEmpty; i++) {
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }
    expect(find.byType(ListView), findsOneWidget,
        reason: 'the profile never reached its ready state');
  }

  /// Scrolls the page to the end, collecting every string it renders on the
  /// way. Any layout error — overflow included — fails the test.
  Future<Set<String>> renderedText(WidgetTester tester) async {
    final collected = <String>{};

    for (var i = 0; i < 24; i++) {
      collected.addAll(
        tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .where((value) => value.isNotEmpty),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -260));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
    }

    return collected;
  }

  testWidgets('every section renders for a user with weigh-ins',
      (tester) async {
    await pumpProfile(tester, history: [
      WeightEntry(weightKg: 84.3, loggedAt: now.subtract(const Duration(days: 28))),
      WeightEntry(weightKg: 86.1, loggedAt: now.subtract(const Duration(days: 14))),
      WeightEntry(weightKg: 88.5, loggedAt: now),
    ]);

    final rendered = await renderedText(tester);

    // Under flutter_test easy_localization may serve the key rather than the
    // copy, so a section counts as rendered if either shows up.
    for (final section in const {
      'weight_progress': 'WEIGHT PROGRESS',
      'log_weight_btn': 'LOG WEIGHT',
      'current_weight': 'CURRENT WEIGHT',
      'target_weight': 'TARGET WEIGHT',
      'progress_stats_title': 'PROGRESS',
      'plan_maintenance': 'MAINTENANCE',
      'plan_surplus': 'SURPLUS',
      'nutrition_plan': 'NUTRITION PLAN',
      'recalculate': 'RECALCULATE',
      'body_stats_title': 'BODY STATS',
      'focus_title': "TODAY'S FOCUS",
    }.entries) {
      final matched = rendered.any((text) =>
          _normalise(text).contains(_normalise(section.key)) ||
          _normalise(text).contains(_normalise(section.value)));

      expect(
        matched,
        isTrue,
        reason: 'section missing from the rendered page: ${section.value}',
      );
    }

    // The user's own data, which is not translated either way.
    expect(rendered, contains('MAX GAINS'));
  });
}
