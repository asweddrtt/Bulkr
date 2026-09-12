import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/analytics_events.dart';
import 'core/config/supabase_config.dart';
import 'core/telemetry.dart';
import 'cubit/auth/auth_cubit.dart';
import 'cubit/conversations/conversations_cubit.dart';
import 'cubit/entitlement/entitlement_cubit.dart';
import 'cubit/feed/feed_cubit.dart';
import 'cubit/notifications/notifications_cubit.dart';
import 'cubit/meals/meals_cubit.dart';
import 'cubit/onboarding/onboarding_cubit.dart';
import 'cubit/tracker/tracker_cubit.dart';
import 'cubit/profile/profile_cubit.dart';
import 'data/app_preferences.dart';
import 'data/auth_repository.dart';
import 'data/ads_service.dart';
import 'data/challenge_repository.dart';
import 'data/entitlement_repository.dart';
import 'data/follow_repository.dart';
import 'data/chat_repository.dart';
import 'data/notification_repository.dart';
import 'data/push_repository.dart';
import 'data/push_service.dart';
import 'data/food_repository.dart';
import 'data/group_repository.dart';
import 'data/moderation_repository.dart';
import 'data/meal_repository.dart';
import 'data/post_repository.dart';
import 'data/user_repository.dart';
import 'go_router/router_config.dart';
import 'screens/boot_screen.dart';
import 'screens/startup_failure_screen.dart';
import 'styles/app_color.dart';

/// How long any one startup step may take before it is treated as hung.
///
/// A step that throws reports itself. A step that simply never returns is the
/// worse case: `runApp` is never reached, the app is a white rectangle, and
/// there is no crash report because nothing crashed. This bounds that.
///
/// Fifteen seconds is well past a slow cold start on a bad connection and well
/// short of the point where somebody force-quits.
const Duration _startupBudget = Duration(seconds: 15);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Started here so the whole of launch is measured, including the parts that
  // are slow on a cold start and a bad connection.
  final Stopwatch launch = Stopwatch()..start();

  // Painted before anything is awaited, so the app is never white.
  //
  // Nothing in Bulkr is white — the theme is black, the splash and the failure
  // screen are #121212 — so a white screen is the *native* launch screen still
  // showing, which means Dart never produced a frame. Drawing here, first,
  // turns that into a question with two answers instead of a mystery: if this
  // appears, the engine is fine and the problem is in what follows; if it does
  // not, the problem is below Dart entirely and nothing in `main` could have
  // caught it.
  runApp(BootScreen.app());

  // Named so a failure can say which one. On a device you cannot attach a
  // debugger to — which is most devices, and every TestFlight tester — "it
  // shows white" is otherwise the entire bug report.
  String step = 'loading translations';

  try {
    await EasyLocalization.ensureInitialized().timeout(_startupBudget);

    step = 'connecting to Supabase';
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    ).timeout(_startupBudget);

    // Firebase is only here to deliver push notifications, so a failure to
    // start it must not stop the app starting. On a platform with no
    // configuration — a desktop build during development — this throws, and
    // the app should carry on without notifications rather than not run.
    //
    // Inside the outer try as well as its own: the timeout is what stops a
    // hung initialisation holding the whole launch, and a hang is not
    // something `catch` sees.
    step = 'starting Firebase';
    if (PushService.isSupported) {
      try {
        await Firebase.initializeApp().timeout(_startupBudget);
      } catch (error) {
        debugPrint('Bulkr: Firebase unavailable, push is off — $error');
      }
    }

    // After Firebase and inside the same try, but its own failure is not
    // allowed to stop the app — `start` swallows, and installs Flutter's
    // global error handlers whether or not Firebase came up. From this line
    // on, an exception anywhere in the app is reported rather than lost.
    step = 'starting telemetry';
    await Telemetry.start();
  } catch (error, stackTrace) {
    debugPrint('Bulkr: startup failed while $step — $error');
    debugPrintStack(stackTrace: stackTrace);

    // Best-effort: if the failure was Firebase itself there is nothing to
    // report to, and `recordError` returns quietly. When it was anything else
    // — translations, Supabase — this is the only record that launch died,
    // because the user sees a screen and closes it.
    await Telemetry.recordError(error, stackTrace,
        reason: 'startup failed while $step', fatal: true);
    await Telemetry.send(AnalyticsEvent.startupFailed(
      step: step,
      errorType: error.runtimeType.toString(),
    ));

    // A screen that says what happened, rather than a white one that does not.
    runApp(StartupFailureScreen.app(
      step: step,
      error: error,
      stackTrace: stackTrace,
    ));
    return;
  }

  unawaited(Telemetry.send(
    AnalyticsEvent.startupCompleted(milliseconds: launch.elapsedMilliseconds),
  ));

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      child: const BulkrApp(),
    ),
  );
}

