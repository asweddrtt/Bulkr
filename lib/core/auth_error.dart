import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turning a Supabase auth failure into a sentence somebody can act on.
///
/// The generic error mapper would call all of these "the server said no",
/// which for sign-in is both true and useless — the difference between a wrong
/// password, an unconfirmed address and a rate limit is the difference between
/// three completely different next steps.
///
/// ## What is deliberately not distinguished
///
/// A wrong password and an address with no account get the **same** sentence.
/// Telling somebody "no account with that email" confirms which addresses are
/// registered to anyone who asks, one guess at a time — and Supabase itself
/// answers both with `invalid_credentials` for exactly that reason. Being more
/// helpful here would mean being more helpful to whoever is enumerating.
class AuthErrors {
  const AuthErrors._();

  /// The address exists but has never been confirmed.
  ///
  /// Its own predicate because it is the one failure with a button attached:
  /// the screen offers to send the email again rather than only explaining.
  static bool needsConfirmation(Object error) =>
      error is AuthException &&
      (error.code == 'email_not_confirmed' ||
          error.message.toLowerCase().contains('not confirmed'));

  /// Too many emails, too fast.
  ///
  /// Worth its own answer because on a project still using Supabase's built-in
  /// SMTP this is not the user's fault and not transient in the way a network
  /// blip is: the default allowance is two an hour. See
  /// `docs/BEFORE_RELEASE.md` — the fix is custom SMTP, not patience.
  static bool isEmailRateLimited(Object error) =>
      error is AuthException &&
      (error.code == 'over_email_send_rate_limit' ||
          error.message.toLowerCase().contains('rate limit'));

  /// The sentence to show, or null when this is not an auth failure the app
  /// has anything specific to say about.
  static String? refusal(Object error) {
    if (error is! AuthException) return null;

    final String code = error.code ?? '';
    final String message = error.message.toLowerCase();

    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return 'auth_failed_credentials'.tr();
    }

    if (needsConfirmation(error)) return 'auth_failed_unconfirmed'.tr();

    if (code == 'user_already_exists' ||
        code == 'email_exists' ||
        message.contains('already registered')) {
      return 'auth_failed_exists'.tr();
    }

    if (code == 'weak_password' || message.contains('password should be')) {
      return 'auth_failed_weak'.tr();
    }

    if (isEmailRateLimited(error)) return 'auth_failed_email_limit'.tr();

    if (code == 'over_request_rate_limit') {
      return 'auth_failed_too_many'.tr();
    }

    if (code == 'email_address_invalid') return 'auth_email_malformed'.tr();

    if (code == 'same_password') return 'auth_failed_same_password'.tr();

    if (code == 'signup_disabled') return 'auth_failed_signup_off'.tr();

    // The email layer refused to send. Supabase reports it as
    // `unexpected_failure`, which is the code it uses for "something broke
    // that we did not anticipate" — here it means SMTP is misconfigured, or
    // the project is still on the built-in sender, which only delivers to the
    // organisation's own team members and refuses everybody else.
    //
    // Worth its own sentence rather than the generic "something went wrong"
    // because there *is* a way forward for the person reading it: the OAuth
    // buttons on the same screen do not touch email at all.
    if (code == 'unexpected_failure' && message.contains('error sending')) {
      return 'auth_failed_email_send'.tr();
    }

    // Everything else falls through to the generic mapper, which at least
    // separates offline from server from permission.
    return null;
  }
}
