import 'dart:async';
import 'dart:io';

import 'package:bulkr/core/error_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a user is told when something fails.
///
/// Fourteen cubits each carried a private `_describe`, in four slightly
/// different variants, and every one of them ended `return error.toString()`.
/// So the user-visible text for being on a train was:
///
///     ClientException with SocketException: Failed host lookup:
///     'hqdfaeiyflbbzkduskaz.supabase.co' … uri=https://…/rest/v1/posts?select=…
///
/// which names the backend, reads like a crash, and tells somebody with no
/// signal nothing they can act on. It was rendered as the body of the error
/// state on fourteen screens.
///
/// These check the classification rather than the wording — the wording is a
/// translation key and belongs in `en-US.json` — plus the one rule that
/// matters most: raw exception text must not reach a release build.
void main() {
  group('being offline', () {
    test('a failed DNS lookup is offline, not a server error', () {
      final DescribedFailure failure = describeFailure(
        const SocketException("Failed host lookup: 'example.supabase.co'"),
      );

      expect(failure.kind, FailureKind.offline);
      expect(failure.messageKey, 'error_offline');
      expect(failure.isRetryable, isTrue);
    });

    test("http's wrapper counts too, which is the common one", () {
      // What Supabase's own client actually throws. Missing this was why the
      // offline case read as an unknown failure.
      final DescribedFailure failure = describeFailure(
        http.ClientException('Connection closed before full header was received'),
      );

      expect(failure.kind, FailureKind.offline);
    });

    test('a dropped TLS handshake is offline', () {
      expect(
        describeFailure(const HandshakeException('handshake failed')).kind,
        FailureKind.offline,
      );
    });

    test('a connection that died mid-request is offline', () {
      // PostgREST has already wrapped it by the time it reaches us, so it
      // arrives as a SQLSTATE rather than a SocketException.
      expect(
        describeFailure(const PostgrestException(message: 'x', code: '08006'))
            .kind,
        FailureKind.offline,
      );
    });
  });

  test('a timeout is its own thing, and is worth retrying', () {
    final DescribedFailure failure =
        describeFailure(TimeoutException('too slow'));

    expect(failure.kind, FailureKind.timeout);
    expect(failure.isRetryable, isTrue);
  });

  group('row-level security', () {
    test('42501 is a permission failure', () {
      // In practice this is nearly always a policy file that has not been run
      // rather than a user doing something they should not — which is why the
      // code is kept for the log even though the user never sees it.
      final DescribedFailure failure = describeFailure(
        const PostgrestException(message: 'permission denied', code: '42501'),
      );

      expect(failure.kind, FailureKind.permission);
      expect(failure.code, '42501');
      // Not worth retrying: the answer will be the same next time.
      expect(failure.isRetryable, isFalse);
    });

    test('a missing row is not found, not a server error', () {
      expect(
        describeFailure(
                const PostgrestException(message: 'no rows', code: 'PGRST116'))
            .kind,
        FailureKind.notFound,
      );
    });

    test('anything else from Postgres is a server error', () {
      expect(
        describeFailure(
                const PostgrestException(message: 'boom', code: '23505'))
            .kind,
        FailureKind.server,
      );
    });
  });

  group('a refusal is an answer, not a fault', () {
    test('a blocked term keeps the sentence the database wrote', () {
      // The trigger raises something written to be read by whoever is holding
      // the phone. Replacing it with "something went wrong" would throw away
      // the only useful part.
      final DescribedFailure failure = describeFailure(
        const PostgrestException(
          message: 'Bulkr: that word is not allowed here.',
          code: 'BLKR1',
        ),
      );

      expect(failure.kind, FailureKind.refused);
      expect(failure.refusal, isNotNull);
      expect(failure.refusal, contains('not allowed'));
      // The `Bulkr:` prefix is for the Postgres log and is noise here.
      expect(failure.refusal, isNot(startsWith('Bulkr:')));
    });

    test('the code is never appended to the refusal', () {
      // "(BLKR1)" on the end of a sentence written for a human is not an
      // improvement.
      final DescribedFailure failure = describeFailure(
        const PostgrestException(message: 'Bulkr: no.', code: 'BLKR1'),
      );

      expect(failure.refusal, isNot(contains('BLKR1')));
    });

    test('a refusal is not retryable — the answer will not change', () {
      expect(
        describeFailure(
          const PostgrestException(message: 'Bulkr: no.', code: 'BLKR1'),
        ).isRetryable,
        isFalse,
      );
    });
  });

  test('an unrecognised failure is unknown rather than mis-sorted', () {
    final DescribedFailure failure = describeFailure(Exception('who knows'));

    expect(failure.kind, FailureKind.unknown);
    expect(failure.messageKey, 'error_generic');
  });

  group('what reaches the screen', () {
    test('the raw exception is kept for the log, not thrown away', () {
      // Crashlytics and the debug build still want it. The point was never to
      // lose the detail, only to stop showing it to people who cannot use it.
      final DescribedFailure failure = describeFailure(
        const SocketException("Failed host lookup: 'example.supabase.co'"),
      );

      expect(failure.technical, contains('example.supabase.co'));
    });

    test('every kind maps to a key that exists in en-US.json', () {
      // A missing key renders as the key itself — `error_offline` on screen,
      // in every language. `translation_keys_test.dart` guards the literals;
      // these are built from an enum and would slip past it.
      const Set<String> keys = <String>{
        'error_offline',
        'error_timeout',
        'error_permission',
        'error_not_found',
        'error_server',
        'error_generic',
      };

      for (final FailureKind kind in FailureKind.values) {
        final DescribedFailure failure =
            DescribedFailure(kind: kind, technical: 'x');
        expect(keys, contains(failure.messageKey),
            reason: '$kind maps to ${failure.messageKey}, which is not a key '
                'this test knows about — add it to en-US.json and here');
      }
    });
  });
}
