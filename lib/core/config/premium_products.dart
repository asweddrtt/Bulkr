import 'package:flutter/foundation.dart';

/// The two things Bulkr sells.
///
/// The ids have to match App Store Connect and Play Console exactly, and they
/// are the same string on both stores — which is a choice worth keeping: a
/// product that is named differently per platform means every place that
/// reasons about "is this the yearly one" has to know which platform it is on.
///
/// **Prices are not here.** They live in the stores, and the app shows
/// whatever `ProductDetails.price` comes back with. Hardcoding "$39.99" would
/// be wrong in every country but one, wrong again after any price change, and
/// wrong in a way nobody notices until somebody is charged something other
/// than what the screen said.
///
/// See `docs/PREMIUM.md` for what premium is and what it costs.
@immutable
class PremiumProducts {
  const PremiumProducts._();

  static const String monthly = 'bulkr_premium_monthly';
  static const String yearly = 'bulkr_premium_yearly';

  /// What is asked for at the store. A `Set` because that is what
  /// `queryProductDetails` takes.
  static const Set<String> all = <String>{yearly, monthly};

  /// The one shown first and selected by default.
  ///
  /// The yearly, and not because it is the more expensive: it is the cheaper
  /// of the two per month, it is the one this category actually converts on,
  /// and it carries the free trial. The monthly exists mostly so the yearly
  /// has something to look cheap against, and so somebody can try a month.
  static const String preferred = yearly;

  static bool isYearly(String id) => id == yearly;

  /// Whether this is one of ours.
  ///
  /// Checked on the way *in* from the purchase stream, which also delivers
  /// restored purchases of anything this account has ever bought — including,
  /// one day, products that are no longer sold.
  static bool isPremium(String id) => all.contains(id);
}
