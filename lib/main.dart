import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'cubit/auth/auth_cubit.dart';
import 'cubit/feed/feed_cubit.dart';
import 'cubit/meals/meals_cubit.dart';
import 'cubit/onboarding/onboarding_cubit.dart';
import 'cubit/profile/profile_cubit.dart';
import 'data/app_preferences.dart';
import 'data/auth_repository.dart';
import 'data/food_repository.dart';
import 'data/meal_repository.dart';
import 'data/post_repository.dart';
import 'data/user_repository.dart';
import 'go_router/router_config.dart';
import 'styles/app_color.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

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
    _postRepository = PostRepository();
    // Built once: rebuilding a GoRouter throws away the navigation stack.
    _router = AppRouter.build(
      authRepository: _authRepository,
      preferences: _preferences,
    );
  }

  @override
  void dispose() {
    _foodRepository.dispose();
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
          create: (_) => FeedCubit(postRepository: _postRepository),
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
