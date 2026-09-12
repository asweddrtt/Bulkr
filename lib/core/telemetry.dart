import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_events.dart';

/// What happened, and what people did.
///
/// Two things behind one door, because they have the same three requirements
/// and it would be two copies of the same care to keep them apart:
///
///   1. **It must never throw.** Nothing here is worth an exception in a
///      release build. Every method swallows, the same way [PushRepository]
///      does, because a failure to *report* a problem must not become one.
///   2. **It must work when Firebase is absent.** A desktop dev build has no
///      config, a unit test has no plugins, and `FirebaseCrashlytics.instance`
///      throws `[core/no-app]` in both. That is the exact failure that shipped
///      build 4 as a white screen — see `push_service_test.dart` — so nothing
///      here touches a Firebase global until [start] has proven there is one.
///   3. **It must say nothing it should not.** See [AnalyticsEvent] for the
///      rule about what may go in a parameter.
///
/// ## What this is not
///
/// Not a replacement for the `debugPrint` lines scattered through the app.
/// Those are for somebody holding the phone with a console attached; this is
/// for the nine hundred people who are not, and whose problems are otherwise
/// invisible. They record different things on purpose.
abstract final class Telemetry {
  /// Whether this platform reports crashes at all.
  ///
  /// Crashlytics ships Android, iOS and macOS. The Linux and Windows builds
  /// exist for development, and asking there logs a plugin error and achieves
  /// nothing — the same reasoning, and the same shape, as
  /// `PushService.isSupported`.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Set by [start], and the switch every method below reads.
  ///
  /// Not a getter over `Firebase.apps.isNotEmpty`: that answers "is Firebase
  /// up", and the question here is "did we successfully attach", which is a
  /// stricter thing and can be false with Firebase running perfectly.
  static bool _live = false;

  static FirebaseCrashlytics? _crashlytics;
  static FirebaseAnalytics? _analytics;

  /// Whether anything is actually being recorded. For tests and for the
  /// account screen, which offers to turn it off.
  static bool get isLive => _live;

  /// Attaches to Firebase and installs the global error handlers.
  ///
  /// Called from `main` after `Firebase.initializeApp`, and safe to call when
  /// that failed — it checks rather than assumes, and returns quietly.
  ///
  /// Handlers are installed even when Firebase is down, because
  /// [FlutterError.onError]'s default in release is to swallow the error
  /// entirely. Printing it is strictly better than that, and costs nothing.
  static Future<void> start({bool collectionEnabled = true}) async {
    _installHandlers();

    if (!isSupported || Firebase.apps.isEmpty) {
      debugPrint('Bulkr telemetry: no Firebase app, so nothing is recorded.');
      return;
    }

    try {
      _crashlytics = FirebaseCrashlytics.instance;
      _analytics = FirebaseAnalytics.instance;

      // Off in debug, always. A crash while developing is already on the
      // console in full, and sending it pollutes the release signal with
      // hot-reload noise and deliberately-broken states.
      final bool enabled = collectionEnabled && !kDebugMode;
      await _crashlytics!.setCrashlyticsCollectionEnabled(enabled);
      await _analytics!.setAnalyticsCollectionEnabled(enabled);

      _live = true;
      debugPrint('Bulkr telemetry: live (collection ${enabled ? 'on' : 'off'}).');
    } catch (error) {
      // Attaching failed. The handlers above are still installed, so errors
      // still reach the console; they just do not leave the phone.
      _live = false;
      debugPrint('Bulkr telemetry: could not attach — $error');
    }
  }

