import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/premium_products.dart';

/// Why a purchase did not become premium.
///
/// Deliberately small. Each one is a different sentence on screen, and a
/// category that would produce the same sentence as another is not worth
/// having.
enum PurchaseFailure {
  /// They backed out. Not an error, and not worth a message.
  cancelled,

  /// The store refused — a declined card, a parental control, an unavailable
  /// product.
  storeRefused,

  /// The store said yes and the backend could not confirm it. The money may
  /// well have been taken, so this is the one case where the app has to tell
  /// somebody to try again rather than shrug.
  notVerified,

  /// This purchase is already attached to a different account. Nearly always
  /// two accounts on one phone, not an attack.
  alreadyClaimed,

  /// Restore found nothing to restore.
  nothingToRestore,
}

/// What came back from an attempt to buy or restore.
@immutable
class PurchaseOutcome {
  const PurchaseOutcome.success({required this.productId})
    : failure = null,
      pending = false;

  const PurchaseOutcome.pending()
    : failure = null,
      productId = null,
      pending = true;

  const PurchaseOutcome.failed(this.failure, {this.productId})
    : pending = false;

  final PurchaseFailure? failure;
  final String? productId;

  /// The store is waiting on something — a parent's approval, a bank. The
  /// purchase is not finished and is not lost; it arrives later, through the
  /// same stream, on whichever launch happens to be running.
  final bool pending;

  bool get succeeded => failure == null && !pending;
}

/// Buying premium, and proving it afterwards.
///
/// ## The shape of this, and why
///
/// A store purchase does not return a result. It goes out through
/// [InAppPurchase.buyNonConsumable] and comes back — minutes later, or on a
/// completely different launch — on [InAppPurchase.purchaseStream]. That is
/// not an API design to be smoothed over: it is what a purchase *is*. Somebody
/// can buy a subscription, lose signal, force-quit, and reopen the app an hour
/// later, and the purchase is still owed to them.
///
/// So everything here is stream-shaped. The stream is subscribed at startup
/// rather than when a screen opens, because the purchase that arrives while no
/// screen is listening is exactly the one that would otherwise be lost.
///
/// ## Nothing is delivered before the server agrees
///
/// Every purchase goes to the `verify-purchase` edge function, which asks the
/// store itself and writes `subscriptions`. The app never decides it is
/// premium — it cannot, there is no write policy — and this class does not
/// pretend otherwise. See supabase/functions/verify-purchase/README.md.
///
/// `completePurchase` is called even when verification fails, and that is
/// deliberate: an uncompleted iOS transaction is replayed on every launch
/// forever, which turns one bad verification into a permanent loop.
class PurchaseService {
  PurchaseService({InAppPurchase? store, SupabaseClient? client})
    : _store = store ?? InAppPurchase.instance,
      _client = client ?? Supabase.instance.client;

  final InAppPurchase _store;
  final SupabaseClient _client;

  static const String verifyFunction = 'verify-purchase';

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final StreamController<PurchaseOutcome> _outcomes =
      StreamController<PurchaseOutcome>.broadcast();

  /// Every completed attempt, whoever started it — including one that started
  /// on a previous launch.
  Stream<PurchaseOutcome> get outcomes => _outcomes.stream;

  bool _available = false;

  /// Whether the store is reachable at all. False on a device with purchases
  /// disabled, and on every desktop build.
  bool get isAvailable => _available;

  /// Starts listening. Call once, at launch.
  Future<void> start() async {
    if (_subscription != null) return;
    if (!_isSupportedPlatform) return;

    try {
      _available = await _store.isAvailable();
    } catch (error) {
      debugPrint('Bulkr: the store is unavailable — $error');
      _available = false;
      return;
    }

    if (!_available) return;

    _subscription = _store.purchaseStream.listen(
      _handle,
      onError: (Object error) {
        debugPrint('Bulkr: purchase stream failed — $error');
      },
    );
  }

