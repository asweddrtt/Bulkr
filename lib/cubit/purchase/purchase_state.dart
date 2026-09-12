part of 'purchase_cubit.dart';

/// Named for the screen rather than for the purchase, because
/// `in_app_purchase` exports a `PurchaseStatus` of its own and the two would
/// be ambiguous in every file that shows a paywall.
enum PaywallStatus {
  initial,
  loading,

  /// Products came back and can be bought.
  ready,

  /// The store is unreachable, or the products do not exist yet. A real state
  /// rather than an error: it is what every build looks like until somebody
  /// creates them in App Store Connect and Play Console.
  unavailable,
}

class PurchaseState extends Equatable {
  const PurchaseState({
    this.status = PaywallStatus.initial,
    this.plans = const <PremiumPlan>[],
    this.selectedId,
    this.busy = false,
    this.pending = false,
    this.preview = false,
    this.succeeded = false,
    this.failure,
  });

  final PaywallStatus status;

  /// Yearly first, one per product id. Prices come from the store, in the
  /// user's own currency — never from anything written down in this app.
  ///
  /// [PremiumPlan] rather than the store's own `ProductDetails`, because on
  /// Play those arrive one per *offer* and two of them can describe the same
  /// plan. See that class for what goes wrong otherwise.
  final List<PremiumPlan> plans;

  final String? selectedId;

  /// A purchase or a restore is in flight.
  final bool busy;

  /// The store is waiting on something — a bank, a parent's approval. Neither
  /// finished nor lost, and it can be hours, so the screen says so instead of
  /// spinning.
  final bool pending;

  /// These plans came from [PremiumPlan.samples], not from a store.
  ///
  /// Debug builds only, so the paywall can be photographed before the products
  /// exist — see that method. Nothing can be bought in this state.
  final bool preview;

  /// Verified, written, and premium. The screen closes itself on this.
  final bool succeeded;

  final PurchaseFailure? failure;

  PremiumPlan? get selected {
    final String? id = selectedId;
    if (id == null) return null;

    for (final PremiumPlan plan in plans) {
      if (plan.id == id) return plan;
    }
    return null;
  }

  /// The trial the store is offering on the selected plan, if any.
  ///
  /// Read from the store rather than written down, because somebody who has
  /// already used it is not offered it again — and promising a trial to
  /// someone who will be charged today is a lie as well as a guideline
  /// problem. See [TrialOffer].
  TrialOffer? get trial => selected?.trial;

  bool get canBuy =>
      status == PaywallStatus.ready && selected != null && !busy;

  PurchaseState copyWith({
    PaywallStatus? status,
    List<PremiumPlan>? plans,
    String? selectedId,
    bool? busy,
    bool? pending,
    bool? preview,
    bool? succeeded,
    PurchaseFailure? failure,
    bool clearFailure = false,
  }) {
    return PurchaseState(
      status: status ?? this.status,
      plans: plans ?? this.plans,
      selectedId: selectedId ?? this.selectedId,
      busy: busy ?? this.busy,
      pending: pending ?? this.pending,
      preview: preview ?? this.preview,
      succeeded: succeeded ?? this.succeeded,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    // By id: ProductDetails has no value equality, so two identical lists
    // from two queries would otherwise never compare equal and every
    // refresh would rebuild the screen.
    plans,
    selectedId,
    busy,
    pending,
    preview,
    succeeded,
    failure,
  ];
}
