import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/auth/auth_cubit.dart';
import '../cubit/onboarding/onboarding_cubit.dart';
import '../go_router/app_routes.dart';
import '../styles/app_color.dart';
import '../widgets/outlined_button.dart';
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
      listener: (context, state) {
        if (state.isAuthenticated) {
          // Hand the provider's identity to the onboarding flow, which uses it
          // for display_name, avatar_url and the suggested username.
          context.read<OnboardingCubit>().adoptIdentity(state.user!);
          context.go(AppRoutes.biometrics);
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
              children: [
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
                        SizedBox(height: 16.h),
                        SecondaryOutlinedButton(
                          label: 'other_options'.tr(),
                          onPressed: busy
                              ? null
                              : () => _showOtherOptions(context),
                        ),
                      ],
                    );
                  },
                ),
                SizedBox(height: 40.h),

                // --- 3. FOOTER ---
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'agree_prefix'.tr(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.offWhiteMuted,
                        ),
                      ),
                      TextSpan(
                        text: 'policy'.tr(),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          color: AppColors.offWhiteMuted,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Placeholder for additional providers. Surfacing a message beats a button
  /// that silently does nothing when tapped.
  void _showOtherOptions(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2A2A2A),
          content: Text(
            'other_options_coming_soon'.tr(),
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
          ),
        ),
      );
  }

  /// Cancellation is a translated key; anything from Supabase is passed
  /// through as-is so real failures stay diagnosable.
  String _friendlyError(String message) =>
      message == 'auth_error_cancelled' ? 'auth_error_cancelled'.tr() : message;
}
