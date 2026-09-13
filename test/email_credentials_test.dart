import 'package:bulkr/core/email_credentials.dart';
import 'package:flutter_test/flutter_test.dart';

/// The checks that run before anything reaches the network.
///
/// Two of these are not style preferences but real support tickets:
/// lower-casing the address, because every phone keyboard capitalises the
/// first letter and `Ali@x.com` is a different row from `ali@x.com`; and
/// *not* trimming the password, because a space is a legitimate character and
/// silently removing one means the password that worked at sign-up fails at
/// sign-in.
void main() {
  EmailCredentials make(String email, String password) =>
      EmailCredentials.from(email: email, password: password);

  group('normalising what was typed', () {
    test('the address is trimmed and lower-cased', () {
      // The phone keyboard did this, not the user.
      expect(make('  Ali@Example.COM ', 'hunter2a').email, 'ali@example.com');
    });

    test('the password is left exactly alone', () {
      // Including the spaces. Trimming here is the bug where an account can be
      // created with a password that can never be typed again.
      expect(make('a@b.co', '  spaced  ').password, '  spaced  ');
      expect(make('a@b.co', 'CaseMatters1').password, 'CaseMatters1');
    });
  });

  group('what counts as an email address', () {
    test('ordinary addresses pass', () {
      for (final String address in const <String>[
        'ali@example.com',
        'ali.rashid@example.co.uk',
        'ali+bulkr@example.com',
        'a@b.co',
        "o'brien@example.com",
      ]) {
        expect(EmailCredentials.looksLikeEmail(address), isTrue,
            reason: address);
      }
    });

    test('the typos people actually make do not', () {
      for (final String address in const <String>[
        '',
        'ali',
        'ali@',
        '@example.com',
        'ali@example',
        'ali example@x.com',
        'ali@@example.com',
      ]) {
        expect(EmailCredentials.looksLikeEmail(address), isFalse,
            reason: address);
      }
    });

    test('the check is loose on purpose', () {
      // RFC 5322 admits addresses no regex gets right, and every strict one
      // rejects somebody's real address. The email arriving is the only test
      // that proves anything, so this only has to catch a slip.
      expect(EmailCredentials.looksLikeEmail('ali@mail.example.museum'), isTrue);
    });
  });

  group('signing in', () {
    test('needs both halves', () {
      expect(make('', 'pw').signInProblem, CredentialProblem.emailEmpty);
      expect(make('a@b.co', '').signInProblem, CredentialProblem.passwordEmpty);
      expect(make('nope', 'pw').signInProblem, CredentialProblem.emailMalformed);
    });

    test('does not apply the sign-up password rules', () {
      // An account made before the rules tightened still has to be able to get
      // in. Refusing at the door because a password is now "too short" locks
      // out the people who joined earliest, who are the last ones to deserve
      // it.
      expect(make('a@b.co', 'old').signInProblem, isNull);
    });
  });

  group('creating an account', () {
    test('accepts a reasonable password', () {
      expect(make('a@b.co', 'bulking24').signUpProblem(), isNull);
    });

    test('rejects a short one', () {
      expect(
        make('a@b.co', 'bulk1').signUpProblem(),
        CredentialProblem.passwordTooShort,
      );
    });

    test('wants a letter and a number, and nothing more ornate', () {
      expect(
        make('a@b.co', 'bulkingbulking').signUpProblem(),
        CredentialProblem.passwordTooSimple,
      );
      expect(
        make('a@b.co', '1234567890').signUpProblem(),
        CredentialProblem.passwordTooSimple,
      );
      // No symbol required: those rules produce `Password1!`, which is worse
      // than a long simple one, and length is doing the real work.
      expect(make('a@b.co', 'bulking24').signUpProblem(), isNull);
    });

    test('checks the confirmation when one is given', () {
      expect(
        make('a@b.co', 'bulking24').signUpProblem(confirmation: 'bulking25'),
        CredentialProblem.passwordMismatch,
      );
      expect(
        make('a@b.co', 'bulking24').signUpProblem(confirmation: 'bulking24'),
        isNull,
      );
    });

    test('the address is checked before the password', () {
      // So somebody who mistypes both is told about the field they are
      // looking at rather than the one below it.
      expect(
        make('nope', 'x').signUpProblem(),
        CredentialProblem.emailMalformed,
      );
    });
  });

  group('resetting a password', () {
    test('needs only a usable address', () {
      expect(EmailCredentials.resetProblem('ali@example.com'), isNull);
      expect(
        EmailCredentials.resetProblem(''),
        CredentialProblem.emailEmpty,
      );
      expect(
        EmailCredentials.resetProblem('ali@'),
        CredentialProblem.emailMalformed,
      );
    });

    test('tolerates the spacing a keyboard adds', () {
      expect(EmailCredentials.resetProblem('  Ali@Example.com '), isNull);
    });
  });

  test('every problem has a message key', () {
    // A missing one ships the enum's name to a user.
    for (final CredentialProblem problem in CredentialProblem.values) {
      final String key = EmailCredentials.messageKey(problem);
      expect(key, startsWith('auth_'));
      expect(key, isNot(contains('Instance of')));
    }
  });
}
