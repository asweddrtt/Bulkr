import 'package:bulkr/core/moderation_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A blocked term is an answer, not a fault report.
///
/// The composer already formatted `PostgrestException`s as "message (code)",
/// which for this one produced "Bulkr: this cannot be posted as written.
/// (BLKR1)" — technically the truth and useless to the person holding the
/// phone.
void main() {
  PostgrestException blocked({String? hint}) => PostgrestException(
        message: 'Bulkr: this cannot be posted as written.',
        code: blockedTermSqlState,
        hint: hint,
      );

  test('a blocked term reads as a sentence', () {
    expect(
      blockedTermRefusal(blocked(hint: 'Reword it and try again.')),
      'this cannot be posted as written. Reword it and try again.',
    );
  });

  test('the log prefix is dropped and the code never shown', () {
    final String? refusal = blockedTermRefusal(blocked());
    expect(refusal, 'this cannot be posted as written.');
    expect(refusal, isNot(contains('Bulkr:')),
        reason: 'the prefix exists for the Postgres log, where nothing else '
            'says which app raised it');
    expect(refusal, isNot(contains(blockedTermSqlState)));
  });

  test('an empty hint does not leave a trailing space', () {
    expect(blockedTermRefusal(blocked(hint: '   ')),
        'this cannot be posted as written.');
  });

  test('other failures are left to the generic formatting', () {
    // 42501 is a row-level security refusal and 23505 a unique violation.
    // Both need the code shown, because both mean a policy or a schema is
    // wrong rather than the text being wrong.
    expect(
      blockedTermRefusal(
        PostgrestException(message: 'permission denied', code: '42501'),
      ),
      isNull,
    );
    expect(blockedTermRefusal(Exception('network')), isNull);
    expect(blockedTermRefusal('a string'), isNull);
  });

  test('the match is on the code, not the wording', () {
    // The refusal text can be reworded freely. If this ever matched on the
    // message instead, the first rewording would silently turn the check into
    // a no-op and every blocked post would show a raw Postgres error again.
    expect(
      blockedTermRefusal(PostgrestException(
        message: 'something else entirely',
        code: blockedTermSqlState,
      )),
      'something else entirely',
    );
  });
}
