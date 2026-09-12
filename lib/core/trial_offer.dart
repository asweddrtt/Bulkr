import 'package:equatable/equatable.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

/// A free trial the store is actually offering, right now, to this person.
///
/// ## Why this is read rather than written down
///
/// Bulkr's yearly plan has a seven-day trial, configured in App Store Connect
/// and Play Console. Putting "7 days free" in the app's own copy would be
/// right for most people and wrong for the ones that matter: somebody who has
/// already used the trial is not offered it again, and the stores decide that,
/// not us. Promising a trial to a person who will be charged immediately is a
/// guideline 2.3.1 problem — and, more to the point, a lie.
///
/// So the screen says "7 days free" only when the store says there is a trial
/// on this product for this account, and says nothing when it does not.
///
/// ## What it cannot see
///
/// Nothing, on the two paths that matter — StoreKit 1 on iOS and Billing
/// Client on Android — but the plugin's StoreKit **2** product type does not
/// expose introductory offers at all in this version. If iOS is ever switched
/// to StoreKit 2, every offer silently becomes "no trial", the screen quietly
/// drops the line, and nothing else breaks. That is the right direction to
/// fail in, and it is written down here because the symptom is invisible.
class TrialOffer extends Equatable {
  const TrialOffer({required this.days});

  /// How long it lasts, in days. Weeks and months are converted, because "7
  /// days free" is a sentence and "P1W free" is not.
  final int days;

  /// The trial on [product], or null when the store is not offering one.
  static TrialOffer? of(ProductDetails product) {
    if (product is AppStoreProductDetails) return _apple(product);
    if (product is GooglePlayProductDetails) return _google(product);

    // Includes AppStoreProduct2Details — see the note on this class.
    return null;
  }

  static TrialOffer? _apple(AppStoreProductDetails product) {
    final SKProductDiscountWrapper? intro = product.skProduct.introductoryPrice;
    if (intro == null) return null;

    // A discounted introductory *price* is not a trial. Only `freeTrail`
    // is — spelling and all; that typo is in the plugin's public API.
    if (intro.paymentMode != SKProductDiscountPaymentMode.freeTrail) {
      return null;
    }

    final int days = _appleDays(intro.subscriptionPeriod);
    return days > 0 ? TrialOffer(days: days) : null;
  }

  static int _appleDays(SKProductSubscriptionPeriodWrapper period) {
    final int count = period.numberOfUnits;

    return switch (period.unit) {
      SKSubscriptionPeriodUnit.day => count,
      SKSubscriptionPeriodUnit.week => count * 7,
      SKSubscriptionPeriodUnit.month => count * 30,
      SKSubscriptionPeriodUnit.year => count * 365,
    };
  }

  static TrialOffer? _google(GooglePlayProductDetails product) {
    final List<SubscriptionOfferDetailsWrapper> offers =
        product.productDetails.subscriptionOfferDetails ??
        const <SubscriptionOfferDetailsWrapper>[];

    final int? index = product.subscriptionIndex;
    if (index == null || index >= offers.length) return null;

    // A trial is a first pricing phase that costs nothing. Play models it as a
    // phase like any other rather than as a flag, which is why this looks for
    // a zero price instead of asking a question.
    for (final PricingPhaseWrapper phase in offers[index].pricingPhases) {
      if (phase.priceAmountMicros != 0) break;

      final int days = isoPeriodInDays(phase.billingPeriod);
      if (days > 0) return TrialOffer(days: days);
    }

    return null;
  }

  /// An ISO 8601 duration — `P1W`, `P7D`, `P1M` — as a number of days.
  ///
  /// Public because it is the only part of this file that can be tested
  /// without a store, and it is the part most likely to be wrong: Play returns
  /// the same seven days as `P1W` for one product and `P7D` for another,
  /// depending on how it was entered in the console.
  ///
  /// Zero for anything unrecognised, which reads as "no trial" and so shows
  /// nothing rather than showing something wrong.
  static int isoPeriodInDays(String period) {
    final RegExpMatch? match = RegExp(
      r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$',
    ).firstMatch(period);

    if (match == null) return 0;

    int part(int group) => int.tryParse(match.group(group) ?? '') ?? 0;

    return part(1) * 365 + part(2) * 30 + part(3) * 7 + part(4);
  }

  @override
  List<Object?> get props => <Object?>[days];
}
