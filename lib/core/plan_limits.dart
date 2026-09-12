import 'package:equatable/equatable.dart';

import '../models/entitlement.dart';

/// What a free account may do, and what paying removes.
///
/// Every number Bulkr charges for is in this file. That is the point of it:
/// "how many saved meals does free get" is a pricing question, it will be
/// answered differently in three months, and the answer should not have to be
/// hunted through the screens that happen to enforce it.
///
/// ## What is gated, and what is deliberately not
///
/// **Daily logging is never gated.** Not by count, not by day, not by hitting
/// a wall at 6pm. It is the thing the app is for, and an app that stops
/// someone recording their dinner is an app they stop opening — no upgrade
/// screen recovers that. The free tier has to be genuinely usable forever or
/// it is a trial with extra steps.
///
/// What is gated is *accumulation* and *convenience*: how large a library you
/// can keep, how far back you can look, how many challenges you can run at
/// once. Each of those is something you only want once the app has already
/// become part of your week, which is exactly when paying makes sense — and
/// none of them stops you logging today's food.
///
/// Ads are in the same category. They are the free tier's price, and removing
/// them is most of what premium sells.
///
/// ## `null` means unlimited
///
/// Rather than a sentinel like `-1` or `999999`, which have both been read as
/// real numbers by code that forgot. A nullable int makes the compiler ask.
///
/// ## These numbers exist twice
///
/// Here, and in `supabase/premium.sql`, because the client decides what to
/// *show* and the database decides what is *allowed* — and a client-side limit
/// is a suggestion, since the client is on someone else's phone. Two copies of
/// a number is a bug waiting to happen, so `plan_limits_test.dart` reads the
/// SQL and fails if the two ever disagree.
class PlanLimits extends Equatable {
  const PlanLimits({
    required this.savedMeals,
    required this.historyDays,
    required this.activeChallenges,
    required this.showsAds,
  });

  /// What an account gets before paying.
  ///
  /// Five saved meals is a deliberate tightening from twenty, and it is the
  /// most aggressive number here: somebody who repeats meals — which is most
  /// people, and nearly everyone bulking — reaches it in their first week
  /// rather than their first month. That is the point, and it is also the
  /// risk. Watch `plan_limit_reached` against `upgrade_completed`: if people
  /// hit this and leave instead of paying, the cap is converting nobody and
  /// costing the users who would have paid in month three.
  ///
  /// Seven days of history is the weekly recap and nothing further back. One
  /// challenge at a time is enough to be in the one your friends are in.
  static const PlanLimits free = PlanLimits(
    savedMeals: 5,
    historyDays: 7,
    activeChallenges: 1,
    showsAds: true,
  );

  /// What paying buys: the same app with the ceilings taken out.
  ///
  /// Not extra features. A premium tier made of features the free tier cannot
  /// see needs those features built and maintained separately forever; a
  /// premium tier made of removed limits is the app you already shipped,
  /// unobstructed, and it never rots.
  static const PlanLimits premium = PlanLimits(
    savedMeals: null,
    historyDays: null,
    activeChallenges: null,
    showsAds: false,
  );

  /// The limits that apply to [entitlement] right now.
  ///
  /// Reads [Entitlement.isPremium] rather than the tier, so an expired
  /// subscription whose row has not been refreshed yet gets free's limits
  /// instead of premium's.
  static PlanLimits of(Entitlement entitlement) =>
      entitlement.isPremium ? premium : free;

  /// How many meals may be in the library — created plus saved, since both
  /// appear on the same screen and the user does not distinguish them.
  final int? savedMeals;

  /// How far back the tracker may be scrolled, in days, counting today as one.
  final int? historyDays;

  /// How many challenges may be joined at once.
  final int? activeChallenges;

  /// Whether ads are shown. The one limit that is a boolean, and the one most
  /// people are actually buying their way out of.
  final bool showsAds;

  bool get isUnlimited =>
      savedMeals == null && historyDays == null && activeChallenges == null;

  /// Whether one more may be added when [current] are already there.
  ///
  /// Takes the count rather than the collection so the caller can pass a
  /// `count(*)` from the server without fetching rows to length them.
  static bool allowsAnother(int? limit, int current) =>
      limit == null || current < limit;

  /// How many are left, or null when there is no ceiling. Never negative: a
  /// library that is over its limit because the user downgraded shows zero
  /// remaining, not minus six.
  static int? remaining(int? limit, int current) =>
      limit == null ? null : (limit - current).clamp(0, limit);

  bool canSaveAnotherMeal(int current) => allowsAnother(savedMeals, current);

  bool canJoinAnotherChallenge(int current) =>
      allowsAnother(activeChallenges, current);

  /// Whether [day] is inside the window this plan can look back over.
  ///
  /// Compared by calendar day, not by elapsed hours: "seven days of history"
  /// has to mean the same thing at 9am and at 11pm, or the tracker loses a day
  /// while somebody is looking at it.
  ///
  /// Future days are always allowed. Logging tomorrow's prepped lunch is not a
  /// premium feature, and the window is about the past.
  bool includesDay(DateTime day, {DateTime? now}) {
    final int? window = historyDays;
    if (window == null) return true;

    final DateTime today = _dateOnly(now ?? DateTime.now());
    final DateTime target = _dateOnly(day);

    final int daysBack = today.difference(target).inDays;
    return daysBack < window;
  }

  /// The oldest day this plan can reach, or null when all of it can.
  DateTime? earliestDay({DateTime? now}) {
    final int? window = historyDays;
    if (window == null) return null;

    return _dateOnly(
      now ?? DateTime.now(),
    ).subtract(Duration(days: window - 1));
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  List<Object?> get props => <Object?>[
    savedMeals,
    historyDays,
    activeChallenges,
    showsAds,
  ];
}
