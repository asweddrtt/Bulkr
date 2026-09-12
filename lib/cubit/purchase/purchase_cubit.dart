import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/analytics_events.dart';
import '../../core/config/premium_products.dart';
import '../../core/telemetry.dart';
import '../../core/trial_offer.dart';
import '../../data/purchase_service.dart';

part 'purchase_state.dart';

/// The upgrade screen's state, and the one place a purchase is started.
///
/// It does not decide whether anybody is premium — that is
/// [EntitlementCubit], reading a table this app cannot write. This only runs
/// the shop: what is for sale, what it costs here, and what happened when
/// somebody tried to buy it.
///
/// The separation matters when a purchase completes on a launch where no
/// upgrade screen was ever opened, which is common: the store hands it back
/// whenever it gets round to it. [PurchaseService] listens from startup and
/// the entitlement refreshes itself; this cubit is simply not involved.
class PurchaseCubit extends Cubit<PurchaseState> {
  PurchaseCubit({required PurchaseService service})
    : _service = service,
      super(const PurchaseState()) {
    _outcomes = _service.outcomes.listen(_onOutcome);
  }

  final PurchaseService _service;
  late final StreamSubscription<PurchaseOutcome> _outcomes;

  /// What the store says these cost, in the user's own currency.
  Future<void> load({String source = 'unknown'}) async {
    emit(state.copyWith(status: PaywallStatus.loading, clearFailure: true));

    await Telemetry.send(AnalyticsEvent.paywallShown(source: source));

    final List<ProductDetails> products = await _service.products();
    if (isClosed) return;

    if (products.isEmpty) {
      // Either the store is unreachable, or the products have not been created
      // yet. The screen says so rather than showing a button that cannot work
      // — see `docs/PREMIUM.md` for the two ids that have to exist.
      emit(state.copyWith(status: PaywallStatus.unavailable));
      return;
    }

    // Yearly first, because it is the one being recommended and the one
    // carrying the trial. Sorted rather than assumed: the store returns them
    // in whatever order it likes.
    final List<ProductDetails> ordered = <ProductDetails>[...products]
      ..sort(
        (ProductDetails a, ProductDetails b) =>
            PremiumProducts.isYearly(a.id) == PremiumProducts.isYearly(b.id)
            ? 0
            : (PremiumProducts.isYearly(a.id) ? -1 : 1),
      );

    emit(
      state.copyWith(
        status: PaywallStatus.ready,
        products: ordered,
        selectedId:
            state.selectedId ??
            (ordered.any(
                  (ProductDetails p) => p.id == PremiumProducts.preferred,
                )
                ? PremiumProducts.preferred
                : ordered.first.id),
      ),
    );
  }

  void select(String productId) {
    if (state.selectedId == productId) return;
    emit(state.copyWith(selectedId: productId, clearFailure: true));
  }

  /// Opens the store's own sheet. The result arrives later, on the stream.
  Future<void> buy() async {
    final ProductDetails? product = state.selected;
    if (product == null || state.busy) return;

    emit(state.copyWith(busy: true, clearFailure: true));

    await Telemetry.send(AnalyticsEvent.upgradeStarted(product: product.id));

    try {
      await _service.buy(product);
    } catch (error) {
      if (isClosed) return;
      debugPrint('Bulkr: could not open the purchase sheet — $error');
      emit(state.copyWith(busy: false, failure: PurchaseFailure.storeRefused));
    }
  }

  /// "Restore purchases". Apple rejects a subscription app without it, and a
  /// new phone genuinely has no local record of anything.
  Future<void> restore() async {
    if (state.busy) return;
    emit(state.copyWith(busy: true, clearFailure: true));

    await _service.restore();
  }

  Future<void> _onOutcome(PurchaseOutcome outcome) async {
    if (isClosed) return;

    if (outcome.pending) {
      // Waiting on a bank or a parent's approval. The sheet is gone and the
      // purchase is neither finished nor lost, so the screen says so and stops
      // spinning — it may be hours.
      emit(state.copyWith(busy: false, pending: true));
      return;
    }

    if (outcome.succeeded) {
      await Telemetry.send(
        AnalyticsEvent.upgradeCompleted(
          product: outcome.productId ?? 'unknown',
        ),
      );
      if (isClosed) return;

      emit(state.copyWith(busy: false, succeeded: true, clearFailure: true));
      return;
    }

    final PurchaseFailure failure =
        outcome.failure ?? PurchaseFailure.storeRefused;

    if (failure == PurchaseFailure.nothingToRestore) {
      await Telemetry.send(AnalyticsEvent.purchasesRestored(found: false));
    } else if (failure != PurchaseFailure.cancelled) {
      await Telemetry.send(AnalyticsEvent.upgradeFailed(reason: failure.name));
    }

    if (isClosed) return;
    emit(state.copyWith(busy: false, failure: failure));
  }

  /// Once the screen has shown the message.
  void clearFailure() {
    if (state.failure == null) return;
    emit(state.copyWith(clearFailure: true));
  }

  @override
  Future<void> close() {
    _outcomes.cancel();
    return super.close();
  }
}
