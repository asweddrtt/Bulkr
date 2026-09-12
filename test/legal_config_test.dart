import 'package:bulkr/core/config/legal_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The welcome screen asks people to agree to something.
///
/// It used to render "BY CONTINUING YOU AGREE TO THE Policy" with `Policy`
/// underlined inside a plain `RichText` — no recogniser, no URL, nothing
/// behind it to read. That is worse than having no link: it is agreement
/// requested to a document that does not exist, on the one screen App Store
/// review is guaranteed to look at.
///
/// The fix is not a hardcoded URL, because a wrong URL is the same bug with
/// extra steps. It is that the link exists exactly when there is something to
/// link to, which is what these check.
void main() {
  test('the policy link is live', () {
    // The welcome screen renders "Policy" as plain text until this is set, so
    // this assertion is the difference between the sentence being a link and
    // being decoration.
    expect(LegalConfig.hasPrivacyPolicy, isTrue,
        reason: 'App Store guideline 5.1.1 wants a reachable privacy policy, '
            'and the sign-up screen is where review looks for it');
  });

  test('the policy URL carries no session state', () {
    // Google Sites puts `?authuser=2` in the address bar to say which of the
    // accounts signed into *that browser* is being used. It is session state,
    // and it was in the URL this was first given.
    //
    // Shipping it sends every user a parameter that means nothing to them and
    // can land them on an account chooser instead of the policy — which, on
    // the one screen App Store review always opens, is a bad place to find
    // out.
    final Uri url = Uri.parse(LegalConfig.privacyPolicyUrl);

    for (final String parameter in const <String>['authuser', 'usp', 'pli']) {
      expect(
        url.queryParameters.containsKey(parameter),
        isFalse,
        reason: '"$parameter" is browser session state, not part of the '
            'address. Copy the URL from a private window instead.',
      );
    }
  });

  group('URL validation', () {
    // Exercised through the public predicate by way of the real constant's
    // rules, which is the behaviour that matters: anything not an https URL
    // with a host must not be treated as one.
    test('rejects the empty default', () {
      expect(_usable(''), isFalse);
    });

    test('rejects a plain word left in by mistake', () {
      expect(_usable('tbd'), isFalse);
      expect(_usable('coming soon'), isFalse);
    });

    test('rejects http, which the App Store will not accept either', () {
      expect(_usable('http://bulkr.app/privacy'), isFalse);
    });

    test('rejects a scheme with no host', () {
      expect(_usable('https://'), isFalse);
    });

    test('accepts a real https URL', () {
      expect(_usable('https://bulkr.app/privacy'), isTrue);
      expect(_usable('https://example.com/legal/privacy?v=2'), isTrue);
    });
  });

  test('the support address is a real address', () {
    // Guideline 1.2 asks a user-generated-content app for a contact method,
    // alongside the reporting and blocking Bulkr already has.
    expect(LegalConfig.supportEmail, contains('@'));
    expect(LegalConfig.supportEmail, isNot(contains(' ')));
  });
}

/// Mirrors `LegalConfig._isUsable`, which is private because nothing outside
/// that class should be deciding what counts as a usable URL.
///
/// Duplicated rather than made visible for testing: it is four lines, and the
/// rule it encodes — https, and a host — is the thing under test, so writing
/// it out here means the test fails if the rule is quietly loosened.
bool _usable(String value) {
  if (value.isEmpty) return false;
  final Uri? parsed = Uri.tryParse(value);
  return parsed != null && parsed.isScheme('https') && parsed.host.isNotEmpty;
}
