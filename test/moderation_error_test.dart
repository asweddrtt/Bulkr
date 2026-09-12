import 'package:bulkr/core/moderation_error.dart';
import 'package:bulkr/core/image_safety.dart';
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

  group('the explicit-image refusal', _refusalTests);
}

/// The refusal a user actually reads.
///
/// `ImageSafety.showScoreInRefusal` was true while the threshold was being
/// calibrated, which meant a false positive on somebody's progress photo said:
///
///     We can't post that image (scored 0.812, threshold 0.75)
///
/// A number the person holding the phone cannot act on, attached to a refusal
/// they will read as the app malfunctioning. The scores now go to analytics
/// instead, where the distribution is the thing that is actually wanted.
void _refusalTests() {
  test('a refused image is told why, not told a score', () {
    final String? refusal =
        explicitImageRefusal(const ExplicitImageException(0.812));

    expect(refusal, isNotNull);
    expect(
      refusal,
      isNot(contains('0.81')),
      reason: 'the model score must not be shown to the user',
    );
    expect(
      refusal,
      isNot(contains('threshold')),
      reason: 'nor the threshold it was measured against',
    );
  });

  test('the flag that put the score there is off', () {
    // Asserted directly as well as through the text above, so that turning it
    // back on for a calibration run fails here rather than silently shipping.
    expect(ImageSafety.showScoreInRefusal, isFalse);
  });

  test('other failures are still not image refusals', () {
    expect(explicitImageRefusal(Exception('something else')), isNull);
  });
}
