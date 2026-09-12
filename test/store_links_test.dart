import 'dart:io';

import 'package:bulkr/core/config/legal_config.dart';
import 'package:bulkr/core/config/store_links.dart';
import 'package:flutter_test/flutter_test.dart';

/// Getting somebody to the page where they cancel.
///
/// Neither store lets an app cancel its own subscription, so every one of
/// these links is the whole of Bulkr's compliance with App Store guideline
/// 3.1.2 — a subscriber who cannot reach the cancel button has, from their
/// side, an app that took their money and hid the exit.
///
/// The links cannot be opened from a test, so what is checked is the two
/// things that break them silently: the package name drifting away from the
/// one Play knows, and a link that is not a usable https URL.
void main() {
  group('the Play subscription link', () {
    test('names the package Play actually knows', () {
      // Play answers a subscription link for an unknown package with a generic
      // page that does not name the subscription — a worse dead end than no
      // link, because it looks like it worked.
      final String gradle =
          File('android/app/build.gradle.kts').readAsStringSync();

      final RegExpMatch? applicationId =
          RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle);

      expect(applicationId, isNotNull,
          reason: 'no applicationId in android/app/build.gradle.kts');
      expect(
        StoreLinks.androidPackage,
        applicationId!.group(1),
        reason: 'StoreLinks.androidPackage has drifted from the id Play knows '
            'this app by',
      );
    });

    test('carries the product when there is one', () {
      // So Play opens the subscription itself rather than the list of
      // everything this person has ever subscribed to.
      final Uri url = Uri.parse(
        StoreLinks.subscriptionManagement(productId: 'bulkr_premium_yearly'),
      );

      expect(url.queryParameters['sku'], 'bulkr_premium_yearly');
      expect(url.queryParameters['package'], StoreLinks.androidPackage);
    });

    test('and still works without one', () {
      // An account whose row predates the product_id column. Fewer details,
      // not a broken link.
      final Uri url = Uri.parse(StoreLinks.subscriptionManagement());

      expect(url.queryParameters.containsKey('sku'), isFalse);
      expect(url.queryParameters['package'], StoreLinks.androidPackage);
    });

    test('an empty product id is treated as none', () {
      expect(
        Uri.parse(StoreLinks.subscriptionManagement(productId: ''))
            .queryParameters
            .containsKey('sku'),
        isFalse,
      );
    });
  });

  group('every link is one a browser can open', () {
    test('the management link', () {
      final Uri url = Uri.parse(
        StoreLinks.subscriptionManagement(productId: 'bulkr_premium_monthly'),
      );

      expect(url.isScheme('https'), isTrue);
      expect(url.host, isNotEmpty);
    });

    test('the terms the paywall falls back to', () {
      // Apple requires a functional terms link on the paywall and accepts
      // their standard EULA in place of custom terms. A dead link here is one
      // of the most common rejections there is, and it is invisible from
      // inside the app — the screen looks finished either way.
      final Uri url = Uri.parse(StoreLinks.appleStandardEula);

      expect(url.isScheme('https'), isTrue);
      expect(url.host, 'www.apple.com');
    });

    test('and the privacy policy it sits next to', () {
      expect(LegalConfig.hasPrivacyPolicy, isTrue,
          reason: 'the paywall links to it, so it has to be real');
    });
  });

  test('desktop is not offered a store it does not have', () {
    // Where this project is developed. A row that opens nothing is worse than
    // an absent one.
    expect(StoreLinks.isSupported, isFalse);
  });
}