  /// Routes Flutter's two global error channels into [recordError].
  ///
  /// Both are needed and they catch different things. [FlutterError.onError]
  /// is errors inside the framework — a build method, a layout, a gesture
  /// callback. [PlatformDispatcher.onError] is everything else that reaches
  /// the root zone: an un-awaited future, a stream with no error handler.
  ///
  /// `runZonedGuarded` is deliberately *not* used. It was the old advice, it
  /// forces `runApp` inside the zone, and since Flutter 3.3 the platform
  /// dispatcher hook covers the same ground without splitting the app's zone
  /// away from the one the framework's own bindings were created in.
  static void _installHandlers() {
    final FlutterExceptionHandler? existing = FlutterError.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      // Still printed. The console is where this is read during development,
      // and losing that to gain a dashboard would be a bad trade.
      existing?.call(details);

      // `silent` is Flutter marking an error as not worth reporting — the
      // classic being an image that failed to decode. Honoured, or the
      // dashboard fills with noise nobody will act on.
      if (details.silent) return;

      unawaited(recordError(
        details.exception,
        details.stack,
        reason: details.context?.toString(),
        fatal: false,
      ));
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(recordError(error, stack, reason: 'uncaught', fatal: true));
      // True means handled. Returning false re-throws it to the platform,
      // which on iOS terminates the process — a strictly worse outcome than
      // an app that keeps running with one broken async path.
      return true;
    };
  }

  /// Records a problem.
  ///
  /// [fatal] separates "the app died" from "something went wrong and the app
  /// carried on", which is the axis the Crashlytics dashboard sorts by. A
  /// failed network call is not fatal; an uncaught error in the root zone is.
  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    if (!_live || _crashlytics == null) return;

    try {
      await _crashlytics!.recordError(
        error,
        stack,
        reason: reason,
        fatal: fatal,
      );
    } catch (failure) {
      debugPrint('Bulkr telemetry: could not record an error — $failure');
    }
  }

  /// A line in the log that ships alongside the next crash.
  ///
  /// Crashlytics keeps the last 64KB per session. What this is for is the
  /// sequence — "opened composer, picked image, scored image, uploaded" — so
  /// a stack trace arrives with the story of how it got there.
  static void breadcrumb(String message) {
    if (!_live || _crashlytics == null) return;

    try {
      _crashlytics!.log(message);
    } catch (_) {
      // Deliberately silent. A breadcrumb that cannot be written is not worth
      // a line of its own about not being written.
    }
  }

  /// Records something the user did.
  static Future<void> send(AnalyticsEvent event) async {
    if (!_live || _analytics == null) return;

    // Also a breadcrumb, so a crash report carries the last few actions that
    // led to it. This is most of why the two live in one class.
    breadcrumb(event.toString());

    try {
      await _analytics!.logEvent(
        name: event.name,
        parameters: event.firebaseParameters,
      );
    } catch (failure) {
      debugPrint('Bulkr telemetry: could not send ${event.name} — $failure');
    }
  }

  /// Ties reports to an account, so one person's repeated crash is visible as
  /// one person's repeated crash.
  ///
  /// The Supabase user id and nothing else — never an email, a handle or a
  /// display name. It is already a random UUID, it is meaningless outside our
  /// own database, and it is the only identifier that makes a report
  /// actionable without making it personal.
  static Future<void> identify(String? userId) async {
    if (!_live) return;

    try {
      await _crashlytics?.setUserIdentifier(userId ?? '');
      await _analytics?.setUserId(id: userId);
    } catch (failure) {
      debugPrint('Bulkr telemetry: could not set the user — $failure');
    }
  }

  /// Which screen is in front of the user, for crash reports and funnels.
  static Future<void> screen(String name) async {
    if (!_live) return;

    breadcrumb('screen: $name');

    try {
      await _analytics?.logScreenView(screenName: name);
    } catch (failure) {
      debugPrint('Bulkr telemetry: could not log a screen — $failure');
    }
  }

  /// Turns collection off, or back on, for this install.
  ///
  /// Persisted by both SDKs across launches, so this is the whole of the
  /// opt-out — there is nothing for the app to remember.
  static Future<void> setCollectionEnabled(bool enabled) async {
    try {
      await _crashlytics?.setCrashlyticsCollectionEnabled(enabled);
      await _analytics?.setAnalyticsCollectionEnabled(enabled);
      debugPrint('Bulkr telemetry: collection ${enabled ? 'on' : 'off'}.');
    } catch (failure) {
      debugPrint('Bulkr telemetry: could not change collection — $failure');
    }
  }

  /// Drops everything attached. For tests only.
  @visibleForTesting
  static void resetForTest() {
    _live = false;
    _crashlytics = null;
    _analytics = null;
  }
}
