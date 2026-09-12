import 'package:flutter/foundation.dart';

/// Everything Bulkr records about what people do, in one file.
///
/// ## The rule about parameters
///
/// **No parameter may carry anything a user wrote or is.** Not a post, not a
/// message, not a search query, not a handle, display name, email or photo
/// URL. What goes in instead is the *shape* of the thing: how long it was,
/// which of five labels it had, how many results came back, whether it
/// succeeded.
///
/// That is not caution for its own sake. Analytics leaves the device, lands in
/// a console many people can open, and is retained on someone else's schedule
/// — so a search query in a parameter is a private thing published, and
/// "boiled eggs" being harmless does not make the *next* query harmless. The
/// constructors below are the enforcement: they take counts and enums, so
/// there is no argument to pass a message body to.
///
/// The one identifier that does travel is the Supabase user id, set once via
/// `Telemetry.identify`. It is a random UUID, meaningless outside our own
/// database, and it is what makes a report actionable without making it
/// personal.
///
/// ## Why these events and not others
///
/// Each one answers a question that would otherwise be answered by guessing:
///
///   - Where does onboarding lose people? — the five `onboarding*` events
///   - Is the three-tier food search worth its complexity? — [foodSearched]
///     records which tier answered, so "tier 1 answers 80% of queries" stops
///     being a hope
///   - Is the nudity threshold right? — [imageRefused] carries the score that
///     caused a refusal, which is the number `ImageSafety` was printing to a
///     console nobody could read
///   - Does anybody use Discover? — [feedViewed]
///   - Do the share buttons do anything? — [postShared] against [postOpened]
///     with `source: deep_link`
@immutable
class AnalyticsEvent {
  const AnalyticsEvent(this.name, [this.params = const <String, Object?>{}]);

  /// Firebase's rules, which it enforces by silently dropping the event: at
  /// most 40 characters, letters, digits and underscores, starting with a
  /// letter, and not beginning with `firebase_`, `google_` or `ga_`.
  final String name;

  /// Null values are dropped rather than sent, so a call site can pass an
  /// optional without a conditional around it.
  final Map<String, Object?> params;

  /// [params] in the two types Firebase accepts, with the caps it applies.
  ///
  /// Booleans become 1 and 0 rather than `'true'`/`'false'`: the console and
  /// BigQuery can average a number, which turns `succeeded` into a success
  /// rate for free.
  Map<String, Object> get firebaseParameters {
    final Map<String, Object> out = <String, Object>{};

    for (final MapEntry<String, Object?> entry in params.entries) {
      final Object? value = entry.value;
      if (value == null) continue;

      // 25 parameters per event, and the rest are dropped by the SDK without
      // saying so. Nothing here comes close, but the cap is silent, so it is
      // enforced where it can be seen.
      if (out.length >= maxParameters) break;

      final String key = _clamp(entry.key, maxKeyLength);

      out[key] = switch (value) {
        bool b => b ? 1 : 0,
        num n => n,
        // Truncated rather than dropped: a value over the limit takes the
        // whole event down with it.
        _ => _clamp('$value', maxValueLength),
      };
    }

    return out;
  }

  static const int maxParameters = 25;
  static const int maxKeyLength = 40;
  static const int maxValueLength = 100;

  static String _clamp(String value, int limit) =>
      value.length <= limit ? value : value.substring(0, limit);

  /// How long a piece of text was, as a bucket rather than a number.
  ///
  /// A length is not content, but an exact length is a fingerprint — it is
  /// enough to recognise a specific message in a list of them. Buckets answer
  /// the only question anybody actually asks ("are people writing sentences or
  /// paragraphs") and answer nothing else.
  static String lengthBucket(int length) {
    if (length == 0) return 'empty';
    if (length <= 40) return 'short';
    if (length <= 200) return 'medium';
    if (length <= 1000) return 'long';
    return 'very_long';
  }

  @override
  String toString() {
    if (params.isEmpty) return name;
    final String detail = firebaseParameters.entries
        .map((MapEntry<String, Object> e) => '${e.key}=${e.value}')
        .join(' ');
    return '$name $detail';
  }

  // --- Launch ------------------------------------------------------------

  /// The app got all the way to `runApp`. Paired with [startupFailed], this is
  /// the denominator for "how often does launch actually work".
  factory AnalyticsEvent.startupCompleted({required int milliseconds}) =>
      AnalyticsEvent('startup_completed', {'duration_ms': milliseconds});

