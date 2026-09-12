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
import '../../models/premium_plan.dart';

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
      //
      // Except in a debug build, where the screen is drawn with stand-in
      // prices instead. That is not a lie to anybody: it exists so the paywall
      // can be photographed for App Store Connect's review screenshot, which
      // Apple wants *before* it will accept the subscription that would make
      // this branch stop being taken. See [PremiumPlan.samples].
      if (kDebugMode) {
        emit(
          state.copyWith(
            status: PaywallStatus.ready,
            preview: true,
            plans: PremiumPlan.samples(),
            selectedId: state.selectedId ?? PremiumProducts.preferred,
          ),
        );
        return;
      }

      emit(state.copyWith(status: PaywallStatus.unavailable));
      return;
    }

    // Google Play answers with one entry per *offer*, so a yearly plan with a
    // free trial attached comes back twice under the same id. Folding them
    // into one plan each is what stops the screen drawing "Yearly" twice, one
    // of them priced at nothing — see [PremiumPlan].
    final List<PremiumPlan> plans = PremiumPlan.from(products);

    // Yearly first: it is the one being recommended and the one carrying the
    // trial. Sorted rather than assumed, because the store returns them in
    // whatever order it likes.
    plans.sort(
      (PremiumPlan a, PremiumPlan b) =>
          PremiumProducts.isYearly(a.id) == PremiumProducts.isYearly(b.id)
          ? 0
          : (PremiumProducts.isYearly(a.id) ? -1 : 1),
    );

    emit(
      state.copyWith(
        status: PaywallStatus.ready,
        plans: plans,
        selectedId:
            state.selectedId ??
            (plans.any((PremiumPlan p) => p.id == PremiumProducts.preferred)
                ? PremiumProducts.preferred
                : plans.first.id),
      ),
    );
  }

  void select(String productId) {
    if (state.selectedId == productId) return;
    emit(state.copyWith(selectedId: productId, clearFailure: true));
  }

  /// Opens the store's own sheet. The result arrives later, on the stream.
  Future<void> buy() async {
    final PremiumPlan? plan = state.selected;
    if (plan == null || state.busy) return;

    // Nothing behind these but a screenshot. Handing a made-up product to the
    // billing flow would throw, and the point of the preview is a screen that
    // looks exactly like the real one.
    if (state.preview) return;

    emit(state.copyWith(busy: true, clearFailure: true));

    await Telemetry.send(AnalyticsEvent.upgradeStarted(product: plan.id));

    try {
      // `plan.purchase`, not the base plan: on Play, handing the billing flow
      // the base plan instead of the trial offer buys the subscription without
      // the trial, and nothing anywhere says so — the user is simply charged
      // today.
      await _service.buy(plan.purchase);
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
