import 'package:equatable/equatable.dart';

/// What a user has paid for.
enum Tier {
  free('free'),
  premium('premium');

  const Tier(this.dbValue);

  /// Exact string in `subscriptions.tier`.
  final String dbValue;

  static Tier fromDbValue(Object? value) {
    final String text = '$value';
    for (final Tier tier in Tier.values) {
      if (tier.dbValue == text) return tier;
    }
    // Anything unrecognised is free. A future tier this build has never heard
    // of must not accidentally read as premium.
    return Tier.free;
  }
}

/// Which tier a user is on, and until when.
///
/// ## What this is and is not trusted for
///
/// This is the *client's* copy, and it decides presentation only: whether to
/// draw an ad, whether to show an upgrade prompt, whether a lock icon appears.
/// It is cached on the device so a paying user on a bad connection is not
/// suddenly shown ads, which means it is also spoofable by a patched client.
///
/// That trade is deliberate, and it is only safe because of what it does *not*
/// decide. Real limits — how many meals may be saved, how far back history
/// goes — are enforced in row-level security against `subscriptions`, which
/// the client cannot write. So the worst a forged premium buys is a missing
/// banner ad. Enforcing it here instead, and punishing real subscribers for a
/// tunnel with no signal, would be the worse trade.
///
/// See `supabase/premium.sql`.
class Entitlement extends Equatable {
  const Entitlement({
    required this.tier,
    this.expiresAt,
    this.source,
    this.productId,
  });

  /// Nobody has paid. The state every account starts in, and the one assumed
  /// whenever the answer is not known yet.
  static const Entitlement free = Entitlement(tier: Tier.free);

  final Tier tier;

  /// When the current period ends, or null for a subscription with no end —
  /// a promo, a manual grant, or a lifetime purchase.
  final DateTime? expiresAt;

  /// Where it came from: `app_store`, `play`, `promo`, `manual`. Kept for
  /// support questions, which are nearly always "I paid, why am I not
  /// premium" and are unanswerable without it.
  final String? source;

  /// Which plan — `bulkr_premium_yearly`. Decides nothing; it labels the
  /// membership screen and lets Play open the specific subscription rather
  /// than the list of everything this person has ever subscribed to.
  ///
  /// Written by `verify-purchase` from the store's own answer, so an old row
  /// from before that column existed simply has none, and the screen says a
  /// little less rather than being wrong.
  final String? productId;

  /// Whether premium features are on **right now**.
  ///
  /// Checks the clock as well as the tier, because a row can outlive its
  /// period: the store tells the server a subscription lapsed, but between
  /// that happening and this device refreshing, the cached row still says
  /// premium. Reading the date here means an expired cache degrades to free on
  /// its own rather than waiting for a round trip.
  bool get isPremium {
    if (tier != Tier.premium) return false;

    final DateTime? expiry = expiresAt;
    if (expiry == null) return true;

    return expiry.isAfter(DateTime.now());
  }

  /// True when this was premium and the period has run out. The prompt to
  /// renew is a different sentence from the prompt to subscribe.
  bool get hasLapsed => tier == Tier.premium && expiresAt != null && !isPremium;

  factory Entitlement.fromRow(Map<String, dynamic> row) => Entitlement(
    tier: Tier.fromDbValue(row['tier']),
    expiresAt: DateTime.tryParse('${row['expires_at']}')?.toLocal(),
    source: row['source'] as String?,
    productId: row['product_id'] as String?,
  );

  /// For the local cache. Only the fields that survive a restart.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'tier': tier.dbValue,
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
    if (source != null) 'source': source,
    if (productId != null) 'product_id': productId,
  };

  factory Entitlement.fromJson(Map<String, dynamic> json) =>
      Entitlement.fromRow(json);

  @override
  List<Object?> get props => <Object?>[tier, expiresAt, source, productId];
}