class BulkrApp extends StatefulWidget {
  const BulkrApp({super.key});

  @override
  State<BulkrApp> createState() => _BulkrAppState();
}

class _BulkrAppState extends State<BulkrApp> {
  late final AuthRepository _authRepository;
  late final AppPreferences _preferences;
  late final UserRepository _userRepository;
  late final FoodRepository _foodRepository;
  late final MealRepository _mealRepository;
  late final FollowRepository _followRepository;
  late final GroupRepository _groupRepository;
  late final ChallengeRepository _challengeRepository;
  late final EntitlementRepository _entitlementRepository;
  late final AdsService _adsService;
  late final ModerationRepository _moderationRepository;
  late final ChatRepository _chatRepository;
  late final NotificationRepository _notificationRepository;
  late final PushRepository _pushRepository;
  late final PushService _pushService;
  late final PostRepository _postRepository;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository();
    _preferences = AppPreferences();
    _userRepository = UserRepository();
    // One food repository for the whole app: it owns an HTTP client that is
    // kept alive across searches rather than reopened per query.
    _foodRepository = FoodRepository();
    _mealRepository = MealRepository(foodRepository: _foodRepository);
    _followRepository = FollowRepository();
    _groupRepository = GroupRepository();
    _challengeRepository = ChallengeRepository();
    // Shares the one [AppPreferences] rather than making a second: the
    // cached entitlement is cleared by `AppPreferences.clear()` on sign-out,
    // and a second instance would mean one of them still holding the last
    // account's answer.
    _entitlementRepository = EntitlementRepository(
      preferences: _preferences,
    );
    // Built here, started from the shell. Starting it at launch would put a
    // consent form and iOS's tracking prompt in front of somebody who has not
    // seen the app yet — and the tracking prompt is shown once per install,
    // ever, so the moment it is asked is the only moment there is.
    _adsService = AdsService(preferences: _preferences);
    _moderationRepository = ModerationRepository();
    _chatRepository = ChatRepository();
    _notificationRepository = NotificationRepository();
    _pushRepository = PushRepository();
    _pushService = PushService(repository: _pushRepository);
    // For You is "posts by people you follow, plus posts in your groups", and
    // a challenge post carries a challenge — so the post repository reads all
    // three through the repositories that own them rather than querying their
    // tables itself.
    _postRepository = PostRepository(
      followRepository: _followRepository,
      groupRepository: _groupRepository,
      challengeRepository: _challengeRepository,
      // Hidden posts are filtered inside the feed's own paging, so the
      // repository that owns them is handed in rather than built twice.
      moderationRepository: _moderationRepository,
    );
    // Built once: rebuilding a GoRouter throws away the navigation stack.
    _router = AppRouter.build(
      authRepository: _authRepository,
      preferences: _preferences,
    );
  }

  @override
  void dispose() {
    _foodRepository.dispose();
    _adsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      // The create-meal screen builds its own cubit and needs both of these,
      // so they are reachable from anywhere under the router rather than
      // threaded down through the shell.
      providers: [
        RepositoryProvider.value(value: _mealRepository),
        RepositoryProvider.value(value: _foodRepository),
        // The composer is pushed above the shell and builds its own cubit, so
        // it reads both of these off the context rather than being handed them.
        RepositoryProvider.value(value: _postRepository),
        RepositoryProvider.value(value: _followRepository),
        RepositoryProvider.value(value: _groupRepository),
        RepositoryProvider.value(value: _challengeRepository),
        // Read directly by the upgrade screen, which re-asks the server the
        // moment a purchase completes.
        RepositoryProvider.value(value: _entitlementRepository),
        // Read by every banner and by every screen that finishes something.
        // See lib/core/ad_moment.dart for why the call sites are one line.
        RepositoryProvider.value(value: _adsService),
        // The blocked-people screen reads this directly — one query and one
        // write, opened rarely, and a cubit for it would say nothing more.
        RepositoryProvider.value(value: _moderationRepository),
        // The profile's edit sheet writes name and bio, so it needs the
        // repository that owns `users`.
        RepositoryProvider.value(value: _userRepository),
        // Direct messages. Held here rather than created per thread because a
        // thread screen and the inbox behind it must talk to the same client —
        // and because the realtime channel a thread opens is torn down by the
        // cubit, not by the repository.
        RepositoryProvider.value(value: _chatRepository),
        RepositoryProvider.value(value: _notificationRepository),
        // Registered so a screen can reach it directly. Today only
        // [PushService] does — see supabase/functions/send-push/README.md for
        // what is on the other end of it.
        RepositoryProvider.value(value: _pushRepository),
        // The plugin side, for the shell to register a token and sign-out to
        // remove it.
        RepositoryProvider.value(value: _pushService),
      ],
      child: MultiBlocProvider(
      // Above the router on purpose — onboarding answers have to survive
      // navigation between the five steps.
      providers: [
        BlocProvider(
          create: (_) => AuthCubit(
            authRepository: _authRepository,
            preferences: _preferences,
          ),
        ),
        BlocProvider(
          create: (_) => OnboardingCubit(userRepository: _userRepository),
        ),
        BlocProvider(
          create: (_) => ProfileCubit(
            userRepository: _userRepository,
            preferences: _preferences,
          ),
        ),
        BlocProvider(
          create: (_) => MealsCubit(mealRepository: _mealRepository),
        ),
        BlocProvider(
          create: (_) => TrackerCubit(
            mealRepository: _mealRepository,
            // Its own read of the `users` row, for the targets the day is
            // measured against — see the note on the cubit.
            userRepository: _userRepository,
          ),
        ),
        // App-wide so the unread badge in the feed header and the inbox
        // itself are the same list. Loaded lazily: `lazy: false` would fire a
        // request before anybody is signed in.
        BlocProvider(
          create: (_) => ConversationsCubit(chatRepository: _chatRepository),
        ),
        // Also app-wide, and for the same reason: the dot on the feed header
        // and the screen behind it have to be the same list.
        BlocProvider(
          create: (_) =>
              NotificationsCubit(repository: _notificationRepository),
        ),
        // App-wide because almost every surface asks whether this account is
        // premium — the feed before drawing a banner, the meal library before
        // saving another meal, the tracker before scrolling past last week.
        // One answer for all of them, or they disagree.
        BlocProvider(
          create: (_) =>
              EntitlementCubit(repository: _entitlementRepository)..load(),
        ),
        BlocProvider(
          create: (_) => FeedCubit(
            postRepository: _postRepository,
            // Taking a meal off a post writes to the meal library, so the feed
            // needs the repository that owns it.
            mealRepository: _mealRepository,
            challengeRepository: _challengeRepository,
          ),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (_, child) {
          return MaterialApp.router(
            title: 'Bulkr',
            debugShowCheckedModeBanner: false,
            routerConfig: _router,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              scaffoldBackgroundColor: Colors.black,
              colorScheme: const ColorScheme.dark(
                primary: AppColors.primaryNeon,
                onPrimary: Colors.black,
                surface: Color(0xFF1A1A1A),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}
