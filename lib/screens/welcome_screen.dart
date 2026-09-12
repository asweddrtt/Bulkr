import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/legal_config.dart';
import '../core/telemetry.dart';
import '../cubit/auth/auth_cubit.dart';
import '../cubit/onboarding/onboarding_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../go_router/app_routes.dart';
import '../styles/app_color.dart';
import '../widgets/animations/entrance.dart';
import '../widgets/welcome_button.dart';

/// Step 1 — identity.
///
/// Kept deliberately frictionless: two OAuth buttons, no password field, no
/// profile questions. The Supabase Auth session is all this screen creates;
/// the public `users` row is written once at the end of the flow.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthCubit, AuthenticationState>(
      listenWhen: (previous, current) =>
          previous.status != current.status ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) async {
        if (state.isAuthenticated) {
          // Hand the provider's identity to the onboarding flow, which uses it
          // for display_name, avatar_url and the suggested username.
          context.read<OnboardingCubit>().adoptIdentity(state.user!);

          // Returning users go straight in. Without this check every sign-in
          // replays onboarding and its final upsert overwrites the profile
          // that already exists, which reads as a brand new account.
          final router = GoRouter.of(context);
          final completed =
              await context.read<ProfileCubit>().hasCompletedOnboarding();
          router.go(completed ? AppRoutes.home : AppRoutes.biometrics);
          return;
        }

        if (state.status == AuthStatus.failure && state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF2A2A2A),
                content: Text(
                  _friendlyError(state.errorMessage!),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
                ),
              ),
            );
        }
      },
      child: Scaffold(
        extendBody: true,
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/background.png'),
              fit: BoxFit.cover,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // First impression: the wordmark lands, then the buttons follow.
              // Rising from below suits a column anchored to the bottom of the
              // screen — the content arrives from the direction it lives in.
              children: staggered(
                [
                // --- 1. HEADER ---
                Text(
                  'welcome_time_to'.tr(),
                  style: GoogleFonts.anton(
                    fontSize: 72.sp,
                    height: 0.9,
                    letterSpacing: -2,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'welcome_grow'.tr(),
                  style: GoogleFonts.anton(
                    fontSize: 72.sp,
                    height: 0.9,
                    letterSpacing: -2,
                    color: AppColors.primaryNeon,
                  ),
                ),
                SizedBox(height: 23.h),
                Text(
                  'welcome_subtitle'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w500,
                    color: AppColors.offWhiteMuted,
                  ),
                ),
                SizedBox(height: 40.h),

                // --- 2. SIGN IN ---
                BlocBuilder<AuthCubit, AuthenticationState>(
                  builder: (context, state) {
                    final cubit = context.read<AuthCubit>();
                    final busy = state.isLoading;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PrimaryIconButton(
                          label: 'continue_apple'.tr(),
                          icon: Icons.apple,
                          isBusy: state.pendingProvider == AuthProviderKind.apple,
                          onPressed: busy ? null : cubit.signInWithApple,
                        ),
                        SizedBox(height: 16.h),
                        PrimaryIconButton(
                          label: 'continue_google'.tr(),
                          customIcon: Image.asset(
                            'assets/images/google.png',
                            height: 28.sp,
                          ),
                          isBusy:
                              state.pendingProvider == AuthProviderKind.google,
                          onPressed: busy ? null : cubit.signInWithGoogle,
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 40.h),

                // --- 3. FOOTER ---
                const _AgreementFooter(),
              ],
                step: const Duration(milliseconds: 70),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Cancellation is a translated key; anything from Supabase is passed
  /// through as-is so real failures stay diagnosable.
  String _friendlyError(String message) =>
      message == 'auth_error_cancelled' ? 'auth_error_cancelled'.tr() : message;
}

/// "By continuing you agree to the Policy" — and the Policy opens.
///
/// This used to be a `RichText` whose second span was underlined and carried
/// no recogniser, so it looked like a link and was not one. Worse than a
/// missing link: it asked for agreement to a document nobody could read.
///
/// Now it is a link when there is something to link to, and plain text when
/// there is not — see [LegalConfig] for why that is the honest default and
/// what has to be set before release.
class _AgreementFooter extends StatelessWidget {
  const _AgreementFooter();

  @override
  Widget build(BuildContext context) {
    final TextStyle base = GoogleFonts.jetBrainsMono(
      fontSize: 11.sp,
      fontWeight: FontWeight.bold,
      color: AppColors.offWhiteMuted,
    );

    if (!LegalConfig.hasPrivacyPolicy) {
      // No underline and no recogniser: the sentence still sets expectations,
      // without the styling that promises a tap will do something.
      return Text(
        '${'agree_prefix'.tr()}${'policy'.tr()}',
        textAlign: TextAlign.center,
        style: base,
      );
    }

    return Semantics(
      link: true,
      label: 'policy'.tr(),
      child: GestureDetector(
        onTap: () => _open(context),
        // The text is 11sp and the word is short, so the row it sits in is the
        // tap target rather than the glyphs themselves — a link nobody can hit
        // is the same as no link.
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(text: 'agree_prefix'.tr(), style: base),
                TextSpan(
                  text: 'policy'.tr(),
                  style: base.copyWith(
                    color: Colors.white,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Uri url = Uri.parse(LegalConfig.privacyPolicyUrl);

    // `externalApplication` rather than an in-app web view: a privacy policy
    // is a document somebody may want to keep, search or send to themselves,
    // and the browser does all three.
    bool opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      await Telemetry.recordError(error, stackTrace,
          reason: 'opening the privacy policy');
    }

    if (opened) return;

    // A device with no browser is close to impossible, but silently doing
    // nothing is the failure this whole widget exists to remove — so if it
    // cannot be opened, say so rather than repeat the original bug.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2A2A2A),
          content: Text(
            'policy_unavailable'.tr(),
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
          ),
        ),
      );
  }
}
