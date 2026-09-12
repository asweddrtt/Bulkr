import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/analytics_events.dart';
import '../core/telemetry.dart';
import 'push_repository.dart';

/// A notification the user tapped.
///
/// Parsed out of the `data` map `send-push` attaches, and kept a plain value
/// so the parsing can be tested — none of the rest of this file can be, since
/// permission dialogs and platform channels do not run in a unit test, and the
/// part that decides where a tap goes should not be trapped behind them.
@immutable
class PushTap {
  const PushTap({required this.kind, this.conversationId, this.notificationId});

  /// `message` or `notification`. Not an enum: it arrives as a string from a
  /// server that may be a version ahead of this app, and an unrecognised kind
  /// should land somewhere sensible rather than crash.
  final String kind;

  /// The thread to open, for a direct message.
  final String? conversationId;

  /// The row to highlight, for anything in the notifications inbox.
  final String? notificationId;

  /// Whether this is a message rather than feed activity.
  bool get isMessage => kind == 'message';

  /// Null when there is nothing here worth acting on.
  ///
  /// A tap with no usable data still opens the app — that is iOS's doing, not
  /// ours — and returning null lets the caller leave the user where they were
  /// instead of navigating somewhere arbitrary.
  static PushTap? fromData(Map<String, dynamic> data) {
    String? text(String key) {
      final Object? value = data[key];
      if (value is! String) return null;
      final String trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final String? conversationId = text('conversation_id');
    final String? notificationId = text('notification_id');
    final String? kind = text('kind');

    if (kind == null && conversationId == null && notificationId == null) {
      return null;
    }

    return PushTap(
      // Inferred from what is present when the server did not say. Builds of
      // the function predating the `kind` field sent one identifier and no
      // label, and their notifications are still in people's trays.
      kind: kind ?? (conversationId != null ? 'message' : 'notification'),
      conversationId: conversationId,
      notificationId: notificationId,
    );
  }
}

/// Firebase Cloud Messaging, and nothing else.
///
/// Split from [PushRepository] on purpose. That one writes a token to a table
/// and has no idea where tokens come from; this one talks to the plugin and
/// has no idea what a `device_tokens` row is. The seam is a string.
///
/// It matters because half of this is untestable — permission dialogs and
/// platform channels do not run in a unit test — and the half that decides
/// what gets stored should not be trapped behind them.
class PushService {
  PushService({required PushRepository repository, FirebaseMessaging? messaging})
      : _repository = repository,
        _injected = messaging;

  final PushRepository _repository;
  final FirebaseMessaging? _injected;

  /// Resolved on first use, never in the constructor.
  ///
  /// `FirebaseMessaging.instance` throws `[core/no-app]` when
  /// `Firebase.initializeApp()` has not run — which is exactly what happens on
  /// a build with no `GoogleService-Info.plist` in the bundle. Touching it from
  /// the initialiser list meant merely *constructing* this class threw, inside
  /// the first `initState`, before the first frame was ever produced: a white
  /// screen with no error, on a feature nobody was using yet.
  ///
  /// Push is optional. Constructing the thing that does it must be free.
  late final FirebaseMessaging _messaging = _injected ?? FirebaseMessaging.instance;

  /// The token this device most recently registered.
  ///
  /// Held so [signOut] can remove the right row without asking the plugin
  /// again — by then the session may already be gone, and on iOS the token can
  /// come back null once notifications are no longer authorised.
  String? _token;

  /// The live subscription to FCM's token rotation, if there is one.
  ///
  /// Held so there is never more than one. [signIn] runs whenever the shell
  /// mounts, and the shell remounts on every sign-in — so a sign-out followed
  /// by a sign-in used to leave the first subscription running and add a
  /// second beside it. Every rotation then wrote the same row once per
  /// listener, and the count grew for as long as the process lived.
  StreamSubscription<String>? _tokenRefresh;