  /// Launch died, at the named step. The step is the whole value here: `main`
  /// already tracks one so the failure screen can name it.
  factory AnalyticsEvent.startupFailed({
    required String step,
    required String errorType,
  }) =>
      AnalyticsEvent('startup_failed', {'step': step, 'error': errorType});

  // --- Auth --------------------------------------------------------------

  factory AnalyticsEvent.signInStarted({required String provider}) =>
      AnalyticsEvent('sign_in_started', {'provider': provider});

  factory AnalyticsEvent.signInSucceeded({
    required String provider,
    required bool isNewUser,
  }) =>
      AnalyticsEvent('sign_in_succeeded', {
        'provider': provider,
        'is_new_user': isNewUser,
      });

  /// [reason] is a category — `cancelled`, `network`, `rejected` — never the
  /// provider's error text, which can carry an email address.
  factory AnalyticsEvent.signInFailed({
    required String provider,
    required String reason,
  }) =>
      AnalyticsEvent('sign_in_failed', {
        'provider': provider,
        'reason': reason,
      });

  factory AnalyticsEvent.signedOut() => const AnalyticsEvent('signed_out');

  factory AnalyticsEvent.accountDeleted() =>
      const AnalyticsEvent('account_deleted');

  // --- Onboarding --------------------------------------------------------

  /// One of the five steps came into view. The funnel is built from these.
  factory AnalyticsEvent.onboardingStep({required String step}) =>
      AnalyticsEvent('onboarding_step', {'step': step});

  /// The plan was computed and shown. Carries the plan's own shape so a
  /// nonsense target — a 900 calorie bulk — is visible as a pattern rather
  /// than waiting for somebody to report it.
  factory AnalyticsEvent.planRevealed({
    required int calories,
    required int proteinG,
    required String activityLevel,
    required String unitSystem,
  }) =>
      AnalyticsEvent('plan_revealed', {
        'calories': calories,
        'protein_g': proteinG,
        'activity_level': activityLevel,
        'unit_system': unitSystem,
      });

  /// Onboarding finished and the profile was written.
  factory AnalyticsEvent.onboardingCompleted({required int seconds}) =>
      AnalyticsEvent('onboarding_completed', {'duration_s': seconds});

  /// Body stats were corrected after the fact, which is the signal that a
  /// step of onboarding asked badly.
  factory AnalyticsEvent.bodyStatsEdited({required String field}) =>
      AnalyticsEvent('body_stats_edited', {'field': field});

  // --- Food and meals ----------------------------------------------------

  /// A search resolved. [tier] is which of the three answered — `cache`,
  /// `hosted`, `off`, or `none` — which is the number that says whether tiers
  /// 2 and 3 are still earning their complexity.
  ///
  /// The query itself is never sent. Its length is, bucketed.
  factory AnalyticsEvent.foodSearched({
    required String tier,
    required int resultCount,
    required int queryLength,
    required int milliseconds,
  }) =>
      AnalyticsEvent('food_searched', {
        'tier': tier,
        'results': resultCount,
        'query_len': lengthBucket(queryLength),
        'duration_ms': milliseconds,
      });

  /// A search came back with nothing from any tier. The failure mode worth
  /// counting: it is the one that sends somebody to a different app.
  factory AnalyticsEvent.foodSearchEmpty({required int queryLength}) =>
      AnalyticsEvent('food_search_empty', {
        'query_len': lengthBucket(queryLength),
      });

  /// Open Food Facts' per-device budget was reached. If this is ever common,
  /// the limiter is in the wrong place.
  factory AnalyticsEvent.foodSearchRateLimited() =>
      const AnalyticsEvent('food_search_limited');

  factory AnalyticsEvent.barcodeScanned({required bool found}) =>
      AnalyticsEvent('barcode_scanned', {'found': found});

  factory AnalyticsEvent.mealCreated({
    required int ingredientCount,
    required bool hasPhoto,
    required bool isPublic,
  }) =>
      AnalyticsEvent('meal_created', {
        'ingredients': ingredientCount,
        'has_photo': hasPhoto,
        'is_public': isPublic,
      });

