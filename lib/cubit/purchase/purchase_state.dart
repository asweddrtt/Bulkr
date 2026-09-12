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
    this.products = const <ProductDetails>[],
    this.selectedId,
    this.busy = false,
    this.pending = false,
    this.succeeded = false,
    this.failure,
  });

  final PaywallStatus status;

  /// Yearly first. Prices come from the store, in the user's own currency —
  /// never from anything written down in this app.
  final List<ProductDetails> products;

  final String? selectedId;

  /// A purchase or a restore is in flight.
  final bool busy;

  /// The store is waiting on something — a bank, a parent's approval. Neither
  /// finished nor lost, and it can be hours, so the screen says so instead of
  /// spinning.
  final bool pending;

  /// Verified, written, and premium. The screen closes itself on this.
  final bool succeeded;

  final PurchaseFailure? failure;

  ProductDetails? get selected {
    final String? id = selectedId;
    if (id == null) return null;

    for (final ProductDetails product in products) {
      if (product.id == id) return product;
    }
    return null;
  }

  /// The trial the store is offering on the selected plan, if any.
  ///
  /// Read from the store rather than written down, because somebody who has
  /// already used it is not offered it again — and promising a trial to
  /// someone who will be charged today is a lie as well as a guideline
  /// problem. See [TrialOffer].
  TrialOffer? get trial {
    final ProductDetails? product = selected;
    return product == null ? null : TrialOffer.of(product);
  }

  bool get canBuy =>
      status == PaywallStatus.ready && selected != null && !busy;

  PurchaseState copyWith({
    PaywallStatus? status,
    List<ProductDetails>? products,
    String? selectedId,
    bool? busy,
    bool? pending,
    bool? succeeded,
    PurchaseFailure? failure,
    bool clearFailure = false,
  }) {
    return PurchaseState(
      status: status ?? this.status,
      products: products ?? this.products,
      selectedId: selectedId ?? this.selectedId,
      busy: busy ?? this.busy,
      pending: pending ?? this.pending,
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
    products.map((ProductDetails p) => p.id).toList(),
    selectedId,
    busy,
    pending,
    succeeded,
    failure,
  ];
}