  /// Whether this platform can receive a push at all.
  ///
  /// Desktop and web builds of this app exist for development; FCM is set up
  /// for the two that ship. Asking on the others logs a plugin error and
  /// achieves nothing.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  /// Asks for permission, and registers this device if it is given.
  ///
  /// Called once the user is signed in and looking at the app, never at
  /// launch. A permission prompt on first open, before anyone has seen what
  /// the app is, is the one most reliably denied — and on iOS a denial is
  /// close to permanent, since re-asking is not possible from inside the app.
  ///
  /// Never throws. Push is an enhancement; a phone that cannot register is a
  /// phone that misses notifications, not one that cannot use the app.
  Future<void> signIn() async {
    if (!isSupported) {
      debugPrint('Bulkr push: platform does not do notifications, skipping.');
      return;
    }

    // Asked before touching the plugin so the log says which of the two things
    // went wrong. Without this the symptom is `[core/no-app]` thrown from a
    // getter, which reads like a plugin bug rather than what it is: no
    // `google-services.json` / `GoogleService-Info.plist` in the bundle.
    if (Firebase.apps.isEmpty) {
      debugPrint(
        'Bulkr push: Firebase never initialised, so there is nothing to '
        'register with. Check that the config file for this platform is in '
        'the built app, not just in the repo.',
      );
      return;
    }

    try {
      final NotificationSettings settings = await _messaging.requestPermission();

      // Logged at every step, deliberately. This runs once, on a real device,
      // and when it does nothing there is no screen that says so — "I did not
      // get a prompt" has at least five causes and they are indistinguishable
      // without this.
      debugPrint('Bulkr push: permission ${settings.authorizationStatus}.');
      // Counted, because the denial rate is the number that decides whether
      // this prompt is being asked at the right moment — and on iOS a denial
      // is close to permanent, so getting it wrong is not recoverable per
      // user.
      unawaited(Telemetry.send(AnalyticsEvent.pushPermission(
        status: settings.authorizationStatus.name,
      )));

      // `provisional` is iOS's quiet authorisation — delivered silently to the
      // notification centre without a prompt. It counts: the point is being
      // able to send, and the user can promote it to full at any time.
      final bool allowed = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!allowed) {
        debugPrint(
          'Bulkr push: not authorised, so no token. On Android 13+ this is the '
          'system prompt being declined; below that there is no prompt and this '
          'should not happen.',
        );
        return;
      }

      final String? token = await _messaging.getToken();
      if (token == null) {
        // On Android this usually means the google-services.json belongs to a
        // different application id. On iOS it means APNs has not handed one
        // over — no APNs key uploaded to Firebase, or no Push Notifications
        // capability on the target.
        debugPrint('Bulkr push: FCM returned no token.');
        return;
      }

      debugPrint('Bulkr push: token ${token.substring(0, 12)}..., registering.');

      _token = token;
      await _repository.register(token: token, platform: _platform);
      debugPrint('Bulkr push: registered for $_platform.');
      unawaited(
        Telemetry.send(AnalyticsEvent.pushRegistered(platform: _platform)),
      );

      // FCM rotates tokens — on reinstall, on restore to a new device, and
      // occasionally on its own. Registering only at sign-in would leave a
      // stale row behind, and a stale row is a phone that silently stops being
      // notified with nothing to show for it.
      //
      // Cancelled before resubscribing rather than simply added to: see
      // [_tokenRefresh].
      await _tokenRefresh?.cancel();
      _tokenRefresh = _messaging.onTokenRefresh.listen((String refreshed) {
        _token = refreshed;
        _repository.register(token: refreshed, platform: _platform);
      });
    } catch (error) {
      debugPrint('Bulkr push: registration failed — $error');
    }
  }

  /// Notifications tapped while the app was running in the background.
  ///
  /// Empty rather than throwing when Firebase never initialised: a listener
  /// that has to ask whether push exists before subscribing is a listener
  /// every caller gets wrong once.
  Stream<PushTap> get taps {
    if (!isSupported || Firebase.apps.isEmpty) {
      return const Stream<PushTap>.empty();
    }

    try {
      // Static on the plugin, not per-instance — so unlike the rest of this
      // class it cannot be pointed at an injected fake.
      return FirebaseMessaging.onMessageOpenedApp
          .map((RemoteMessage message) => PushTap.fromData(message.data))
          .where((PushTap? tap) => tap != null)
          .cast<PushTap>();
    } catch (error) {
      debugPrint('Bulkr push: tap stream unavailable — $error');
      return const Stream<PushTap>.empty();
    }
  }

  bool _initialTapTaken = false;

  /// The notification that launched the app from cold, if one did.
  ///
  /// Answers once. The plugin will hand the same message back on a second ask,
  /// and two answers means the thread opens twice — one screen stacked on an
  /// identical screen, with a back gesture that appears not to work.
  Future<PushTap?> takeInitialTap() async {
    if (_initialTapTaken || !isSupported || Firebase.apps.isEmpty) return null;
    _initialTapTaken = true;

    try {
      final RemoteMessage? message = await _messaging.getInitialMessage();
      return message == null ? null : PushTap.fromData(message.data);
    } catch (error) {
      debugPrint('Bulkr push: launch notification unavailable — $error');
      return null;
    }
  }

  /// Forgets this device, before the session goes.
  ///
  /// The token belongs to the phone rather than to the account. Leaving it
  /// behind means the next person to sign in here receives the last person's
  /// notifications until they happen to register their own — which is why this
  /// runs on the way out rather than being left to the next sign-in to
  /// overwrite.
  Future<void> signOut() async {
    final String? token = _token;
    _token = null;

    // Stopped here as well as re-established in [signIn]. A rotation arriving
    // after sign-out has nobody to belong to, and re-registering the phone is
    // the exact thing this method exists to undo.
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;

    if (token == null) return;

    try {
      await _repository.unregister(token);
    } catch (error) {
      debugPrint('Bulkr: push token not removed — $error');
    }
  }

  static String get _platform => Platform.isIOS ? 'ios' : 'android';
}
