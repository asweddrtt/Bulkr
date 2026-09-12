import 'package:equatable/equatable.dart';

/// Why an interstitial was not shown. Every path through [AdPolicy] ends in
/// one of these, which is what makes the decision testable and what makes the
/// analytics answer "why is nobody seeing ads" without guessing.
enum AdBlock {
  /// Nothing stopped it.
  none,

  /// A paying account. The first check, and the only one that is not about
  /// timing.
  premium,

  /// Inside the 24 hours somebody earned by watching a rewarded ad. Honouring
  /// this is the entire product: an app that takes the reward and shows the ad
  /// anyway has taught the user never to trust an offer again.
  rewardEarned,

  /// Too new. Nobody's first day should contain a full-screen ad.
  newUser,

  /// Another one was shown a moment ago.
  cooldown,

  /// Already had today's share.
  dailyCap,

  /// They have not finished enough since the last one. Stops the very next
  /// save after an ad from producing another.
  tooSoonAfterAction,

  /// The trigger itself does not apply — a return that was not long enough to
  /// count as coming back.
  notTriggered,
}

/// What made the app consider showing an interstitial.
enum AdTrigger {
  /// The user finished something: a meal saved, a day logged, a post
  /// published. The seam between one thing and the next, which is the only
  /// place a full-screen ad is not an interruption.
  completedAction,

  /// The app was reopened after a long time away. Coming back is its own seam
  /// — nothing was interrupted, because nothing was in progress.
  returned,
}

/// Everything the decision depends on, as one value.
///
/// Persisted between launches, because all of these limits are worthless if
/// they reset when the app is killed — which is exactly when somebody who has
/// seen four ads comes back for a fifth.
class AdState extends Equatable {
  const AdState({
    this.firstSeenAt,
    this.lastInterstitialAt,
    this.shownToday = 0,
    this.countedDay,
    this.adFreeUntil,
    this.actionsSinceLast = 0,
  });

  /// The first time this install ran. The clock the new-user grace is measured
  /// against.
  final DateTime? firstSeenAt;

  final DateTime? lastInterstitialAt;

  /// How many have been shown on [countedDay]. Kept with the day it counts,
  /// rather than reset by a timer, so the count is correct after a restart and
  /// across a midnight the app slept through.
  final int shownToday;
  final DateTime? countedDay;

  /// Earned by watching a rewarded ad. See [AdBlock.rewardEarned].
  final DateTime? adFreeUntil;

  /// Completed actions since the last interstitial.
  final int actionsSinceLast;

  static const AdState fresh = AdState();

