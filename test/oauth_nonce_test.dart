import 'dart:convert';

import 'package:bulkr/core/oauth_nonce.dart';
import 'package:flutter_test/flutter_test.dart';

String _token(Map<String, dynamic> payload) {
  String segment(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(<String, dynamic>{'alg': 'RS256'})}'
      '.${segment(payload)}'
      '.signature';
}

void main() {
  group('generate', () {
    test('is url-safe and unpadded', () {
      for (int i = 0; i < 50; i++) {
        final String nonce = OAuthNonce.generate();
        expect(nonce, isNot(contains('=')));
        expect(nonce, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      }
    });

    test('does not repeat', () {
      final Set<String> seen = <String>{
        for (int i = 0; i < 200; i++) OAuthNonce.generate(),
      };
      expect(seen, hasLength(200), reason: 'a reused nonce is not a nonce');
    });
  });

  group('hash', () {
    test('is the hex SHA-256 the providers expect', () {
      // Checked against a known vector rather than against itself.
      expect(
        OAuthNonce.hash('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('claimOf', () {
    test('reads the nonce out of a token', () {
      expect(
        OAuthNonce.claimOf(_token(<String, dynamic>{'nonce': 'abc123'})),
        'abc123',
      );
    });

    test('is null when the token carries no nonce', () {
      expect(
        OAuthNonce.claimOf(_token(<String, dynamic>{'sub': 'someone'})),
        isNull,
      );
    });

    test('survives a token it cannot parse', () {
      for (final String rubbish in <String>['', 'not.a.token', 'a.b', 'aaa']) {
        expect(OAuthNonce.claimOf(rubbish), isNull);
      }
    });
  });

  group('forSupabase', () {
    const String raw = 'the-original';
    final String hashed = OAuthNonce.hash(raw);

    test('sends the original when the provider stamped in our hash', () {
      expect(
        OAuthNonce.forSupabase(claim: hashed, raw: raw, hashed: hashed),
        raw,
        reason: 'Supabase hashes what it is given and compares to the claim',
      );
    });

    test('sends nothing when the token has no nonce', () {
      // The other half of "both exist or not" — passing a nonce here is what
      // would fail, not what would help.
      expect(
        OAuthNonce.forSupabase(claim: null, raw: raw, hashed: hashed),
        isNull,
      );
    });

    test('echoes a nonce the SDK chose for itself', () {
      // The iOS Google case: our hash was ignored and something else was
      // stamped in. Passing null here is the bug that was shipped.
      expect(
        OAuthNonce.forSupabase(claim: 'sdk-chose-this', raw: raw, hashed: hashed),
        'sdk-chose-this',
      );
    });
  });
}
