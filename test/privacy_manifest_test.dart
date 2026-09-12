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
      // The FCM token in device_tokens.
      'NSPrivacyCollectedDataTypeDeviceID',
    ];

    for (final String type in expected) {
      test(type.replaceFirst('NSPrivacyCollectedDataType', ''), () {
        expect(manifest, contains(type));
      });
    }
  });

  test('does not claim to track', () {
    // True today: there is no ad SDK in the binary and no advertising
    // identifier is read. Adding AdMob makes it false, and docs/ADMOB.md
    // lists this file as one of the things that has to change with it — so
    // this assertion is what turns "we forgot" into a failing test.
    expect(manifest, contains('<key>NSPrivacyTracking</key>'));
    expect(
      manifest.split('<key>NSPrivacyTracking</key>')[1].trimLeft(),
      startsWith('<false/>'),
      reason: 'if an ad SDK has been added this has to become true, along '
          'with NSPrivacyTrackingDomains and the App Store privacy labels',
    );
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
