import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_repository.dart';

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
        _messaging = messaging ?? FirebaseMessaging.instance;

  final PushRepository _repository;
  final FirebaseMessaging _messaging;

  /// The token this device most recently registered.
  ///
  /// Held so [signOut] can remove the right row without asking the plugin
  /// again — by then the session may already be gone, and on iOS the token can
  /// come back null once notifications are no longer authorised.
  String? _token;

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
    if (!isSupported) return;

    try {
      final NotificationSettings settings = await _messaging.requestPermission();

      // `provisional` is iOS's quiet authorisation — delivered silently to the
      // notification centre without a prompt. It counts: the point is being
      // able to send, and the user can promote it to full at any time.
      final bool allowed = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!allowed) return;

      final String? token = await _messaging.getToken();
      if (token == null) return;

      _token = token;
      await _repository.register(token: token, platform: _platform);

      // FCM rotates tokens — on reinstall, on restore to a new device, and
      // occasionally on its own. Registering only at sign-in would leave a
      // stale row behind, and a stale row is a phone that silently stops being
      // notified with nothing to show for it.
      _messaging.onTokenRefresh.listen((String refreshed) {
        _token = refreshed;
        _repository.register(token: refreshed, platform: _platform);
      });
    } catch (error) {
      debugPrint('Bulkr: push registration failed — $error');
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

    if (token == null) return;

    try {
      await _repository.unregister(token);
    } catch (error) {
      debugPrint('Bulkr: push token not removed — $error');
    }
  }

  static String get _platform => Platform.isIOS ? 'ios' : 'android';
}
