import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cubit/onboarding/onboarding_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../data/app_preferences.dart';
import '../data/auth_repository.dart';
import '../go_router/app_routes.dart';
import '../styles/app_color.dart';

/// Decides where a launch goes, so a signed-in user is never asked to sign in
/// again.
///
/// Supabase already persists the session — it writes to shared preferences and
/// [Supabase.initialize] restores it before this screen builds — so the session
/// was never the thing being lost. What was missing is this: the app opened on
/// the sign-in screen every time regardless, and tapping through it was the only
/// way forward.
///
/// Three destinations, and the middle one is why this cannot live in the
/// router's `redirect`: telling a returning user apart from one who abandoned
/// onboarding halfway needs a database read, and `redirect` is synchronous.
///
///   * no session            -> sign in
///   * session, onboarded    -> straight into the app
///   * session, not finished -> back into onboarding where it stopped
///
/// The third case has to hand the session's identity to [OnboardingCubit] the
/// same way the sign-in screen does. That cubit is where onboarding keeps the
/// user id it eventually writes against, and it starts empty on every launch —
/// so a user who reaches onboarding through here rather than through sign-in
/// would walk all four steps and only find out at the very end that there was
/// nothing to attach them to.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.authRepository,
    required this.preferences,
  });

  final AuthRepository authRepository;
  final AppPreferences preferences;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the router is settled before it is navigated.
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    // Both read off the context before the first await, so nothing here reaches
    // through a BuildContext that may have gone by the time it resolves.
    final GoRouter router = GoRouter.of(context);
    final ProfileCubit profile = context.read<ProfileCubit>();
    final OnboardingCubit onboarding = context.read<OnboardingCubit>();

    final User? user = widget.authRepository.currentUser;

    if (!widget.authRepository.hasSession || user == null) {
      router.go(AppRoutes.welcome);
      return;
    }

    final String userId = user.id;

    // The device already knows, for a user who has been here before, so launch
    // costs no round trip — and works with no signal at all.
    if (await widget.preferences.hasCompletedOnboarding(userId)) {
      if (!mounted) return;
      router.go(AppRoutes.home);
      return;
    }

    // Otherwise ask, and remember the answer. False on failure, so a network
    // problem sends the user to onboarding rather than into an app with no
    // profile behind it — and finishing onboarding again writes the same row
    // rather than a second one.
    final bool completed = await profile.hasCompletedOnboarding();

    if (!mounted) return;

    if (completed) {
      router.go(AppRoutes.home);
      return;
    }

    // Seed the flow before entering it, not after: step 2 reads the suggested
    // username in `initState`, and the final step needs the user id.
    onboarding.adoptIdentity(user);
    router.go(AppRoutes.biometrics);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'app_name'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                fontSize: 34.sp,
                color: AppColors.primaryNeon,
                letterSpacing: 3,
              ),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: 22.w,
              height: 22.w,
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.darkBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
