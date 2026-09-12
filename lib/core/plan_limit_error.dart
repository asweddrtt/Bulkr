import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'plan_limits.dart';

/// The SQLSTATE `supabase/premium_limits.sql` raises when a free account has
/// hit one of its ceilings.
///
/// Its own code rather than the 42501 a `with check` would produce, because
/// the two mean different things and the app answers them differently. 42501
/// is "you do not have permission", which in this app is nearly always a
/// policy file nobody has run — a bug, and nothing the user can act on. This
/// is "you have filled up the free tier", which is a sentence with an obvious
/// next step.
///
/// `BLKR1` is the blocked-term refusal in `moderation_terms.sql`; this is the
/// second of the same family.
const String planLimitSqlState = 'BLKR2';

/// Which limit was hit.
///
/// The names come from the trigger's `hint`, which is a machine-readable key
/// and is never shown to anybody — unlike `BLKR1`, where the hint *is* the
/// message. Kept as an enum so a screen can answer "which upgrade prompt" with
/// a switch the compiler checks.
enum PlanLimit {
  savedMeals('saved_meals'),
  activeChallenges('active_challenges'),

  /// Not enforced in the database — see the header of `premium_limits.sql` for
  /// why restricting reads of `daily_logs` would cap every free account's
  /// streak at seven days. The app raises this one itself.
  historyDays('history_days');

  const PlanLimit(this.key);

  final String key;

  static PlanLimit? fromKey(String? key) {
    for (final PlanLimit limit in PlanLimit.values) {
      if (limit.key == key) return limit;
    }
    return null;
  }
}

/// The limit this failure means, or null when it is some other failure.
PlanLimit? planLimitReached(Object error) {
  if (error is! PostgrestException) return null;
  if (error.code != planLimitSqlState) return null;

  // Unrecognised hint, or none: still a plan limit, and the generic sentence
  // is better than pretending it was a server error. A limit added to the SQL
  // and not to the enum should degrade, not misreport.
  return PlanLimit.fromKey(error.hint?.trim()) ?? PlanLimit.savedMeals;
}

/// What to tell somebody who has hit [limit].
///
/// Each one names the number, because "you have reached the limit" without it
/// is a sentence that answers nothing — and the number comes from
/// [PlanLimits.free] rather than from the database's message, so the app and
/// the screen that offers the upgrade cannot disagree about what free gets.
///
/// The keys are `limit_` plus the enum's own [PlanLimit.key], which
/// `plan_limit_error_test.dart` relies on to check that every limit has a
/// sentence — including one added later by somebody who forgot this file.
String planLimitMessage(PlanLimit limit) {
  return switch (limit) {
    PlanLimit.savedMeals => 'limit_saved_meals'.tr(
      namedArgs: <String, String>{'count': '${PlanLimits.free.savedMeals}'},
    ),
    PlanLimit.activeChallenges => 'limit_active_challenges'.tr(),
    PlanLimit.historyDays => 'limit_history_days'.tr(
      namedArgs: <String, String>{'days': '${PlanLimits.free.historyDays}'},
    ),
  };
}
