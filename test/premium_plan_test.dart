import 'package:bulkr/core/config/premium_products.dart';
import 'package:bulkr/models/premium_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Folding what a store returns back into the thing a person is choosing
/// between.
///
/// The case this exists for cannot happen yet and will happen the moment a
/// seven-day trial is added to the yearly plan in Play Console: Google answers
/// `queryProductDetails` with **one entry per offer**, so a base plan plus a
/// trial offer is two entries carrying the same product id. A screen that
/// draws one card per entry draws "Yearly" twice — and since
/// `ProductDetails.price` is built from the first pricing phase, and the first
/// phase of a free trial is free, one of those cards reads "Free a year".
///
/// The Android-specific half (reading the recurring price out of the pricing
/// phases) needs `GooglePlayProductDetails`, which cannot be constructed
/// outside the plugin. What is checked here is the grouping itself and the
/// platform-agnostic fallback, which is what iOS takes.
void main() {
  ProductDetails product(String id, {String price = r'$39.99'}) =>
      ProductDetails(
        id: id,
        title: 'Bulkr Premium',
        description: 'No ads, no limits',
        price: price,
        rawPrice: 39.99,
        currencyCode: 'USD',
      );

  group('one plan per product id', () {
    test('two offers for the same subscription become one plan', () {
      // The shape Play answers with once an offer is attached to a base plan.
      final List<PremiumPlan> plans = PremiumPlan.from(<ProductDetails>[
        product(PremiumProducts.yearly),
        product(PremiumProducts.yearly, price: 'Free'),
      ]);

      expect(plans, hasLength(1),
          reason: 'the upgrade screen would otherwise draw Yearly twice');
      expect(plans.single.id, PremiumProducts.yearly);
    });

    test('different subscriptions stay separate', () {
      final List<PremiumPlan> plans = PremiumPlan.from(<ProductDetails>[
        product(PremiumProducts.yearly),
        product(PremiumProducts.monthly, price: r'$6.99'),
      ]);

      expect(plans.map((PremiumPlan p) => p.id), <String>[
        PremiumProducts.yearly,
        PremiumProducts.monthly,
      ]);
    });

    test('the order the store gave is kept', () {
      // The cubit sorts afterwards, so this only has to not scramble it —
      // but a `Map` that reordered would make that sort look broken.
      final List<PremiumPlan> plans = PremiumPlan.from(<ProductDetails>[
        product(PremiumProducts.monthly),
        product(PremiumProducts.yearly),
        product(PremiumProducts.monthly),
      ]);

      expect(plans.map((PremiumPlan p) => p.id), <String>[
        PremiumProducts.monthly,
        PremiumProducts.yearly,
      ]);
    });

    test('nothing in, nothing out', () {
      expect(PremiumPlan.from(const <ProductDetails>[]), isEmpty);
    });
  });

  group('what gets bought', () {
    test('a plan with no trial buys the only entry there is', () {
      final ProductDetails only = product(PremiumProducts.monthly);

      expect(PremiumPlan.from(<ProductDetails>[only]).single.purchase, only);
    });

    test('and reports no trial rather than inventing one', () {
      // A plain `ProductDetails` — which is what a platform this code does not
      // know about produces — carries no offer information at all. Guessing a
      // trial from that would put "7 days free" in front of somebody who is
      // about to be charged today.
      expect(
        PremiumPlan.from(<ProductDetails>[product(PremiumProducts.yearly)])
            .single
            .trial,
        isNull,
      );
    });
  });

  group('the price shown', () {
    test('is the store\'s own string on a platform with no offers', () {
      expect(
        PremiumPlan.recurringPrice(product(PremiumProducts.yearly)),
        r'$39.99',
      );
    });

    test('is carried onto the plan', () {
      final PremiumPlan plan = PremiumPlan.from(
        <ProductDetails>[product(PremiumProducts.monthly, price: r'$6.99')],
      ).single;

      expect(plan.priceLabel, r'$6.99');
    });
  });
}