  factory AnalyticsEvent.mealEdited({required int ingredientCount}) =>
      AnalyticsEvent('meal_edited', {'ingredients': ingredientCount});

  factory AnalyticsEvent.mealDeleted() => const AnalyticsEvent('meal_deleted');

  /// Something was logged against a day. [source] says where it came from —
  /// `library`, `search`, `barcode`, `repeat` — which is how the tracker's
  /// entry points get ranked against each other.
  factory AnalyticsEvent.mealLogged({
    required String slot,
    required String source,
  }) =>
      AnalyticsEvent('meal_logged', {'slot': slot, 'source': source});

  /// A meal was taken off somebody else's post into the user's own library.
  /// The clearest signal that the social half is feeding the tracking half.
  factory AnalyticsEvent.mealCopiedFromPost() =>
      const AnalyticsEvent('meal_copied_from_post');

  factory AnalyticsEvent.dayRepeated({required int entryCount}) =>
      AnalyticsEvent('day_repeated', {'entries': entryCount});

  // --- Tracker -----------------------------------------------------------

  /// [dayOffset] is days from today — negative for the past. It answers
  /// whether the day strip is used for anything or whether everyone only ever
  /// looks at today.
  factory AnalyticsEvent.trackerDayViewed({required int dayOffset}) =>
      AnalyticsEvent('tracker_day_viewed', {'day_offset': dayOffset});

  factory AnalyticsEvent.weightLogged({required String method}) =>
      AnalyticsEvent('weight_logged', {'method': method});

  factory AnalyticsEvent.waterLogged({required int millilitres}) =>
      AnalyticsEvent('water_logged', {'ml': millilitres});

  factory AnalyticsEvent.waterGoalChanged({required bool custom}) =>
      AnalyticsEvent('water_goal_changed', {'custom': custom});

  factory AnalyticsEvent.weeklyRecapOpened() =>
      const AnalyticsEvent('weekly_recap_opened');

  /// An insight card was acted on rather than read past. Insight text is a
  /// translation key, not user content, so it travels.
  factory AnalyticsEvent.insightActioned({required String titleKey}) =>
      AnalyticsEvent('insight_actioned', {'insight': titleKey});

  // --- Feed and posting --------------------------------------------------

  factory AnalyticsEvent.feedViewed({required String tab, String? label}) =>
      AnalyticsEvent('feed_viewed', {'tab': tab, 'label': label});

  /// A page beyond the first was fetched. [pageIndex] going deep is the
  /// evidence that paging is worth what it costs.
  factory AnalyticsEvent.feedPaged({
    required String tab,
    required int pageIndex,
  }) =>
      AnalyticsEvent('feed_paged', {'tab': tab, 'page': pageIndex});

  factory AnalyticsEvent.postCreated({
    required String label,
    required int imageCount,
    required bool hasMeal,
    required String visibility,
    required int bodyLength,
    required bool inGroup,
  }) =>
      AnalyticsEvent('post_created', {
        'label': label,
        'images': imageCount,
        'has_meal': hasMeal,
        'visibility': visibility,
        'body_len': lengthBucket(bodyLength),
        'in_group': inGroup,
      });

  /// A post was opened on its own. [source] separates a tap in the feed from
  /// a link somebody was sent — the only way to tell whether sharing works.
  factory AnalyticsEvent.postOpened({required String source}) =>
      AnalyticsEvent('post_opened', {'source': source});

  factory AnalyticsEvent.postLiked({required bool liked}) =>
      AnalyticsEvent('post_liked', {'liked': liked});

  factory AnalyticsEvent.postSaved({required bool saved}) =>
      AnalyticsEvent('post_saved', {'saved': saved});

  factory AnalyticsEvent.postShared() => const AnalyticsEvent('post_shared');

  factory AnalyticsEvent.postDeleted() => const AnalyticsEvent('post_deleted');

  factory AnalyticsEvent.commentAdded({required int bodyLength}) =>
      AnalyticsEvent('comment_added', {'body_len': lengthBucket(bodyLength)});

  // --- People, groups, challenges ---------------------------------------

  factory AnalyticsEvent.profileViewed({required bool isSelf}) =>
      AnalyticsEvent('profile_viewed', {'is_self': isSelf});

  factory AnalyticsEvent.followChanged({required bool following}) =>
      AnalyticsEvent('follow_changed', {'following': following});

