import 'dart:io';

import 'package:bulkr/core/ad_policy.dart';
import 'package:bulkr/core/config/ads_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a full-screen ad may interrupt somebody.
///
/// This is the file to argue with. An interstitial is the format most able to
/// make a person delete a daily-use app, and the ones that do it are never the
/// first ad — they are the fourth in ten minutes, or the one that arrived
/// before the user had worked out what the app was for. So every rule here is
/// about rhythm, and each test names the thing it is protecting.
void main() {
  final DateTime now = DateTime(2026, 9, 12, 14, 0);

  /// An account that has been installed long enough to be eligible, with
  /// nothing shown yet and enough actions behind it.
  AdState settled({
    DateTime? lastShown,
    int shownToday = 0,
    DateTime? countedDay,
    DateTime? adFreeUntil,
    int actions = AdPolicy.actionsBetween,
  }) =>
      AdState(
        firstSeenAt: now.subtract(const Duration(days: 9)),
        lastInterstitialAt: lastShown,
        shownToday: shownToday,
        countedDay: countedDay,
        adFreeUntil: adFreeUntil,
        actionsSinceLast: actions,
      );

  AdBlock verdict(
    AdState state, {
    AdTrigger trigger = AdTrigger.completedAction,
    bool isPremium = false,
    Duration? awayFor,
  }) =>
      AdPolicy.evaluate(
        trigger: trigger,
        state: state,
        isPremium: isPremium,
        awayFor: awayFor,
        now: now,
      );

  group('the two absolutes', () {
    test('a paying account never sees one', () {
      // Checked before everything else, because no amount of good timing makes
      // an ad acceptable to somebody who paid to remove them.
      expect(verdict(settled(), isPremium: true), AdBlock.premium);
    });

    test('an earned ad-free window is honoured', () {
      // The entire product. An app that takes thirty seconds of somebody's
      // attention for a reward and then shows the ad anyway has taught them
      // never to accept an offer again, which costs more than the ad earned.
      final AdState state =
          settled(adFreeUntil: now.add(const Duration(hours: 3)));

      expect(verdict(state), AdBlock.rewardEarned);
    });

    test('and it expires', () {
      final AdState state =
          settled(adFreeUntil: now.subtract(const Duration(minutes: 1)));

      expect(verdict(state), AdBlock.none);
    });
  });

  group('the first day', () {
    test('a brand-new install is never interrupted', () {
      // The value has to land before the ask does, and on day one it has not.
      final AdState state = AdState(
        firstSeenAt: now.subtract(const Duration(hours: 2)),
        actionsSinceLast: 10,
      );

      expect(verdict(state), AdBlock.newUser);
    });

    test('an install with no recorded start is treated as new', () {
      // Fails towards showing nothing. A null here means the write that stamps
      // the install did not happen, and guessing "old enough" would put an ad
      // in front of the one user who has seen nothing of the app yet.
      expect(verdict(const AdState(actionsSinceLast: 10)), AdBlock.newUser);
    });

    test('the day after, it is allowed', () {
      final AdState state = AdState(
        firstSeenAt: now.subtract(const Duration(hours: 25)),
        actionsSinceLast: AdPolicy.actionsBetween,
      );

      expect(verdict(state), AdBlock.none);
    });
  });

  group('rhythm', () {
    test('two ads cannot land close together', () {
      final AdState state = settled(
        lastShown: now.subtract(const Duration(minutes: 1)),
        shownToday: 1,
        countedDay: now,
      );

      expect(verdict(state), AdBlock.cooldown);
    });

    test('the save right after an ad does not produce another', () {
      // Without this, saving three meals in a row produces three ads — the
      // single most uninstall-producing pattern there is. The cooldown alone
      // does not catch it, because somebody entering a week of meals takes
      // longer than four minutes.
      final AdState state = settled(
        lastShown: now.subtract(const Duration(hours: 1)),
        shownToday: 1,
        countedDay: now,
        actions: 1,
      );

      expect(verdict(state), AdBlock.tooSoonAfterAction);
    });

    test('enough actions later, it is allowed', () {
      final AdState state = settled(
        lastShown: now.subtract(const Duration(hours: 1)),
        shownToday: 1,
        countedDay: now,
        actions: AdPolicy.actionsBetween,
      );

      expect(verdict(state), AdBlock.none);
    });

    test('the daily cap holds', () {
      // Aimed at the heavy user, who is both the person shown the most ads and
      // the person most worth keeping.
      final AdState state = settled(
        lastShown: now.subtract(const Duration(hours: 2)),
        shownToday: AdPolicy.maxPerDay,
        countedDay: now,
        actions: 99,
      );

      expect(verdict(state), AdBlock.dailyCap);
    });

    test('yesterday\'s count does not spend today\'s allowance', () {
      // The cap rolls over by comparing dates rather than by a timer, because
      // the app is usually closed at midnight and a timer that has to be
      // running is a cap that resets whenever it is convenient for it not to.
      final AdState state = settled(
        lastShown: now.subtract(const Duration(days: 1)),
        shownToday: AdPolicy.maxPerDay,
        countedDay: now.subtract(const Duration(days: 1)),
        actions: 99,
      );

      expect(AdPolicy.shownOn(state, now), 0);
      expect(verdict(state), AdBlock.none);
    });
  });

  group('coming back', () {
    test('a real absence counts as a seam', () {
      // Nothing was interrupted, because nothing was in progress. This is why
      // the return trigger does not also require completed actions — and the
      // state here has none.
      final AdState state = settled(actions: 0);

      expect(
        verdict(state,
            trigger: AdTrigger.returned, awayFor: const Duration(hours: 6)),
        AdBlock.none,
      );
    });

    test('switching to Messages and back is not coming back', () {
      final AdState state = settled(actions: 0);

      expect(
        verdict(state,
            trigger: AdTrigger.returned, awayFor: const Duration(minutes: 3)),
        AdBlock.notTriggered,
      );
    });

    test('a return with no measured absence does not fire', () {
      expect(
        verdict(settled(), trigger: AdTrigger.returned),
        AdBlock.notTriggered,
      );
    });

    test('but a return still respects the daily cap', () {
      // The trigger skips the action counter. It does not skip the ceilings,
      // or somebody reopening the app all evening would see one every time.
      final AdState state = settled(
        shownToday: AdPolicy.maxPerDay,
        countedDay: now,
        actions: 0,
      );

      expect(
        verdict(state,
            trigger: AdTrigger.returned, awayFor: const Duration(hours: 9)),
        AdBlock.dailyCap,
      );
    });
  });

  group('recording what happened', () {
    test('a shown ad starts the cooldown and zeroes the counter', () {
      final AdState after = AdPolicy.recordShown(settled(), now: now);

      expect(after.lastInterstitialAt, now);
      expect(after.shownToday, 1);
      expect(after.actionsSinceLast, 0);
      expect(AdPolicy.evaluate(
        trigger: AdTrigger.completedAction,
        state: after,
        isPremium: false,
        now: now,
      ), AdBlock.cooldown);
    });

    test('counts accumulate within a day and reset across one', () {
      AdState state = AdPolicy.recordShown(settled(), now: now);
      state = AdPolicy.recordShown(state, now: now.add(const Duration(hours: 1)));

      expect(state.shownToday, 2);

      final AdState tomorrow =
          AdPolicy.recordShown(state, now: now.add(const Duration(days: 1)));
      expect(tomorrow.shownToday, 1);
    });

    test('a reward grants a full day from now, not from the old expiry', () {
      // Watching a second ad an hour in buys 24 hours, not 47. Somebody who
      // wants two days can come back tomorrow — which is also what keeps the
      // offer worth anything.
      final AdState state =
          settled(adFreeUntil: now.add(const Duration(hours: 23)));

      final AdState after = AdPolicy.grantAdFree(state, now: now);

      expect(after.adFreeUntil, now.add(AdPolicy.rewardWindow));
    });

    test('the install stamp is written once and never moved', () {
      // Moving it would restart the new-user grace on every launch, which is
      // an app that shows no interstitials at all — a silent failure, and the
      // expensive direction to be wrong in.
      final AdState first = AdPolicy.seed(AdState.fresh, now: now);
      final AdState again =
          AdPolicy.seed(first, now: now.add(const Duration(days: 30)));

      expect(again.firstSeenAt, now);
    });

    test('survives a round trip through the cache', () {
      // The caps are worthless if they reset when the app is killed, which is
      // exactly when somebody who has seen four ads comes back for a fifth.
      final AdState before = AdPolicy.recordShown(
        AdPolicy.grantAdFree(settled(), now: now),
        now: now,
      );

      expect(AdState.fromJson(before.toJson()), before);
    });
  });

  group('ad units', () {
    test('desktop has none, and says so rather than guessing', () {
      // Where this project is developed. Everything ad-shaped checks
      // `isSupported` first, so a development build is an app with no ads —
      // and asking for a unit anyway throws here, in the line that asked,
      // rather than returning something plausible that would fail on a
      // tester's phone.
      expect(AdsConfig.isSupported, isFalse);
      expect(AdsConfig.rewardedUnit, isNull);
      expect(AdsConfig.hasRewarded, isFalse);

      expect(() => AdsConfig.bannerUnit, throwsUnsupportedError);
      expect(() => AdsConfig.interstitialUnit, throwsUnsupportedError);
    });

    group('every lookup is per-platform', () {
      // The bug this exists for: Google's *test* units are per-platform too,
      // and this file originally used the Android ones for both. An Android
      // test unit requested on iOS does not fill, so a debug build on iOS
      // would have had no ads in it at all — which looks exactly like an
      // integration that does not work, and is the kind of thing somebody
      // spends a day on.
      //
      // The real units have the same shape and a worse failure: the wrong app
      // ID crashes on launch.
      late final String source =
          File('lib/core/config/ads_config.dart').readAsStringSync();

      test('no _perPlatform call passes the same id twice', () {
        final Iterable<RegExpMatch> calls = RegExp(
          r"_perPlatform\(\s*'([^']+)'\s*,\s*'([^']+)'\s*,?\s*\)",
          dotAll: true,
        ).allMatches(source);

        expect(calls, isNotEmpty,
            reason: 'the scan found no unit lookups at all');

        for (final RegExpMatch call in calls) {
          expect(
            call.group(1),
            isNot(call.group(2)),
            reason: 'the same ad unit is used for both platforms — one of '
                'them is wrong, and it will simply never fill',
          );
        }
      });

      test('no ad unit id appears twice anywhere in the file', () {
        // Catches the same mistake made through the constants rather than
        // inline, which is how the real units are written.
        final List<String> units = RegExp(r"'(ca-app-pub-[\d]+/[\d]+)'")
            .allMatches(source)
            .map((RegExpMatch match) => match.group(1)!)
            .toList();

        expect(units, isNotEmpty);
        expect(units.toSet(), hasLength(units.length),
            reason: 'an ad unit id is used in two places, which for a '
                'per-platform lookup means one platform has the other\'s');
      });

      test('test units and real units never overlap', () {
        // Google's test publisher id is 3940256099942544. A real unit reached
        // in a debug build is how an AdMob account gets suspended for clicking
        // its own ads; a test unit reached in a release build is a day of
        // revenue thrown away.
        final Iterable<String> testUnits = RegExp(
          r"'(ca-app-pub-3940256099942544/[\d]+)'",
        ).allMatches(source).map((RegExpMatch match) => match.group(1)!);

        expect(testUnits, hasLength(6),
            reason: 'three formats, two platforms');

        for (final String unit in testUnits) {
          expect(unit, startsWith('ca-app-pub-3940256099942544/'));
        }
      });
    });
  });
}
