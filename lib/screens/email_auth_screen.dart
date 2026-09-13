import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/email_credentials.dart';
import '../cubit/auth/auth_cubit.dart';
import '../styles/app_color.dart';

/// Signing in, or creating an account, with an address and a password.
///
/// ## One screen, two modes
///
/// Sign-in and sign-up are the same three fields with one hidden, and every
/// app that splits them into two screens makes somebody who guessed wrong go
/// back and retype their email. The toggle at the bottom switches mode and
/// keeps what has been typed.
///
/// ## Where the messages come from
///
/// Nothing here decides what went wrong. Local validation lives in
/// [EmailCredentials], server failures are named in `AuthErrors`, and both
/// arrive as `state.errorMessage` — so the sentence a user reads is the same
/// whether the problem was caught on the phone or by Supabase.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  static Future<void> open(BuildContext context) {
    final AuthCubit auth = context.read<AuthCubit>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => BlocProvider<AuthCubit>.value(
          value: auth,
          child: const EmailAuthScreen(),
        ),
      ),
    );
  }

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _creatingAccount = false;
  bool _obscured = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final AuthCubit auth = context.read<AuthCubit>();

    if (_creatingAccount) {
      auth.signUpWithEmail(
        email: _email.text,
        password: _password.text,
        confirmation: _confirm.text,
      );
      return;
    }

    auth.signInWithEmail(email: _email.text, password: _password.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, elevation: 0),
      body: BlocConsumer<AuthCubit, AuthenticationState>(
        listenWhen:
            (AuthenticationState previous, AuthenticationState current) =>
                previous.isAuthenticated != current.isAuthenticated &&
                current.isAuthenticated,
        // A session means the router is about to move; closing this first
        // stops it sitting over the app the user has just been let into.
        listener: (BuildContext context, AuthenticationState state) =>
            Navigator.of(context).maybePop(),
        builder: (BuildContext context, AuthenticationState state) {
          final bool busy =
              state.isLoading &&
              state.pendingProvider == AuthProviderKind.email;

          return ListView(
            padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 32.h),
            children: <Widget>[
              Text(
                (_creatingAccount ? 'auth_sign_up_title' : 'auth_sign_in_title')
                    .tr()
                    .toUpperCase(),
                style: GoogleFonts.anton(
                  color: Colors.white,
                  fontSize: 26.sp,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 22.h),
              _AuthField(
                label: 'auth_email_label'.tr(),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const <String>[AutofillHints.email],
              ),
              SizedBox(height: 12.h),
              _AuthField(
                label: 'auth_password_label'.tr(),
                controller: _password,
                obscured: _obscured,
                onToggleObscured: () => setState(() => _obscured = !_obscured),
                // `newPassword` on sign-up is what makes a password manager
                // offer to generate and save one instead of autofilling the
                // wrong thing.
                autofillHints: <String>[
                  _creatingAccount
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
              ),
              if (_creatingAccount) ...<Widget>[
                SizedBox(height: 12.h),
                _AuthField(
                  label: 'auth_password_confirm_label'.tr(),
                  controller: _confirm,
                  obscured: _obscured,
                  autofillHints: const <String>[AutofillHints.newPassword],
                ),
                SizedBox(height: 8.h),
                Text(
                  'auth_password_hint'.tr(
                    namedArgs: <String, String>{
                      'count': '${EmailCredentials.minPasswordLength}',
                    },
                  ),
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10.sp,
                  ),
                ),
              ],
              if (state.emailNotice != null) ...<Widget>[
                SizedBox(height: 16.h),
                _Notice(
                  message: state.emailNotice!.tr(),
                  // Offered only when there is an address to send to, which is
                  // the address they just used — never one they could type.
                  onResend: state.awaitingConfirmationFor == null
                      ? null
                      : () => context.read<AuthCubit>().resendConfirmation(),
                ),
              ],
              if (state.errorMessage != null) ...<Widget>[
                SizedBox(height: 16.h),
                _Problem(
                  message: state.errorMessage!,
                  onResend: state.awaitingConfirmationFor == null
                      ? null
                      : () => context.read<AuthCubit>().resendConfirmation(),
                ),
              ],
              SizedBox(height: 22.h),
              SizedBox(
                height: 50.h,
                child: ElevatedButton(
                  onPressed: busy ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    disabledBackgroundColor: const Color(0xFF2A2A2A),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: busy
                      ? SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child: const CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          (_creatingAccount
                                  ? 'auth_sign_up_action'
                                  : 'auth_sign_in_action')
                              .tr()
                              .toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 14.h),
              Center(
                child: TextButton(
                  onPressed: () {
                    context.read<AuthCubit>().clearEmailNotice();
                    setState(() => _creatingAccount = !_creatingAccount);
                  },
                  child: Text(
                    (_creatingAccount ? 'auth_to_sign_in' : 'auth_to_sign_up')
                        .tr(),
                    style: GoogleFonts.inter(
                      color: AppColors.primaryNeon,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (!_creatingAccount)
                Center(
                  child: TextButton(
                    onPressed: busy ? null : () => _openReset(context),
                    child: Text(
                      'auth_forgot'.tr(),
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 11.sp,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The reset sheet, seeded with whatever is already in the email field.
  ///
  /// Somebody who has just failed to sign in has typed their address a moment
  /// ago; asking for it again is the kind of small rudeness that makes a
  /// forgotten password feel worse than it is.
  Future<void> _openReset(BuildContext context) async {
    final AuthCubit auth = context.read<AuthCubit>();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider<AuthCubit>.value(
        value: auth,
        child: _ResetSheet(initialEmail: _email.text),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.autofillHints,
    this.obscured = false,
    this.onToggleObscured,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final bool obscured;
  final VoidCallback? onToggleObscured;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscured,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: false,
      // Off, and it matters: a keyboard that capitalises the first letter
      // turns `ali@x.com` into `Ali@x.com`, and the two are different rows.
      textCapitalization: TextCapitalization.none,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 11.sp),
        filled: true,
        fillColor: const Color(0xFF151515),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
        suffixIcon: onToggleObscured == null
            ? null
            : Semantics(
                button: true,
                label: (obscured ? 'a11y_show_password' : 'a11y_hide_password')
                    .tr(),
                child: IconButton(
                  icon: Icon(
                    obscured ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white38,
                    size: 18.sp,
                  ),
                  onPressed: onToggleObscured,
                ),
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.primaryNeon),
        ),
      ),
    );
  }
}

/// Something went right, and there is still something to do about it.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.onResend});

  final String message;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return _Banner(
      tint: AppColors.primaryNeon,
      icon: Icons.mark_email_unread_outlined,
      message: message,
      onResend: onResend,
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, this.onResend});

  final String message;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return _Banner(
      tint: const Color(0xFFFF5722),
      icon: Icons.error_outline,
      message: message,
      onResend: onResend,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.tint,
    required this.icon,
    required this.message,
    this.onResend,
  });

  final Color tint;
  final IconData icon;
  final String message;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: tint.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: tint, size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11.sp,
                    height: 1.5,
                  ),
                ),
                if (onResend != null)
                  TextButton(
                    onPressed: onResend,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size(0, 28.h),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'auth_resend'.tr(),
                      style: GoogleFonts.inter(
                        color: tint,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResetSheet extends StatefulWidget {
  const _ResetSheet({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ResetSheet> createState() => _ResetSheetState();
}

class _ResetSheetState extends State<_ResetSheet> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail,
  );

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 16.h),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'auth_reset_title'.tr().toUpperCase(),
                style: GoogleFonts.anton(
                  color: Colors.white,
                  fontSize: 16.sp,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                'auth_reset_body'.tr(),
                style: GoogleFonts.inter(
                  color: Colors.white54,
                  fontSize: 11.sp,
                ),
              ),
              SizedBox(height: 14.h),
              _AuthField(
                label: 'auth_email_label'.tr(),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const <String>[AutofillHints.email],
              ),
              SizedBox(height: 14.h),
              SizedBox(
                width: double.infinity,
                height: 46.h,
                child: ElevatedButton(
                  onPressed: () {
                    context.read<AuthCubit>().sendPasswordReset(_email.text);
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                  child: Text(
                    'auth_reset_action'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
