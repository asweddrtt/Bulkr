import 'dart:convert';
import 'dart:io';

import 'package:bulkr/core/auth_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Telling somebody what to do next when sign-in fails.
///
/// The generic mapper calls all of these "the server said no", which is true
/// and useless: a wrong password, an unconfirmed address and a rate limit need
/// three completely different next steps, and only one of them is the user's
/// fault.
void main() {
  AuthException failure(String code, [String message = 'failed']) =>
      AuthException(message, code: code);

  group('what gets its own answer', () {
    late final Map<String, dynamic> translations = jsonDecode(
      File('assets/translations/en-US.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('every sentence it can produce exists', () {
      // `.tr()` answers a missing key with the key, so a typo here ships
      // "auth_failed_weak" to somebody who just failed to sign up.
      for (final String key in const <String>[
        'auth_failed_credentials',
        'auth_failed_unconfirmed',
        'auth_failed_exists',
        'auth_failed_weak',
        'auth_failed_email_limit',
        'auth_failed_too_many',
        'auth_failed_same_password',
        'auth_failed_signup_off',
        'auth_email_malformed',
      ]) {
        expect(translations, contains(key));
      }
    });
  });

  group('an unconfirmed address', () {
    test('is recognised by code', () {
      expect(AuthErrors.needsConfirmation(failure('email_not_confirmed')),
          isTrue);
    });

    test('and by message, for a server that sends no code', () {
      expect(
        AuthErrors.needsConfirmation(
          const AuthException('Email not confirmed'),
        ),
        isTrue,
      );
    });

    test('is not confused with a wrong password', () {
      // These two are adjacent and the difference is a button: one offers to
      // resend, the other cannot.
      expect(
        AuthErrors.needsConfirmation(failure('invalid_credentials')),
        isFalse,
      );
    });
  });

  group('the email rate limit', () {
    test('is recognised, because it is not the user\'s fault', () {
      // On a project still using Supabase's built-in SMTP this is two emails
      // an hour, and no amount of retrying helps — the fix is custom SMTP.
      expect(
        AuthErrors.isEmailRateLimited(failure('over_email_send_rate_limit')),
        isTrue,
      );
      expect(
        AuthErrors.isEmailRateLimited(
          const AuthException('email rate limit exceeded'),
        ),
        isTrue,
      );
    });

    test('is not the same as too many sign-in attempts', () {
      expect(
        AuthErrors.isEmailRateLimited(failure('over_request_rate_limit')),
        isFalse,
      );
      expect(AuthErrors.refusal(failure('over_request_rate_limit')), isNotNull);
    });
  });

  group('what is deliberately not distinguished', () {
    test('a wrong password and an unknown address read the same', () {
      // Saying "no account with that email" confirms which addresses are
      // registered, one guess at a time. Supabase answers both with
      // `invalid_credentials` for the same reason.
      final String? wrongPassword =
          AuthErrors.refusal(failure('invalid_credentials'));

      expect(wrongPassword, isNotNull);
      expect(wrongPassword!.toLowerCase(), isNot(contains('no account')));
      expect(wrongPassword.toLowerCase(), isNot(contains('not found')));
      expect(wrongPassword.toLowerCase(), isNot(contains('exist')));
    });
  });

  group('anything else falls through', () {
    test('an unknown auth code gets no special sentence', () {
      // The generic mapper still separates offline from server from
      // permission, which is better than inventing a specific claim.
      expect(AuthErrors.refusal(failure('something_new')), isNull);
    });

    test('a non-auth error is not an auth refusal', () {
      expect(AuthErrors.refusal(Exception('offline')), isNull);
      expect(AuthErrors.needsConfirmation(Exception('offline')), isFalse);
      expect(AuthErrors.isEmailRateLimited('nope'), isFalse);
    });
  });
}