  factory AnalyticsEvent.groupCreated({required bool isPrivate}) =>
      AnalyticsEvent('group_created', {'is_private': isPrivate});

  factory AnalyticsEvent.groupMembershipChanged({required bool joined}) =>
      AnalyticsEvent('group_membership', {'joined': joined});

  factory AnalyticsEvent.challengeJoined({required String metric}) =>
      AnalyticsEvent('challenge_joined', {'metric': metric});

  factory AnalyticsEvent.challengeLeft() =>
      const AnalyticsEvent('challenge_left');

  /// [scope] is which tab of search — people, groups, meals. The term is not
  /// sent, only how long it was.
  factory AnalyticsEvent.searchPerformed({
    required String scope,
    required int resultCount,
    required int queryLength,
  }) =>
      AnalyticsEvent('search_performed', {
        'scope': scope,
        'results': resultCount,
        'query_len': lengthBucket(queryLength),
      });

  // --- Messages ----------------------------------------------------------

  factory AnalyticsEvent.conversationOpened() =>
      const AnalyticsEvent('conversation_opened');

  factory AnalyticsEvent.messageSent({required int bodyLength}) =>
      AnalyticsEvent('message_sent', {'body_len': lengthBucket(bodyLength)});

  factory AnalyticsEvent.messageFailed({required String reason}) =>
      AnalyticsEvent('message_failed', {'reason': reason});

  // --- Moderation --------------------------------------------------------

  /// An image was refused on the device. [score] and [threshold] are the whole
  /// point: the threshold is uncalibrated, the score was being printed to a
  /// console nobody can read, and a distribution of real refusals is the only
  /// thing that can move it off a number picked by intuition.
  factory AnalyticsEvent.imageRefused({
    required double score,
    required double threshold,
    required String variant,
  }) =>
      AnalyticsEvent('image_refused', {
        // Two decimal places: enough to bucket, not enough to pretend the
        // model is precise.
        'score': double.parse(score.toStringAsFixed(2)),
        'threshold': threshold,
        'variant': variant,
      });

  /// An image was allowed, and what the highest score was. Sent for the
  /// allowed case too, because a threshold cannot be judged from refusals
  /// alone — the false negatives are the half that does not complain.
  factory AnalyticsEvent.imageAllowed({
    required double score,
    required String variant,
  }) =>
      AnalyticsEvent('image_allowed', {
        'score': double.parse(score.toStringAsFixed(2)),
        'variant': variant,
      });

  /// Every rendering failed to score, so the check did not run and the upload
  /// was allowed anyway.
  ///
  /// This is the most important event in the file. It is the exact silent
  /// failure that shipped a broken TensorFlow Lite build for a whole release:
  /// every call threw, every call was allowed by the fail-open branch, and
  /// from the outside it was indistinguishable from a model that was working.
  factory AnalyticsEvent.imageCheckDidNotRun({required String reason}) =>
      AnalyticsEvent('image_check_skipped', {'reason': reason});

  /// The Android model finished downloading and loading, and how long it took.
  ///
  /// The number that says whether the fetch is fast enough to sit behind a
  /// post, or whether it needs to move earlier than the composer.
  factory AnalyticsEvent.moderationModelReady({
    required int milliseconds,
    required bool mirrored,
  }) =>
      AnalyticsEvent('moderation_model_ready', {
        'duration_ms': milliseconds,
        // Whether it came from our own mirror or the plugin's third-party
        // default — see ModerationConfig.
        'mirrored': mirrored,
      });

  /// The model could not be fetched, so the next upload goes unchecked.
  ///
  /// Paired with [imageCheckDidNotRun]. This one says *why* the model was
  /// missing; that one says an upload went through without it. If either is
  /// anything but near-zero on Android, moderation is off there.
  factory AnalyticsEvent.moderationModelFailed({
    required String kind,
    required int milliseconds,
  }) =>
      AnalyticsEvent('moderation_model_failed', {
        'kind': kind,
        'duration_ms': milliseconds,
      });

  /// A blocked term was refused by the database. [surface] is post, comment or
  /// message. The term itself is emphatically not sent.
  factory AnalyticsEvent.termBlocked({required String surface}) =>
      AnalyticsEvent('term_blocked', {'surface': surface});

  factory AnalyticsEvent.contentReported({
    required String reason,
    required String surface,
  }) =>
      AnalyticsEvent('content_reported', {
        'reason': reason,
        'surface': surface,
      });

