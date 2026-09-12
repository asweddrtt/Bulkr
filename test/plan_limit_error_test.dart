import 'dart:convert';
import 'dart:io';

import 'package:bulkr/core/error_text.dart';
import 'package:bulkr/core/plan_limit_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Telling "you have filled up the free tier" apart from "you do not have
/// permission".
///
/// Both arrive from Postgres saying no, and before this they arrived as the
/// same SQLSTATE. They need opposite responses: a permission failure is a
/// policy file nobody has run, which the person holding the phone can do
/// nothing about, and a plan limit is a sentence with an obvious next step.
/// Telling somebody they lack permission to save their twenty-first meal would
/// be both wrong and insulting.
void main() {
  PostgrestException limit(String? hint) => PostgrestException(
        message: 'Bulkr: free accounts keep 20 meals.',
        code: planLimitSqlState,
        hint: hint,
      );

  group('recognising a limit', () {
    test('reads which one from the hint', () {
      expect(planLimitReached(limit('saved_meals')), PlanLimit.savedMeals);
      expect(
        planLimitReached(limit('active_challenges')),
        PlanLimit.activeChallenges,
      );
    });

    test('tolerates the hint being padded', () {
      expect(planLimitReached(limit('  saved_meals ')), PlanLimit.savedMeals);
    });

    test('a limit the app has never heard of is still a limit', () {
      // A ceiling added to premium_limits.sql and not to the enum should
      // degrade to the general shape of the right answer, not report itself as
      // a server error.
      expect(planLimitReached(limit('something_new')), isNotNull);
      expect(planLimitReached(limit(null)), isNotNull);
    });

    test('an ordinary policy failure is not a limit', () {
      // 42501 is nearly always a policy file that has not been run. Reading it
      // as a plan limit would tell somebody to buy their way out of our bug.
      expect(
        planLimitReached(PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        )),
        isNull,
      );
    });

    test('a blocked term is not a limit', () {
      expect(
        planLimitReached(PostgrestException(
          message: 'Bulkr: this cannot be posted as written.',
          code: 'BLKR1',
        )),
        isNull,
      );
    });

    test('anything that is not a Postgres error is not a limit', () {
      expect(planLimitReached(Exception('offline')), isNull);
      expect(planLimitReached('nope'), isNull);
    });
  });

  group('what the user is told', () {
    // `.tr()` needs easy_localization initialised, which a unit test does not
    // have — so the translations are read straight off disk. That is also the
    // more useful assertion: what breaks here is a key that does not exist,
    // and easy_localization answers a missing key with the key itself, so the
    // failure ships as "limit_saved_meals" on somebody's screen.
    late final Map<String, dynamic> translations = jsonDecode(
      File('assets/translations/en-US.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('every limit has a sentence behind it', () {
      for (final PlanLimit value in PlanLimit.values) {
        expect(
          translations,
          contains('limit_${value.key}'),
          reason: 'PlanLimit.${value.name} has no translation key',
        );
      }
    });

    test('the sentences name the number', () {
      // "You have reached the limit" without it answers nothing, and the
      // number has to come from PlanLimits rather than be typed into the
      // sentence, or the copy and the cap drift apart.
      expect(translations['limit_saved_meals'], contains('{count}'));
      expect(translations['limit_history_days'], contains('{days}'));
    });

    test('and say what removes it', () {
      for (final String key in const <String>[
        'limit_saved_meals',
        'limit_active_challenges',
        'limit_history_days',
      ]) {
        expect(
          '${translations[key]}'.toLowerCase(),
          contains('premium'),
          reason: '$key states a limit without stating the way out of it',
        );
      }
    });
  });

  group('through the shared classifier', () {
    test('is its own kind, not permission', () {
      final DescribedFailure failure = describeFailure(limit('saved_meals'));

      expect(failure.kind, FailureKind.planLimit);
      expect(failure.kind, isNot(FailureKind.permission));
    });

    test('carries its own sentence rather than the generic one', () {
      // `refusal` is what overrides the "something went wrong" text. Without
      // it, a full library would read as a server error.
      final DescribedFailure failure = describeFailure(limit('saved_meals'));

      expect(failure.refusal, isNotNull);
      expect(failure.code, planLimitSqlState);
    });

    test('is not offered as retryable', () {
      // Retrying does not empty the library, and a "try again" button that
      // cannot work is worse than none.
      expect(describeFailure(limit('saved_meals')).isRetryable, isFalse);
    });
  });
}
