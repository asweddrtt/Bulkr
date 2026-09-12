import 'package:bulkr/core/config/premium_products.dart';
import 'package:bulkr/core/trial_offer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The free trial, and the fact that it is read rather than written down.
///
/// Bulkr's yearly plan has a seven-day trial. Putting "7 days free" in the
/// app's own copy would be right for most people and wrong for the ones that
/// matter: somebody who has already used it is not offered it again, and the
/// stores decide that. Promising a trial to a person who will be charged today
/// is a guideline 2.3.1 problem and, more to the point, a lie.
///
/// What can be tested without a store account is the period parsing, which is
/// also the part most likely to be quietly wrong — Play returns the same seven
/// days as `P1W` for one product and `P7D` for another, depending on how it
/// was entered in the console.
void main() {
  group('ISO 8601 periods', () {
    test('the two spellings of a week agree', () {
      expect(TrialOffer.isoPeriodInDays('P1W'), 7);
      expect(TrialOffer.isoPeriodInDays('P7D'), 7);
    });

    test('the periods a store actually returns', () {
      expect(TrialOffer.isoPeriodInDays('P3D'), 3);
      expect(TrialOffer.isoPeriodInDays('P2W'), 14);
      expect(TrialOffer.isoPeriodInDays('P1M'), 30);
      expect(TrialOffer.isoPeriodInDays('P1Y'), 365);
    });

    test('combined parts add up', () {
      expect(TrialOffer.isoPeriodInDays('P1M15D'), 45);
    });

    test('anything unrecognised is no trial rather than a wrong one', () {
      // Zero reads as "no trial", so the line is simply absent. The failure
      // this avoids is a screen confidently offering "0 days free".
      for (final String junk in const <String>[
        '',
        'P',
        'weekly',
        '7D',
        'P1X',
        'PT1H',
      ]) {
        expect(TrialOffer.isoPeriodInDays(junk), 0, reason: 'for "$junk"');
      }
    });

    test('a trial is never negative', () {
      expect(TrialOffer.isoPeriodInDays('P-1D'), 0);
    });
  });

  group('the products', () {
    test('the yearly one is what is shown first', () {
      // It is the cheaper of the two per month, the one this category
      // converts on, and the one carrying the trial.
      expect(PremiumProducts.preferred, PremiumProducts.yearly);
      expect(PremiumProducts.isYearly(PremiumProducts.preferred), isTrue);
    });

    test('both are asked for at the store', () {
      expect(PremiumProducts.all, hasLength(2));
      expect(PremiumProducts.all, contains(PremiumProducts.monthly));
      expect(PremiumProducts.all, contains(PremiumProducts.yearly));
    });

    test('a product we do not sell is not ours', () {
      // Checked on the way in from the purchase stream, which also delivers
      // restored purchases of anything this account has ever bought.
      expect(PremiumProducts.isPremium('some_other_app_product'), isFalse);
      expect(PremiumProducts.isPremium(''), isFalse);
      expect(PremiumProducts.isPremium(PremiumProducts.monthly), isTrue);
    });

    test('the ids are the same on both stores', () {
      // A product named differently per platform means every place that asks
      // "is this the yearly one" has to know which platform it is on.
      for (final String id in PremiumProducts.all) {
        expect(id, matches(RegExp(r'^[a-z0-9_]+$')),
            reason: 'store product ids allow no punctuation beyond _');
      }
    });
  });
}
