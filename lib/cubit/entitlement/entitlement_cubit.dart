import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/analytics_events.dart';
import '../../core/error_text.dart';
import '../../core/plan_limits.dart';
import '../../core/telemetry.dart';
import '../../data/entitlement_repository.dart';
import '../../models/entitlement.dart';

part 'entitlement_state.dart';

/// Whether this account is premium, app-wide.
///
/// App-wide because nearly every surface asks: the feed asks before drawing a
/// banner, the meal library asks before letting a twenty-first meal be saved,
/// the tracker asks before scrolling past last week. If each of them answered
/// for itself they would answer at different times and disagree — an upgrade
/// that removes the ad from the feed but leaves the lock on the library is a
/// support ticket, and a fair one.
///
/// ## It starts as free and stays usable
///
/// [load] emits the cached answer before it asks the network, so the first
/// frame after launch is right for a paying user rather than briefly showing
/// them the ads they paid to remove. If the network then disagrees, the
/// network wins.
///
/// If the network never answers — offline, server down — the cached answer
/// stands. That is the deliberate direction to fail in: a subscriber on a
/// plane keeps what they bought, and the worst case is somebody whose
/// subscription lapsed while they were offline getting an extra ad-free day.
class EntitlementCubit extends Cubit<EntitlementState> {
  EntitlementCubit({
    required EntitlementRepository repository,
    Stream<void>? purchases,
  })  : _repository = repository,
        super(const EntitlementState()) {
    // A purchase can complete at any moment, including on a launch where no
    // upgrade screen was ever opened — the store hands it back whenever it
    // gets round to it. By then the server has already written the row, so
    // this is only the app catching up with it.
    _purchases = purchases?.listen((_) => refresh());
  }

  final EntitlementRepository _repository;
  StreamSubscription<void>? _purchases;

  @override
  Future<void> close() {
    _purchases?.cancel();
    return super.close();
  }

  /// Cache first, then the server.
  ///
  /// Called at launch and after sign-in. Safe to call again — it is two reads
  /// and no writes.
  Future<void> load() async {
    final Entitlement cached = await _repository.cached();
    if (isClosed) return;

    // Only if it says something. Emitting free over an already-loaded premium
    // would put the ads back for a frame, which is the exact flicker the cache
    // exists to prevent.
    if (cached.isPremium || state.status == EntitlementStatus.initial) {
      emit(
        state.copyWith(status: EntitlementStatus.loading, entitlement: cached),
      );
    }

    await refresh();
  }

  /// Asks the server. Keeps what it had if the answer does not arrive.
  Future<void> refresh() async {
    try {
      final Entitlement fresh = await _repository.fetch();
      if (isClosed) return;

      final bool changed = fresh.isPremium != state.isPremium;

      emit(
        state.copyWith(
          status: EntitlementStatus.ready,
          entitlement: fresh,
          clearError: true,
        ),
      );

      // Only on a transition, not on every launch. What is worth knowing is
      // how many accounts cross the line and when they cross back, and an
      // event fired on every cold start would bury that under a count of
      // launches.
      if (changed) {
        await Telemetry.send(
          AnalyticsEvent.entitlementChanged(
            premium: fresh.isPremium,
            source: fresh.source,
          ),
        );
      }
    } catch (error) {
      if (isClosed) return;

      final String detail = describeError(error);
      debugPrint('Bulkr: entitlement refresh failed — $detail');

      // The entitlement itself is left alone. A failed refresh is not evidence
      // that anything changed, and treating it as a downgrade would show ads
      // to a subscriber every time their train went into a tunnel.
      emit(
        state.copyWith(status: EntitlementStatus.ready, errorMessage: detail),
      );
    }
  }

  /// Back to free, and the device forgets. Called on sign-out, before the next
  /// account's [load].
  Future<void> clear() async {
    await _repository.forget();
    if (isClosed) return;

    emit(const EntitlementState());
  }

  /// Records that somebody hit a wall, and where.
  ///
  /// The single most useful number in this whole feature: which limit people
  /// actually run into. If nobody ever reaches the saved-meal cap then the cap
  /// is not selling anything and the tier is priced on nothing, and if
  /// everybody reaches it in week one then it is too tight and it is costing
  /// users rather than converting them.
  Future<void> recordLimitReached(String limit) =>
      Telemetry.send(AnalyticsEvent.planLimitReached(limit: limit));
}
