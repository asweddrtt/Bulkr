import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/entitlement/entitlement_cubit.dart';
import '../data/ads_service.dart';
import 'ad_policy.dart';

/// One line at a call site, so that no screen has to remember the rules.
///
/// The rules themselves are in [AdPolicy] and there are six of them. A screen
/// that has to check "is this user premium, has an ad been shown recently, is
/// it early in the day, is the install new" before saving a meal is a screen
/// that will get one of those wrong — and there are several such screens.
///
/// So the call sites say only *what happened*:
///
///     AdMoment.of(context).completed('meal_saved');
///
/// and this decides whether anything follows.
///
/// ## Why the services are read up front
///
/// Every method here is asynchronous and most call sites are about to pop a
/// route. Reading providers off a `BuildContext` after an `await`, or after
/// the widget has gone, is the classic way to produce an exception in a place
/// nobody is looking. [AdMoment.of] takes everything it needs at the moment it
/// is called, and nothing after that touches the context.
///
/// ## Why a missing provider is not an error
///
/// [of] answers with a no-op when there is no [AdsService] above it, which is
/// the case in widget tests and on desktop. An ad system is the last thing in
/// an app that should be able to break a screen: not showing an ad costs a
/// fraction of a cent, and throwing out of a save handler costs the meal
/// somebody just entered.
class AdMoment {
  const AdMoment._(this._ads, this._isPremium);

  const AdMoment.none() : _ads = null, _isPremium = true;

  final AdsService? _ads;
  final bool _isPremium;

  factory AdMoment.of(BuildContext context) {
    try {
      return AdMoment._(
        context.read<AdsService>(),
        context.read<EntitlementCubit>().state.isPremium,
      );
    } catch (_) {
      // No provider above this context. See the note on the class.
      return const AdMoment.none();
    }
  }

  /// The user finished something — a meal saved, a post published, a day
  /// copied forward.
  ///
  /// The seam between one thing and the next, and the only place a full-screen
  /// ad is a pause rather than an interruption. Counted whether or not an ad
  /// follows, because the count is what spaces the next one out.
  Future<void> completed(String placement) async {
    final AdsService? ads = _ads;
    if (ads == null) return;

    await ads.recordAction();
    await ads.maybeShowInterstitial(
      trigger: AdTrigger.completedAction,
      isPremium: _isPremium,
      placement: placement,
    );
  }

  /// The app was reopened after [awayFor].
  ///
  /// Nothing was interrupted, because nothing was in progress — which is why
  /// this does not need the action counter that [completed] does. It still
  /// needs the absence to be real; see [AdPolicy.awayThreshold].
  Future<void> returnedAfter(Duration awayFor) async {
    final AdsService? ads = _ads;
    if (ads == null) return;

    await ads.maybeShowInterstitial(
      trigger: AdTrigger.returned,
      isPremium: _isPremium,
      awayFor: awayFor,
      placement: 'return',
    );
  }
}
