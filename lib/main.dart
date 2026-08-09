import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'cubit/auth/auth_cubit.dart';
import 'cubit/onboarding/onboarding_cubit.dart';
import 'data/auth_repository.dart';
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
  late final UserRepository _userRepository;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authRepository = AuthRepository();
    _userRepository = UserRepository();
    // Built once: rebuilding a GoRouter throws away the navigation stack.
    _router = AppRouter.build(authRepository: _authRepository);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      // Above the router on purpose — onboarding answers have to survive
      // navigation between the five steps.
      providers: [
        BlocProvider(
          create: (_) => AuthCubit(authRepository: _authRepository),
        ),
        BlocProvider(
          create: (_) => OnboardingCubit(userRepository: _userRepository),
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
    );
  }
}
