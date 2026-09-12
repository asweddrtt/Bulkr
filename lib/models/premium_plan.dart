import 'package:equatable/equatable.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../core/config/premium_products.dart';
import '../core/trial_offer.dart';

/// One row on the upgrade screen: a plan, its price, and its trial.
///
/// ## Why this exists at all
///
/// Because a store product is not a row. On Google Play a subscription has a
/// base plan *and* any number of offers attached to it, and
/// `queryProductDetails` returns **one `ProductDetails` per offer** — all
/// carrying the same product id. So the moment a seven-day trial is added to
/// the yearly plan in Play Console, the store starts answering with two
/// entries for `bulkr_premium_yearly`, and a screen that draws one card per
/// entry draws "Yearly" twice.
///
/// Worse, the two would not even agree on the price. `ProductDetails.price`
/// is built from the *first* pricing phase, and the first phase of a free
/// trial is free — so one of those two cards would read "Free a year".
///
/// This groups them back into the thing a person is choosing between.
///
/// ## The three things a group has to answer
///
/// - **What does it cost?** The first pricing phase that is not free, which is
///   the amount that will actually be charged and the number the store's terms
///   have to quote.
/// - **Is there a trial?** Play only returns offers the buyer is *eligible*
///   for, so an offer with a free first phase being present is the store
///   saying yes for this account. That is exactly the property the upgrade
///   screen needs and the reason it is read rather than written down.
/// - **Which entry do we buy?** The offer, not the base plan. Handing the base
///   plan to the billing flow buys the subscription without the trial, and
///   nothing anywhere says so — the user simply gets charged today.
///
/// On iOS none of this applies: StoreKit answers one product per id and
/// carries the trial on it. The grouping is a no-op there, which is the point
/// of doing it here rather than in the screen.
class PremiumPlan extends Equatable {
  const PremiumPlan({
    required this.id,
    required this.priceLabel,
    required this.purchase,
    this.trial,
  });

  /// The store product id — `bulkr_premium_yearly`.
  final String id;

  /// The recurring price, formatted by the store in the buyer's own currency.
  /// Never a free-trial phase, and never anything written down in this app.
  final String priceLabel;

  /// The entry to hand to the billing flow. The trial offer when there is one.
  final ProductDetails purchase;

  final TrialOffer? trial;

  /// Collapses what the store returned into one plan per product id.
  ///
  /// Order is preserved, so whatever the caller sorted stays sorted.
  static List<PremiumPlan> from(List<ProductDetails> products) {
    final Map<String, List<ProductDetails>> grouped =
        <String, List<ProductDetails>>{};

    for (final ProductDetails product in products) {
      grouped.putIfAbsent(product.id, () => <ProductDetails>[]).add(product);
    }

    return <PremiumPlan>[
      for (final MapEntry<String, List<ProductDetails>> entry
          in grouped.entries)
        _fold(entry.key, entry.value),
    ];
  }

  static PremiumPlan _fold(String id, List<ProductDetails> offers) {
    ProductDetails? withTrial;
    TrialOffer? trial;

    for (final ProductDetails offer in offers) {
      final TrialOffer? found = TrialOffer.of(offer);
      if (found != null) {
        withTrial = offer;
        trial = found;
        break;
      }
    }

    final ProductDetails purchase = withTrial ?? offers.first;

    return PremiumPlan(
      id: id,
      // Read off the entry being bought, so the price shown is the price that
      // will be charged when the trial ends.
      priceLabel: recurringPrice(purchase),
      purchase: purchase,
      trial: trial,
    );
  }

  /// The price after any free phase.
  ///
  /// Public because it is the piece worth testing on its own, and because it
  /// is the one that silently produces "Free a year" when it is wrong.
  static String recurringPrice(ProductDetails product) {
    if (product is! GooglePlayProductDetails) return product.price;

    final List<SubscriptionOfferDetailsWrapper> offers =
        product.productDetails.subscriptionOfferDetails ??
        const <SubscriptionOfferDetailsWrapper>[];

    final int? index = product.subscriptionIndex;
    if (index == null || index >= offers.length) return product.price;

    for (final PricingPhaseWrapper phase in offers[index].pricingPhases) {
      if (phase.priceAmountMicros != 0) return phase.formattedPrice;
    }

    // Every phase is free. Not a shape Bulkr sells, and falling back to the
    // store's own label is better than an empty string on a button.
    return product.price;
  }


  /// Plausible plans for a **debug build only**, so the paywall can be
  /// photographed before the products exist.
  ///
  /// App Store Connect wants a review screenshot of the purchase screen
  /// attached to each subscription *before* it will let you submit it — and
  /// until the subscription exists and the Paid Applications agreement is
  /// signed, StoreKit answers with nothing and the paywall correctly says the
  /// store is unreachable. There is no order of operations that resolves
  /// that; Apple simply expects a representative screenshot.
  ///
  /// So these exist to make the real screen renderable without a store behind
  /// it. Not a mock-up drawn somewhere else: the same widgets, the same
  /// layout, the same copy, with stand-in prices — which is what makes the
  /// screenshot honest.
  ///
  /// **Never reachable in a release build.** The single call site is guarded
  /// by `kDebugMode`, and `premium_plan_test.dart` reads the source and fails
  /// if that guard is ever removed or a second call site appears. A paywall
  /// showing invented prices to a real buyer is the worst bug this file could
  /// have.
  static List<PremiumPlan> samples() => <PremiumPlan>[
    PremiumPlan(
      id: PremiumProducts.yearly,
      priceLabel: r'$39.99',
      trial: const TrialOffer(days: 7),
      purchase: ProductDetails(
        id: PremiumProducts.yearly,
        title: 'Bulkr Premium',
        description: 'No ads, no limits',
        price: r'$39.99',
        rawPrice: 39.99,
        currencyCode: 'USD',
      ),
    ),
    PremiumPlan(
      id: PremiumProducts.monthly,
      priceLabel: r'$6.99',
      purchase: ProductDetails(
        id: PremiumProducts.monthly,
        title: 'Bulkr Premium',
        description: 'No ads, no limits',
        price: r'$6.99',
        rawPrice: 6.99,
        currencyCode: 'USD',
      ),
    ),
  ];

  @override
  List<Object?> get props => <Object?>[id, priceLabel, purchase.id, trial];
}
