import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// The store pages Bulkr has to be able to send somebody to.
///
/// ## Why cancelling leaves the app
///
/// It has to. Neither store lets an app cancel its own subscription — the
/// money is Apple's or Google's, and so is the cancel button. What an app owes
/// the user, and what App Store guideline 3.1.2 requires, is a way to *reach*
/// that button that is no harder than reaching the buy button was.
///
/// So "Cancel subscription" here is one tap that opens the store's own
/// subscription page, with no confirmation sheet in front of it. A dialog
/// asking "are you sure?" before sending somebody somewhere they can change
/// their mind anyway is friction that serves us rather than them, and it is
/// the exact pattern 3.1.2 exists to stop. The confirmation happens where the
/// cancellation does.
class StoreLinks {
  const StoreLinks._();

  /// Must match `applicationId` in `android/app/build.gradle.kts`. Play
  /// answers a subscription link for the wrong package with a generic page
  /// that does not name the subscription, which is a worse dead end than no
  /// link — so `store_links_test.dart` reads the Gradle file and fails if the
  /// two drift.
  static const String androidPackage = 'com.alimahmoud.bulkr';

  /// Where the user manages, pauses or cancels what they bought.
  ///
  /// [productId] lets Play open the specific subscription rather than the list
  /// of everything they have ever subscribed to. Apple takes no equivalent
  /// parameter and always opens the list.
  static String subscriptionManagement({String? productId}) {
    if (_isApple) return 'https://apps.apple.com/account/subscriptions';

    final String base =
        'https://play.google.com/store/account/subscriptions?package=$androidPackage';

    return productId == null || productId.isEmpty
        ? base
        : '$base&sku=${Uri.encodeQueryComponent(productId)}';
  }

  /// Apple's standard licence agreement.
  ///
  /// Apple requires a functional terms link in the paywall, and accepts this
  /// one in place of custom terms — which is the right trade for an app whose
  /// subscription grants nothing unusual. If Bulkr ever writes its own,
  /// `LegalConfig.termsUrl` takes over and this stops being used.
  static const String appleStandardEula =
      'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';

  /// Whether this build is on a platform with a store at all. Desktop
  /// development builds are not, and every caller checks before offering a
  /// link that would open nothing.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }

  static bool get _isApple => !kIsWeb && Platform.isIOS;
}
