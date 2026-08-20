import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'go_router/router_config.dart';
import 'state/profile_controller.dart';
import 'state/profile_scope.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Load the signed-in athlete before the first frame so the router can send
  // a returning user straight to their profile.
  final ProfileController controller = ProfileController();
  await controller.load();

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')], // Add your supported locales here
      path: 'assets/translations', // Ensure this path matches your pubspec.yaml assets
      fallbackLocale: const Locale('en', 'US'),
      child: MyApp(controller: controller),
    ),
  );
}

class MyApp extends StatefulWidget {
  final ProfileController controller;

  const MyApp({super.key, required this.controller});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router = AppRouter.build(widget.controller);

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      // Replace with the exact width/height of your Figma/UI design mockup
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, child) {
        return ProfileScope(
          controller: widget.controller,
          child: MaterialApp.router(
            title: 'Bulkr',
            routerConfig: _router,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            ),
          ),
        );
      },
    );
  }
}
