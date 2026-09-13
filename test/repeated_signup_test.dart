import 'dart:convert';
import 'dart:io';

import 'package:bulkr/data/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Reading Supabase's answer to "sign this address up" when the address is
/// already signed up.
///
/// The server will not say so in words — a sign-up endpoint that answered
/// "already registered" is a way to find out who has an account, one guess at
/// a time — so it returns a 200 that looks like success and sends no email.
/// The only difference is an **empty identities list**, and the whole cost of
/// misreading it is a screen telling somebody to check an inbox that will
/// never receive anything.
///
/// Worth pinning because it is a quiet convention rather than a documented
/// field: if a future gotrue starts sending a placeholder identity instead,
/// this fails here rather than in somebody's inbox.
void main() {
  UserIdentity identity(String provider) => UserIdentity.fromMap(
        <String, dynamic>{
          'id': 'id-$provider',
          'user_id': 'user-1',
          'identity_id': 'identity-$provider',
          'provider': provider,
          'identity_data': <String, dynamic>{'email': 'a@b.com'},
          'created_at': '2026-01-01T00:00:00Z',
          'last_sign_in_at': '2026-01-01T00:00:00Z',
        },
      );

  group('the empty-identities tell', () {
    test('no identities means the address is taken', () {
      expect(AuthRepository.isAlreadyRegistered(<UserIdentity>[]), isTrue);
    });

    test('a new account comes back with its email identity', () {
      expect(
        AuthRepository.isAlreadyRegistered(<UserIdentity>[identity('email')]),
        isFalse,
      );
    });

    test('the usual cause is an account made with Apple or Google', () {
      // Not that this response says so — an address registered through a
      // provider is obfuscated exactly like any other, coming back empty. The
      // case is here to record why the sentence names them.
      expect(AuthRepository.isAlreadyRegistered(<UserIdentity>[]), isTrue);
      expect(
        AuthRepository.isAlreadyRegistered(<UserIdentity>[identity('google')]),
        isFalse,
      );
    });

    test('a missing field is not evidence', () {
      // An older server that does not send identities at all. Silence is not
      // the same as an empty list, and guessing "taken" from it would refuse
      // sign-ups that would have worked.
      expect(AuthRepository.isAlreadyRegistered(null), isFalse);
    });
  });

  test('the sentence it leads to exists', () {
    final Map<String, dynamic> translations = jsonDecode(
      File('assets/translations/en-US.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final String sentence = translations['auth_failed_exists'] as String;

    // The one thing this copy has to do that generic "already exists" wording
    // does not: point at the two providers the user has probably forgotten
    // using. Without that the message is true and still a dead end.
    expect(sentence, contains('Apple'));
    expect(sentence, contains('Google'));
  });
}