  factory AnalyticsEvent.userBlocked({required bool blocked}) =>
      AnalyticsEvent('user_blocked', {'blocked': blocked});

  factory AnalyticsEvent.postHidden() => const AnalyticsEvent('post_hidden');

  // --- Push --------------------------------------------------------------

  factory AnalyticsEvent.pushPermission({required String status}) =>
      AnalyticsEvent('push_permission', {'status': status});

  factory AnalyticsEvent.pushRegistered({required String platform}) =>
      AnalyticsEvent('push_registered', {'platform': platform});

  /// A notification was tapped, and from which state — `cold` means it
  /// launched the app.
  factory AnalyticsEvent.pushOpened({
    required String kind,
    required bool fromCold,
  }) =>
      AnalyticsEvent('push_opened', {'kind': kind, 'from_cold': fromCold});

  // --- Reliability -------------------------------------------------------

  /// A request failed, categorised. [operation] is a stable name for the call
  /// site — `feed.discover`, `meal.save` — and [kind] is the shape of the
  /// failure from `describeError`: `offline`, `timeout`, `permission`,
  /// `blocked_term`, `server`, `unknown`.
  ///
  /// This is what turns "the app feels broken on the train" into a number.
  factory AnalyticsEvent.requestFailed({
    required String operation,
    required String kind,
    String? code,
  }) =>
      AnalyticsEvent('request_failed', {
        'operation': operation,
        'kind': kind,
        'code': code,
      });

  /// An upload finished, with its size and how long it took. Photos are the
  /// slowest thing the app does and the only one billed by the byte.
  factory AnalyticsEvent.imageUploaded({
    required int kilobytes,
    required int milliseconds,
  }) =>
      AnalyticsEvent('image_uploaded', {
        'size_kb': kilobytes,
        'duration_ms': milliseconds,
      });

  // --- Money -------------------------------------------------------------

  /// An account crossed the line between free and premium, in either
  /// direction. [source] is the store or grant that did it — `app_store`,
  /// `play`, `promo`, `manual` — never anything the user typed.
  ///
  /// Fired on the transition only, not on every launch, so the count is a
  /// count of conversions and lapses rather than a count of cold starts.
  factory AnalyticsEvent.entitlementChanged({
    required bool premium,
    String? source,
  }) =>
      AnalyticsEvent('entitlement_changed', {
        'premium': premium,
        'source': source,
      });

  /// Somebody on the free tier hit a ceiling. [limit] is which one:
  /// `saved_meals`, `history_days`, `active_challenges`.
  ///
  /// The number that says whether the free tier is priced on anything real. A
  /// limit nobody reaches converts nobody; a limit everybody reaches in week
  /// one is not a free tier, it is a trial, and it loses the users who would
  /// have paid in month three.
  factory AnalyticsEvent.planLimitReached({required String limit}) =>
      AnalyticsEvent('plan_limit_reached', {'limit': limit});

  /// The upgrade screen was shown, and what led there — `limit`, `settings`,
  /// `ad`, `onboarding`. Paired with [upgradeCompleted], this is the funnel.
  factory AnalyticsEvent.paywallShown({required String source}) =>
      AnalyticsEvent('paywall_shown', {'source': source});

  /// A purchase was started. [product] is the store product id, which is ours
  /// rather than the user's.
  factory AnalyticsEvent.upgradeStarted({required String product}) =>
      AnalyticsEvent('upgrade_started', {'product': product});

  factory AnalyticsEvent.upgradeCompleted({required String product}) =>
      AnalyticsEvent('upgrade_completed', {'product': product});

  /// A purchase did not finish. [reason] is a category — `cancelled`,
  /// `payment_failed`, `unavailable`, `verification_failed` — because a store
  /// error message is neither stable nor short.
  factory AnalyticsEvent.upgradeFailed({required String reason}) =>
      AnalyticsEvent('upgrade_failed', {'reason': reason});

  /// Restore-purchases finished, and whether it found anything. Worth its own
  /// event: "restore does nothing" is a common and infuriating bug, and it is
  /// invisible unless the failures are counted.
  factory AnalyticsEvent.purchasesRestored({required bool found}) =>
      AnalyticsEvent('purchases_restored', {'found': found});
}
