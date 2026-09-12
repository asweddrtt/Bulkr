import 'package:bulkr/core/analytics_events.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rule that stops analytics becoming a privacy incident.
///
/// Every parameter Bulkr sends is a count, a duration, an enum or a bucket.
/// None is anything a user wrote or is — no post body, no message, no search
/// term, no handle, no email, no photo URL. Analytics leaves the device, lands
/// in a console several people can open, and is retained on somebody else's
/// schedule, so a search query in a parameter is a private thing published.
///
/// Most of that is enforced by the constructors taking counts and enums, which
/// leaves no argument to pass a message body to. What is left is the shape of
/// what goes out, which is what these check — along with the Firebase limits
/// that are enforced by silently dropping the event.
void main() {
  group('parameters Firebase will accept', () {
    test('booleans become numbers, so a rate can be averaged', () {
      // 1 and 0 rather than 'true'/'false': the console and BigQuery can
      // average a number, which turns `liked` into a like rate for free.
      final AnalyticsEvent event = AnalyticsEvent.postLiked(liked: true);

      expect(event.firebaseParameters['liked'], 1);
      expect(AnalyticsEvent.postLiked(liked: false).firebaseParameters['liked'],
          0);
    });

    test('nulls are dropped rather than sent', () {
      // So a call site can pass an optional straight through without a
      // conditional around it.
      final AnalyticsEvent event = AnalyticsEvent.feedViewed(tab: 'discover');

      expect(event.firebaseParameters.containsKey('label'), isFalse);
      expect(event.firebaseParameters['tab'], 'discover');
    });

    test('an over-long value is truncated, not dropped', () {
      // A value over the limit takes the whole event down with it, so the
      // event is worth more than the tail of the string.
      final AnalyticsEvent event =
          AnalyticsEvent('test_event', <String, Object?>{'k': 'x' * 500});

      expect(
        (event.firebaseParameters['k']! as String).length,
        AnalyticsEvent.maxValueLength,
      );
    });

    test('no more parameters than Firebase keeps', () {
      final AnalyticsEvent event = AnalyticsEvent(
        'test_event',
        <String, Object?>{for (int i = 0; i < 40; i++) 'k$i': i},
      );

      expect(
        event.firebaseParameters.length,
        lessThanOrEqualTo(AnalyticsEvent.maxParameters),
      );
    });

    test('numbers pass through as numbers', () {
      final AnalyticsEvent event =
          AnalyticsEvent.waterLogged(millilitres: 250);

      expect(event.firebaseParameters['ml'], 250);
    });
  });

  group('event names Firebase will not silently drop', () {
    // 40 characters, letters digits and underscores, starting with a letter,
    // and none of the reserved prefixes. A name that breaks any of these is
    // dropped without an error, which looks exactly like nobody using the
    // feature.
    final RegExp valid = RegExp(r'^[a-z][a-z0-9_]*$');

    for (final AnalyticsEvent event in _everyEvent) {
      test(event.name, () {
        expect(event.name, matches(valid));
        expect(event.name.length, lessThanOrEqualTo(40));
        expect(event.name, isNot(startsWith('firebase_')));
        expect(event.name, isNot(startsWith('google_')));
        expect(event.name, isNot(startsWith('ga_')));
      });
    }
  });

  group('parameter keys', () {
    test('are all within the length Firebase keeps', () {
      for (final AnalyticsEvent event in _everyEvent) {
        for (final String key in event.firebaseParameters.keys) {
          expect(key.length, lessThanOrEqualTo(AnalyticsEvent.maxKeyLength),
              reason: '${event.name} has an over-long parameter key: $key');
        }
      }
    });
  });

  group('text length is bucketed, never exact', () {
    // An exact length is not content, but it is a fingerprint: it is enough to
    // pick one specific message out of a list of them. Buckets answer the only
    // question anybody asks — sentences or paragraphs — and answer nothing
    // else.
    test('an empty body is its own bucket', () {
      expect(AnalyticsEvent.lengthBucket(0), 'empty');
    });

    test('buckets widen as they go', () {
      expect(AnalyticsEvent.lengthBucket(1), 'short');
      expect(AnalyticsEvent.lengthBucket(40), 'short');
      expect(AnalyticsEvent.lengthBucket(41), 'medium');
      expect(AnalyticsEvent.lengthBucket(200), 'medium');
      expect(AnalyticsEvent.lengthBucket(201), 'long');
      expect(AnalyticsEvent.lengthBucket(1000), 'long');
      expect(AnalyticsEvent.lengthBucket(1001), 'very_long');
    });

    test('two different messages of similar length are indistinguishable', () {
      // The property that matters. 61 characters and 137 characters are both
      // just "medium", so neither can be recognised from the other.
      expect(
        AnalyticsEvent.lengthBucket(61),
        AnalyticsEvent.lengthBucket(137),
      );
    });

    test('a post body reaches the event only as a bucket', () {
      final AnalyticsEvent event = AnalyticsEvent.postCreated(
        label: 'meal',
        imageCount: 1,
        hasMeal: false,
        visibility: 'public',
        bodyLength: 'chicken and rice again, fourth day running'.length,
        inGroup: false,
      );

      expect(event.firebaseParameters['body_len'], 'medium');
      expect(event.firebaseParameters.values.join(' '),
          isNot(contains('chicken')));
    });
  });

  group('nothing carries user content', () {
    test('a search records how long the term was, not the term', () {
      final AnalyticsEvent event = AnalyticsEvent.searchPerformed(
        scope: 'people',
        resultCount: 3,
        queryLength: 'somebody@example.com'.length,
      );

      final String flattened = event.firebaseParameters.values.join(' ');
      expect(flattened, isNot(contains('@')));
      expect(event.firebaseParameters['query_len'], isA<String>());
    });

    test('a food search records the tier, not the food', () {
      final AnalyticsEvent event = AnalyticsEvent.foodSearched(
        tier: 'cache',
        resultCount: 5,
        queryLength: 11,
        milliseconds: 42,
      );

      expect(event.firebaseParameters['tier'], 'cache');
      expect(event.firebaseParameters['query_len'], 'short');
    });

    test('a blocked term is counted without naming the term', () {
      final AnalyticsEvent event = AnalyticsEvent.termBlocked(surface: 'post');

      expect(event.firebaseParameters.keys, <String>['surface']);
    });

    test('a block records that one happened, not who', () {
      final AnalyticsEvent event = AnalyticsEvent.userBlocked(blocked: true);

      expect(event.firebaseParameters.keys, <String>['blocked']);
    });
  });

  group('the image score, which is the point of collecting any of this', () {
    test('a refusal carries the score and the threshold it failed', () {
      final AnalyticsEvent event = AnalyticsEvent.imageRefused(
        score: 0.8123456,
        threshold: 0.75,
        variant: 'channels-swapped',
      );

      // Two decimals: enough to bucket a distribution, not enough to imply
      // the model is more precise than it is.
      expect(event.firebaseParameters['score'], 0.81);
      expect(event.firebaseParameters['threshold'], 0.75);
      expect(event.firebaseParameters['variant'], 'channels-swapped');
    });

    test('an allowed image is recorded too', () {
      // A threshold cannot be judged from refusals alone. The false negatives
      // — the explicit image that scored 0.7 and went up — are the half that
      // never complains, and they only exist in this data.
      final AnalyticsEvent event =
          AnalyticsEvent.imageAllowed(score: 0.31, variant: 'rgb');

      expect(event.name, 'image_allowed');
      expect(event.firebaseParameters['score'], 0.31);
    });

    test('a check that did not run says which platform it was', () {
      // The silent failure that cost a release, and currently the state of
      // every Android upload — see the note on ImageSafety.
      final AnalyticsEvent event =
          AnalyticsEvent.imageCheckDidNotRun(reason: 'android_no_model');

      expect(event.name, 'image_check_skipped');
      expect(event.firebaseParameters['reason'], 'android_no_model');
    });
  });
}

