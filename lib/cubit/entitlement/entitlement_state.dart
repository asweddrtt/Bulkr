part of 'entitlement_cubit.dart';

enum EntitlementStatus {
  /// Nothing has been read yet, not even the cache.
  initial,

  /// The cache has answered; the server has not yet.
  loading,

  /// The server has answered, or has failed and the cache stands.
  ready,
}

class EntitlementState extends Equatable {
  const EntitlementState({
    this.status = EntitlementStatus.initial,
    this.entitlement = Entitlement.free,
    this.errorMessage,
  });

  final EntitlementStatus status;
  final Entitlement entitlement;

  /// Why the last refresh failed, for a debug build and for a settings screen
  /// that wants to say "couldn't check your subscription". Never a reason to
  /// change what the user gets — see the catch in [EntitlementCubit.refresh].
  final String? errorMessage;

  bool get isPremium => entitlement.isPremium;

  /// True when this account paid and the period has run out — the difference
  /// between "subscribe" and "renew", which are different sentences.
  bool get hasLapsed => entitlement.hasLapsed;

  /// What this account may do. Everything that gates on the plan reads this
  /// rather than [isPremium], so the question at the call site stays "how many
  /// meals may I keep" instead of "am I premium, and what did that mean
  /// again".
  PlanLimits get limits => PlanLimits.of(entitlement);

  /// Whether ads should be drawn. Its own getter because it is asked from
  /// widget `build` methods often enough to deserve a name.
  bool get showsAds => limits.showsAds;

  EntitlementState copyWith({
    EntitlementStatus? status,
    Entitlement? entitlement,
    String? errorMessage,
    bool clearError = false,
  }) {
    return EntitlementState(
      status: status ?? this.status,
      entitlement: entitlement ?? this.entitlement,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, entitlement, errorMessage];
}
