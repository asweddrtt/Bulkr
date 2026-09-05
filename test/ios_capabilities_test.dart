import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The entitlements file only counts if the build reads it.
///
/// Both native sign-in paths and push all fail the same quiet way when a
/// capability is declared but not actually wired: no build error, no obvious
/// runtime message, just a feature that does nothing on a real device. The
/// `GoogleService-Info.plist` that shipped in build 4 was exactly this — right
/// file, right contents, never in the app.
void main() {
  late String entitlements;
  late String project;

  setUpAll(() {
    entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
    project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
  });

  test('every Runner build configuration reads the entitlements file', () {
    // Three: Debug, Release, Profile. A capability added to the file but
    // missing from one configuration works in testing and fails in the build
    // that ships.
    final int wired =
        RegExp(r'CODE_SIGN_ENTITLEMENTS = Runner/Runner\.entitlements;')
            .allMatches(project)
            .length;
    expect(wired, 3,
        reason: 'a configuration that does not read the entitlements file '
            'silently ships without push or Sign in with Apple');
  });

  test('Sign in with Apple is entitled', () {
    // Without this the native sheet does not appear, and the failure arrives
    // as a generic authorization error that reads like a bug in our code.
    expect(entitlements, contains('com.apple.developer.applesignin'));
    expect(entitlements, contains('<string>Default</string>'));
  });

  test('push is entitled for development', () {
    // Apple rewrites this to production when a build is processed. A build
    // signed production with this key missing gets no APNs token at all.
    expect(entitlements, contains('aps-environment'));
    expect(entitlements, contains('<string>development</string>'));
  });
}