/// One of every event, so the name and key rules are checked against all of
/// them rather than against whichever handful a test remembered.
final List<AnalyticsEvent> _everyEvent = <AnalyticsEvent>[
  AnalyticsEvent.startupCompleted(milliseconds: 1200),
  AnalyticsEvent.startupFailed(step: 'loading translations', errorType: 'X'),
  AnalyticsEvent.signInStarted(provider: 'apple'),
  AnalyticsEvent.signInSucceeded(provider: 'apple', isNewUser: true),
  AnalyticsEvent.signInFailed(provider: 'google', reason: 'cancelled'),
  AnalyticsEvent.signedOut(),
  AnalyticsEvent.accountDeleted(),
  AnalyticsEvent.onboardingStep(step: 'biometrics'),
  AnalyticsEvent.planRevealed(
    calories: 3200,
    proteinG: 180,
    activityLevel: 'very_active',
    unitSystem: 'metric',
  ),
  AnalyticsEvent.onboardingCompleted(seconds: 90),
  AnalyticsEvent.bodyStatsEdited(field: 'height'),
  AnalyticsEvent.foodSearched(
      tier: 'cache', resultCount: 5, queryLength: 8, milliseconds: 30),
  AnalyticsEvent.foodSearchEmpty(queryLength: 8),
  AnalyticsEvent.foodSearchRateLimited(),
  AnalyticsEvent.barcodeScanned(found: true),
  AnalyticsEvent.mealCreated(
      ingredientCount: 4, hasPhoto: true, isPublic: false),
  AnalyticsEvent.mealEdited(ingredientCount: 4),
  AnalyticsEvent.mealDeleted(),
  AnalyticsEvent.mealLogged(slot: 'dinner', source: 'library'),
  AnalyticsEvent.mealCopiedFromPost(),
  AnalyticsEvent.dayRepeated(entryCount: 6),
  AnalyticsEvent.trackerDayViewed(dayOffset: -2),
  AnalyticsEvent.weightLogged(method: 'tracker'),
  AnalyticsEvent.waterLogged(millilitres: 250),
  AnalyticsEvent.waterGoalChanged(custom: true),
  AnalyticsEvent.weeklyRecapOpened(),
  AnalyticsEvent.insightActioned(titleKey: 'insight_protein_title'),
  AnalyticsEvent.feedViewed(tab: 'discover', label: 'meal'),
  AnalyticsEvent.feedPaged(tab: 'forYou', pageIndex: 2),
  AnalyticsEvent.postCreated(
    label: 'meal',
    imageCount: 1,
    hasMeal: true,
    visibility: 'public',
    bodyLength: 40,
    inGroup: false,
  ),
  AnalyticsEvent.postOpened(source: 'deep_link'),
  AnalyticsEvent.postLiked(liked: true),
  AnalyticsEvent.postSaved(saved: true),
  AnalyticsEvent.postShared(),
  AnalyticsEvent.postDeleted(),
  AnalyticsEvent.commentAdded(bodyLength: 30),
  AnalyticsEvent.profileViewed(isSelf: false),
  AnalyticsEvent.followChanged(following: true),
  AnalyticsEvent.groupCreated(isPrivate: false),
  AnalyticsEvent.groupMembershipChanged(joined: true),
  AnalyticsEvent.challengeJoined(metric: 'weight_gain'),
  AnalyticsEvent.challengeLeft(),
  AnalyticsEvent.searchPerformed(
      scope: 'people', resultCount: 2, queryLength: 5),
  AnalyticsEvent.conversationOpened(),
  AnalyticsEvent.messageSent(bodyLength: 25),
  AnalyticsEvent.messageFailed(reason: 'offline'),
  AnalyticsEvent.imageRefused(score: 0.9, threshold: 0.75, variant: 'rgb'),
  AnalyticsEvent.imageAllowed(score: 0.1, variant: 'rgb'),
  AnalyticsEvent.imageCheckDidNotRun(reason: 'android_no_model'),
  AnalyticsEvent.moderationModelReady(milliseconds: 4200, mirrored: true),
  AnalyticsEvent.moderationModelFailed(kind: 'timeout', milliseconds: 45000),
  AnalyticsEvent.termBlocked(surface: 'post'),
  AnalyticsEvent.contentReported(reason: 'spam', surface: 'post'),
  AnalyticsEvent.userBlocked(blocked: true),
  AnalyticsEvent.postHidden(),
  AnalyticsEvent.pushPermission(status: 'authorized'),
  AnalyticsEvent.pushRegistered(platform: 'ios'),
  AnalyticsEvent.pushOpened(kind: 'message', fromCold: true),
  AnalyticsEvent.requestFailed(
      operation: 'feed.discover', kind: 'offline', code: '42501'),
  AnalyticsEvent.imageUploaded(kilobytes: 420, milliseconds: 900),
];