  /// What the store says these cost, in the user's own currency.
  ///
  /// Empty when the store is unreachable or the products have not been created
  /// yet — which is the state until somebody sets them up in App Store Connect
  /// and Play Console, and the upgrade screen says so rather than showing a
  /// buy button that cannot work.
  Future<List<ProductDetails>> products() async {
    if (!_available) return const <ProductDetails>[];

    try {
      final ProductDetailsResponse response = await _store.queryProductDetails(
        PremiumProducts.all,
      );

      if (response.notFoundIDs.isNotEmpty) {
        // Worth a line in the log, because the usual cause is a product that
        // was never created or is still "waiting for review" — and the symptom
        // on screen is an upgrade page with one option instead of two.
        debugPrint(
          'Bulkr: store has no such products — ${response.notFoundIDs}',
        );
      }

      return response.productDetails;
    } catch (error) {
      debugPrint('Bulkr: could not read products — $error');
      return const <ProductDetails>[];
    }
  }

  /// Opens the store's own purchase sheet.
  ///
  /// Returns as soon as the sheet is showing, not when it is done. The result
  /// arrives on [outcomes] — see the note on this class.
  Future<void> buy(ProductDetails product) async {
    // `buyNonConsumable`, not `buyConsumable`, and it is the right call for a
    // subscription: consumables are things bought repeatedly and delivered
    // once each. A subscription renews under the same purchase.
    await _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Asks the store for everything this account has already bought.
  ///
  /// Required on iOS — Apple rejects a subscription app with no restore
  /// button — and genuinely needed: a new phone has no local record of
  /// anything.
  ///
  /// Results come back through the same stream as a fresh purchase, with
  /// status `restored`.
  Future<void> restore() async {
    if (!_available) {
      _outcomes.add(
        const PurchaseOutcome.failed(PurchaseFailure.nothingToRestore),
      );
      return;
    }

    try {
      await _store.restorePurchases();
    } catch (error) {
      debugPrint('Bulkr: restore failed — $error');
      _outcomes.add(
        const PurchaseOutcome.failed(PurchaseFailure.nothingToRestore),
      );
    }
  }

  Future<void> _handle(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      await _handleOne(purchase);
    }
  }

  Future<void> _handleOne(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _outcomes.add(const PurchaseOutcome.pending());
        return;

      case PurchaseStatus.canceled:
        await _finish(purchase);
        _outcomes.add(const PurchaseOutcome.failed(PurchaseFailure.cancelled));
        return;

      case PurchaseStatus.error:
        debugPrint('Bulkr: store error — ${purchase.error?.message}');
        await _finish(purchase);
        _outcomes.add(
          const PurchaseOutcome.failed(PurchaseFailure.storeRefused),
        );
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        await _verify(purchase);
        return;
    }
  }

  Future<void> _verify(PurchaseDetails purchase) async {
    // Something this account never bought, or a product we no longer sell.
    // Completed rather than ignored, so it stops coming back.
    if (!PremiumProducts.isPremium(purchase.productID)) {
      await _finish(purchase);
      return;
    }

    try {
      final FunctionResponse response = await _client.functions.invoke(
        verifyFunction,
        body: <String, dynamic>{
          'platform': Platform.isIOS ? 'ios' : 'android',
          'receipt': purchase.verificationData.serverVerificationData,
          'productId': purchase.productID,
        },
      );

      final Object? data = response.data;
      final bool premium = data is Map && data['premium'] == true;

      if (premium) {
        _outcomes.add(PurchaseOutcome.success(productId: purchase.productID));
      } else if (data is Map && data['error'] == 'already_claimed') {
        _outcomes.add(
          PurchaseOutcome.failed(
            PurchaseFailure.alreadyClaimed,
            productId: purchase.productID,
          ),
        );
      } else {
        debugPrint('Bulkr: purchase not verified — ${response.status} $data');
        _outcomes.add(
          PurchaseOutcome.failed(
            PurchaseFailure.notVerified,
            productId: purchase.productID,
          ),
        );
      }
    } catch (error) {
      debugPrint('Bulkr: verification call failed — $error');
      _outcomes.add(
        PurchaseOutcome.failed(
          PurchaseFailure.notVerified,
          productId: purchase.productID,
        ),
      );
    } finally {
      // Even on failure. An iOS transaction that is never completed is
      // replayed on every single launch, which turns one bad verification into
      // a loop the user cannot get out of — and the subscription is not lost
      // by finishing it: "restore purchases" asks the store again.
      await _finish(purchase);
    }
  }

  Future<void> _finish(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;

    try {
      await _store.completePurchase(purchase);
    } catch (error) {
      debugPrint('Bulkr: could not complete the purchase — $error');
    }
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _outcomes.close();
  }
}
