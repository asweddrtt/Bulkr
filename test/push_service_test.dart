import 'dart:io';

import 'package:bulkr/data/push_repository.dart';
import 'package:bulkr/data/push_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two halves of one crash.
///
/// Build 4 launched to a permanently white screen on TestFlight. The device
/// log said why: `GoogleService-Info.plist` was committed to the repo but
/// never added to the Xcode target, so `Firebase.initializeApp()` failed;
/// `main()` caught that and carried on, exactly as intended — and then
/// `PushService`'s constructor read `FirebaseMessaging.instance`, which throws
/// `[core/no-app]` when no app was configured. It ran inside the first
/// `initState`, so the throw happened *during the first build pass* and no
/// frame was ever produced. No crash, no error screen: white.
///
/// So there are two invariants worth holding onto, and each guards one half.
void main() {
  group('constructing PushService is free', () {
    // A throwaway client rather than `Supabase.instance` — nothing here makes
    // a request, and the point is that no part of this construction reaches
    // for a global that might not exist.
    PushRepository repository() => PushRepository(
          client: SupabaseClient('https://example.supabase.co', 'anon-key'),
        );

    test('does not touch Firebase', () {
      // The regression itself. Firebase is not initialised in a unit test, so
      // before the fix this line threw `[core/no-app]`.
      expect(() => PushService(repository: repository()), returnsNormally);
    });

    test('signing in without Firebase does not throw either', () async {
      // Push is an enhancement. A phone that cannot register is a phone that
      // misses notifications, never one that cannot use the app.
      await expectLater(
        PushService(repository: repository()).signIn(),
        completes,
      );
    });
  });

  group('the Firebase config files are in the built app', () {
    test('iOS ships GoogleService-Info.plist as a bundle resource', () {
      final File plist = File('ios/Runner/GoogleService-Info.plist');
      expect(plist.existsSync(), isTrue,
          reason: 'the iOS Firebase config has moved');

      final String project =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

      // Being in the folder is not being in the app. The file has to be a
      // PBXFileReference, wrapped in a PBXBuildFile, listed in the Runner
      // target's Resources phase — miss the last step and the build is green,
      // the repo looks right, and the shipped bundle has no config in it.
      final RegExp fileRef = RegExp(
        r'([0-9A-F]{24}) /\* GoogleService-Info\.plist \*/ = \{isa = PBXFileReference',
      );
      final RegExpMatch? reference = fileRef.firstMatch(project);
      expect(reference, isNotNull,
          reason: 'GoogleService-Info.plist is not a file in the Xcode '
              'project, so it cannot be copied into the bundle');

      const String tail =
          r' /\* GoogleService-Info\.plist in Resources \*/ = '
          r'\{isa = PBXBuildFile; fileRef = ';
      final RegExp buildFile =
          RegExp('([0-9A-F]{24})$tail${reference!.group(1)}');
      final RegExpMatch? build = buildFile.firstMatch(project);
      expect(build, isNotNull,
          reason: 'the file reference is not wrapped in a build file');

      final String resources = project.split('/* Begin PBXResourcesBuildPhase '
          'section */')[1];
      expect(
        resources.contains('${build!.group(1)} /* GoogleService-Info.plist'),
        isTrue,
        reason: 'the build file is not in a Resources build phase, so the '
            'plist never reaches the app and Firebase cannot configure',
      );
    });

    test('Android ships google-services.json', () {
      expect(File('android/app/google-services.json').existsSync(), isTrue,
          reason: 'the Gradle plugin fails the build without it');
    });
  });

  group('PushTap.fromData decides where a tap lands', () {
    // The `data` map send-push attaches. Getting this wrong does not crash
    // anything — it just drops the user on the wrong screen after they took
    // the trouble to tap, which is the sort of bug nobody reports.
    test('a message carries its thread', () {
      final PushTap? tap = PushTap.fromData(<String, dynamic>{
        'kind': 'message',
        'conversation_id': 'c-1',
      });

      expect(tap, isNotNull);
      expect(tap!.isMessage, isTrue);
      expect(tap.conversationId, 'c-1');
    });

    test('feed activity carries its notification', () {
      final PushTap? tap = PushTap.fromData(<String, dynamic>{
        'kind': 'notification',
        'notification_id': 'n-1',
      });

      expect(tap!.isMessage, isFalse);
      expect(tap.notificationId, 'n-1');
    });

    test('a payload with no kind is read from what it does carry', () {
      // Builds of the function before `kind` existed sent one identifier and
      // no label, and their notifications are still sitting in trays.
      expect(
        PushTap.fromData(<String, dynamic>{'conversation_id': 'c-9'})!.isMessage,
        isTrue,
      );
      expect(
        PushTap.fromData(<String, dynamic>{'notification_id': 'n-9'})!.isMessage,
        isFalse,
      );
    });

    test('an empty string is not an id', () {
      // FCM data values are always strings, so an absent conversation arrives
      // as "" rather than as null — and "" would send the app looking for a
      // thread that cannot exist.
      final PushTap? tap = PushTap.fromData(<String, dynamic>{
        'kind': 'message',
        'conversation_id': '   ',
      });

      expect(tap, isNotNull);
      expect(tap!.isMessage, isTrue);
      expect(tap.conversationId, isNull,
          reason: 'the caller opens the inbox on a null, and would otherwise '
              'query for a blank id');
    });

    test('nothing usable returns null rather than a default', () {
      // A tap with no data still opens the app; that is iOS, not us. Null lets
      // the caller leave the user where they were instead of navigating
      // somewhere arbitrary.
      expect(PushTap.fromData(<String, dynamic>{}), isNull);
      expect(PushTap.fromData(<String, dynamic>{'other': 'thing'}), isNull);
      expect(PushTap.fromData(<String, dynamic>{'kind': ''}), isNull);
    });

    test('a non-string value is ignored rather than crashing', () {
      // The map is typed dynamic. A server sending a number here should be a
      // missing id, not an exception on the launch path.
      final PushTap? tap = PushTap.fromData(<String, dynamic>{
        'kind': 'message',
        'conversation_id': 42,
      });

      expect(tap!.conversationId, isNull);
    });

    test('an unknown kind is treated as feed activity', () {
      // A server a version ahead of this app. Anything that is not a message
      // belongs in the notifications inbox, which is where everything else
      // lives.
      final PushTap? tap = PushTap.fromData(<String, dynamic>{
        'kind': 'something_new',
        'notification_id': 'n-2',
      });

      expect(tap!.isMessage, isFalse);
    });
  });
}
