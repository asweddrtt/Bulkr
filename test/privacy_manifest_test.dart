import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The privacy manifest, and the fact that it is actually in the app.
///
/// Apple has required one since spring 2024. Using a "required reason" API
/// without declaring it earns an ITMS-91053 email and blocks the upload — and
/// Bulkr uses four of them, through `shared_preferences`, `image_picker`,
/// `cached_network_image` and the launch stopwatch in `main`.
///
/// The second half of this file is the more important half. A manifest sitting
/// in `ios/Runner/` that was never added to the Xcode target is not in the
/// built app, and that failure is completely invisible: the repo looks
/// correct, the build is green, and the upload is rejected. It is the same
/// mistake that shipped build 4 as a white screen, when
/// `GoogleService-Info.plist` was committed but never added to the target —
/// which is why `push_service_test.dart` checks the same thing for that file.
void main() {
  late String manifest;
  late String project;

  setUpAll(() {
    final File file = File('ios/Runner/PrivacyInfo.xcprivacy');
    expect(file.existsSync(), isTrue,
        reason: 'the iOS privacy manifest is missing');
    manifest = file.readAsStringSync();
    project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  });

  group('declares every required-reason API the app reaches', () {
    // Each of these is used, and each needs a reason code or the upload is
    // rejected. The reason codes themselves are checked, not just the
    // category: a category with the wrong reason is still a rejection.
    const Map<String, String> expected = <String, String>{
      // shared_preferences, via AppPreferences.
      'NSPrivacyAccessedAPICategoryUserDefaults': 'CA92.1',
      // image_picker and the cached_network_image cache.
      'NSPrivacyAccessedAPICategoryFileTimestamp': 'C617.1',
      'NSPrivacyAccessedAPICategoryDiskSpace': 'E174.1',
      // The launch stopwatch in main(), and FoodRepository's timeouts.
      'NSPrivacyAccessedAPICategorySystemBootTime': '35F9.1',
    };

    expected.forEach((String category, String reason) {
      test(category.replaceFirst('NSPrivacyAccessedAPICategory', ''), () {
        expect(manifest, contains(category));
        expect(manifest, contains(reason),
            reason: '$category needs reason code $reason');
      });
    });
  });

  group('describes what actually leaves the device', () {
    const List<String> expected = <String>[
      // Supabase Auth.
      'NSPrivacyCollectedDataTypeEmailAddress',
      // Weight, height, calories — the point of the app.
      'NSPrivacyCollectedDataTypeHealth',
      // Meal and post photos.
      'NSPrivacyCollectedDataTypePhotosorVideos',
      // Firebase Analytics, added in this release.
      'NSPrivacyCollectedDataTypeProductInteraction',
      // Crashlytics, added in this release.
      'NSPrivacyCollectedDataTypeCrashData',
      // The FCM token in device_tokens, and the IDFA once AdMob has it.
      'NSPrivacyCollectedDataTypeDeviceID',
      // What the ad SDK sends to choose an ad, and what it reports back.
      'NSPrivacyCollectedDataTypeCoarseLocation',
      'NSPrivacyCollectedDataTypeAdvertisingData',
    ];

    for (final String type in expected) {
      test(type.replaceFirst('NSPrivacyCollectedDataType', ''), () {
        expect(manifest, contains(type));
      });
    }
  });

  group('declares the tracking that AdMob does', () {
    // This used to assert the opposite, and correctly: before AdMob there was
    // no ad SDK in the binary and no advertising identifier was read. The
    // direction has flipped, and the assertion is worth as much pointing this
    // way — a manifest that says `false` with an ad SDK in the app is the
    // discrepancy Apple's privacy report surfaces.
    test('NSPrivacyTracking is true', () {
      expect(manifest, contains('<key>NSPrivacyTracking</key>'));
      expect(
        manifest.split('<key>NSPrivacyTracking</key>')[1].trimLeft(),
        startsWith('<true/>'),
        reason: 'google_mobile_ads is a dependency, so the binary is capable '
            'of tracking — whatever any one user answers at the prompt',
      );
    });

    test('and names the domains it reaches', () {
      // `true` with an empty domain list is the worst of both: it admits the
      // tracking and tells the privacy report nothing about where the
      // connections go.
      for (final String domain in const <String>[
        'googleads.g.doubleclick.net',
        'pagead2.googlesyndication.com',
        'doubleclick.net',
      ]) {
        expect(manifest, contains(domain));
      }
    });

    test('the device identifier says it is used for advertising', () {
      // The IDFA rides in the same data type as the FCM token, and a
      // `Tracking: false` on that entry would contradict the flag above.
      final String deviceId = manifest
          .split('<string>NSPrivacyCollectedDataTypeDeviceID</string>')[1];

      expect(
        deviceId.split('<key>NSPrivacyCollectedDataTypeTracking</key>')[1]
            .trimLeft(),
        startsWith('<true/>'),
      );
      expect(
        deviceId.split('</dict>').first,
        contains('NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising'),
      );
    });
  });

  test('the tracking prompt has a usage description', () {
    // Reading the IDFA without NSUserTrackingUsageDescription in Info.plist
    // does not fail politely — iOS will not show the prompt, ATT returns
    // denied forever, and the rejection under guideline 5.1.2 arrives later.
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, contains('<key>NSUserTrackingUsageDescription</key>'));

    final String description =
        plist.split('<key>NSUserTrackingUsageDescription</key>')[1];
    expect(description.trimLeft(), startsWith('<string>'));
    expect(
      description.split('</string>').first.length,
      greaterThan(30),
      reason: 'a one-word usage description is a rejection on its own',
    );
  });

  group('the AdMob application identifier', () {
    // Not a privacy question, but the same class of mistake and there is
    // nowhere better: the SDK reads this at startup and *crashes the app on
    // launch* when it is missing or belongs to the other platform. The
    // symptom is a white screen before Dart runs, which is exactly what
    // shipped build 4.
    test('is in Info.plist, and is the iOS one', () {
      final String plist = File('ios/Runner/Info.plist').readAsStringSync();

      expect(plist, contains('<key>GADApplicationIdentifier</key>'));
      expect(plist, contains('ca-app-pub-6396760454728825~3261840114'));
      expect(
        plist,
        isNot(contains('ca-app-pub-6396760454728825~3257970685')),
        reason: 'that is the ANDROID app ID — in Info.plist it crashes the '
            'app on launch. See docs/ADMOB.md',
      );
    });

    test('is in AndroidManifest.xml, and is the Android one', () {
      final String androidManifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      expect(androidManifest,
          contains('com.google.android.gms.ads.APPLICATION_ID'));
      expect(
          androidManifest, contains('ca-app-pub-6396760454728825~3257970685'));
      expect(
        androidManifest,
        isNot(contains('ca-app-pub-6396760454728825~3261840114')),
        reason: 'that is the iOS app ID',
      );
    });
  });

  group('is in the built app, not just in the repo', () {
    late String fileRefId;

    setUpAll(() {
      final RegExp reference = RegExp(
        r'([0-9A-F]{24}) /\* PrivacyInfo\.xcprivacy \*/ = \{isa = PBXFileReference',
      );
      final RegExpMatch? match = reference.firstMatch(project);
      expect(match, isNotNull,
          reason: 'PrivacyInfo.xcprivacy is not a file in the Xcode project, '
              'so it cannot be copied into the bundle');
      fileRefId = match!.group(1)!;
    });

    test('is wrapped in a build file pointing at that reference', () {
      final RegExp buildFile = RegExp(
        '([0-9A-F]{24})'
        r' /\* PrivacyInfo\.xcprivacy in Resources \*/ = '
        r'\{isa = PBXBuildFile; fileRef = '
        '$fileRefId',
      );

      expect(buildFile.firstMatch(project), isNotNull,
          reason: 'the file is in the project but not wrapped as a build '
              'file, so no build phase can reference it');
    });

    test('that build file is listed in the Resources phase', () {
      // The step that actually matters, and the one that is silently
      // skippable. Miss it and everything above still passes.
      final RegExp buildFile = RegExp(
        '([0-9A-F]{24})'
        r' /\* PrivacyInfo\.xcprivacy in Resources \*/ = \{isa = PBXBuildFile',
      );
      final String buildFileId = buildFile.firstMatch(project)!.group(1)!;

      final RegExp resources = RegExp(
        r'isa = PBXResourcesBuildPhase;.*?files = \((.*?)\);',
        dotAll: true,
      );

      final bool listed = resources
          .allMatches(project)
          .any((RegExpMatch m) => m.group(1)!.contains(buildFileId));

      expect(listed, isTrue,
          reason: 'PrivacyInfo.xcprivacy is not in any Resources build '
              'phase, so it will not be in the shipped bundle and App Store '
              'Connect will reject the upload');
    });
  });
}