  bool get isAdFree {
    final DateTime? until = adFreeUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// How much of the earned ad-free window is left, or null when there is
  /// none. For the screen that says so.
  Duration? adFreeRemaining({DateTime? now}) {
    final DateTime? until = adFreeUntil;
    if (until == null) return null;

    final Duration left = until.difference(now ?? DateTime.now());
    return left.isNegative ? null : left;
  }

  AdState copyWith({
    DateTime? firstSeenAt,
    DateTime? lastInterstitialAt,
    int? shownToday,
    DateTime? countedDay,
    DateTime? adFreeUntil,
    int? actionsSinceLast,
  }) {
    return AdState(
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastInterstitialAt: lastInterstitialAt ?? this.lastInterstitialAt,
      shownToday: shownToday ?? this.shownToday,
      countedDay: countedDay ?? this.countedDay,
      adFreeUntil: adFreeUntil ?? this.adFreeUntil,
      actionsSinceLast: actionsSinceLast ?? this.actionsSinceLast,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (firstSeenAt != null) 'first_seen': firstSeenAt!.toIso8601String(),
    if (lastInterstitialAt != null)
      'last_shown': lastInterstitialAt!.toIso8601String(),
    'shown_today': shownToday,
    if (countedDay != null) 'counted_day': countedDay!.toIso8601String(),
    if (adFreeUntil != null) 'ad_free_until': adFreeUntil!.toIso8601String(),
    'actions_since': actionsSinceLast,
  };

  factory AdState.fromJson(Map<String, dynamic> json) => AdState(
    firstSeenAt: DateTime.tryParse('${json['first_seen']}'),
    lastInterstitialAt: DateTime.tryParse('${json['last_shown']}'),
    shownToday: json['shown_today'] is int ? json['shown_today'] as int : 0,
    countedDay: DateTime.tryParse('${json['counted_day']}'),
    adFreeUntil: DateTime.tryParse('${json['ad_free_until']}'),
    actionsSinceLast: json['actions_since'] is int
        ? json['actions_since'] as int
        : 0,
  );

  @override
  List<Object?> get props => <Object?>[
    firstSeenAt,
    lastInterstitialAt,
    shownToday,
    countedDay,
    adFreeUntil,
    actionsSinceLast,
  ];
}

/// When a full-screen ad may be shown.
///
/// Pure, so the rules can be argued with and tested without an SDK, a device,
/// or a four-minute wait. Nothing here loads or shows anything — it only
/// answers yes or no, and says why when the answer is no.
///
/// ## The rules, and what each one is protecting
///
/// An interstitial is the format most able to make somebody delete a
/// daily-use app, and the ones that do it are never the first ad — they are
/// the fourth in ten minutes, or the one that appeared before the user had
/// worked out what the app was for. So the caps are about *rhythm*, not about
/// a total:
///
/// - **[newUserGrace]** — nobody's first day contains a full-screen ad. The
///   value has to land before the ask does, and on day one it has not landed.
/// - **[cooldown]** — no two ads close together, whatever happened in between.
/// - **[maxPerDay]** — a ceiling for the heavy user, who is the person most
///   likely to be shown the most ads and is also the person worth keeping.
/// - **[actionsBetween]** — the save immediately after an ad must not produce
///   another. Without this, somebody saving three meals in a row gets three
///   ads, which is the single most uninstall-producing pattern there is.
/// - **[awayThreshold]** — a "return" has to be a real absence. Switching to
///   Messages and back is not coming back.
///
/// And two absolutes: never for a premium account, and never inside an
/// ad-free window somebody earned. Both are checked first, because no amount
/// of good timing makes either acceptable.
class AdPolicy {
  const AdPolicy._();

  /// No interstitial in the first day of an install.
  static const Duration newUserGrace = Duration(hours: 24);

  /// Minimum gap between two interstitials.
  static const Duration cooldown = Duration(minutes: 4);

  /// The most anybody sees in a calendar day.
  static const int maxPerDay = 4;

  /// Completed actions required between one interstitial and the next.
  static const int actionsBetween = 3;

  /// How long away counts as having left. Four hours: long enough that a
  /// commute, a night's sleep or a working day qualifies and a glance at a
  /// notification does not.
  static const Duration awayThreshold = Duration(hours: 4);

  /// What a rewarded ad buys.
  static const Duration rewardWindow = Duration(hours: 24);

  /// Whether an interstitial may be shown now.
  ///
  /// [isPremium] is passed rather than read, so this file never learns what a
  /// subscription is.
  static AdBlock evaluate({
    required AdTrigger trigger,
    required AdState state,
    required bool isPremium,
    Duration? awayFor,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();

    if (isPremium) return AdBlock.premium;

    final DateTime? adFreeUntil = state.adFreeUntil;
    if (adFreeUntil != null && adFreeUntil.isAfter(at)) {
      return AdBlock.rewardEarned;
    }

    final DateTime? firstSeen = state.firstSeenAt;
    if (firstSeen == null || at.difference(firstSeen) < newUserGrace) {
      return AdBlock.newUser;
    }

    if (trigger == AdTrigger.returned &&
        (awayFor == null || awayFor < awayThreshold)) {
      return AdBlock.notTriggered;
    }

    final DateTime? last = state.lastInterstitialAt;
    if (last != null && at.difference(last) < cooldown) {
      return AdBlock.cooldown;
    }

    if (shownOn(state, at) >= maxPerDay) return AdBlock.dailyCap;

    // Only the completed-action trigger counts actions. A return after four
    // hours is its own reason to be at a seam, and requiring three saves as
    // well would mean the trigger almost never fired.
    if (trigger == AdTrigger.completedAction &&
        state.actionsSinceLast < actionsBetween) {
      return AdBlock.tooSoonAfterAction;
    }

    return AdBlock.none;
  }

  static bool allows({
    required AdTrigger trigger,
    required AdState state,
    required bool isPremium,
    Duration? awayFor,
    DateTime? now,
  }) =>
      evaluate(
        trigger: trigger,
        state: state,
        isPremium: isPremium,
        awayFor: awayFor,
        now: now,
      ) ==
      AdBlock.none;

  /// How many have been shown on the calendar day containing [at].
  ///
  /// Zero when the stored count belongs to a different day, which is what
  /// makes the cap roll over without a timer — the app is usually closed at
  /// midnight, and a timer that has to be running is a cap that resets
  /// whenever it is convenient for it not to.
  static int shownOn(AdState state, DateTime at) {
    final DateTime? counted = state.countedDay;
    if (counted == null) return 0;

    return _sameDay(counted, at) ? state.shownToday : 0;
  }

  /// The state after an interstitial has actually been shown.
  ///
  /// Applied on *shown*, never on *requested*: an ad that failed to load must
  /// not spend the day's allowance, or a bad network becomes a day with no
  /// revenue and no ads either.
  static AdState recordShown(AdState state, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();

    return AdState(
      firstSeenAt: state.firstSeenAt,
      lastInterstitialAt: at,
      shownToday: shownOn(state, at) + 1,
      countedDay: at,
      adFreeUntil: state.adFreeUntil,
      actionsSinceLast: 0,
    );
  }

  /// The state after the user finished something.
  static AdState recordAction(AdState state) =>
      state.copyWith(actionsSinceLast: state.actionsSinceLast + 1);

  /// The state after a rewarded ad paid out its ad-free window.
  ///
  /// Extends from *now* rather than from the existing expiry, so watching a
  /// second ad an hour in buys 24 hours and not 47. Somebody who wants two
  /// days of it can come back tomorrow, which is also the behaviour that keeps
  /// the offer worth anything.
  static AdState grantAdFree(AdState state, {DateTime? now}) =>
      state.copyWith(adFreeUntil: (now ?? DateTime.now()).add(rewardWindow));

  /// The state for an install that has just run for the first time.
  static AdState seed(AdState state, {DateTime? now}) =>
      state.firstSeenAt != null
      ? state
      : state.copyWith(firstSeenAt: now ?? DateTime.now());

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
