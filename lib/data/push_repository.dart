import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where this user's push notifications should go.
///
/// Takes a token string and knows nothing about where it came from — no
/// Firebase import, no plugin, no platform channel. That is deliberate: the
/// app cannot depend on `firebase_messaging` until there is a
/// `google-services.json` to go with it, because the Android Gradle plugin
/// fails the build outright without one. This is the seam that lets everything
/// else be finished and tested in the meantime.
///
/// See `supabase/functions/send-push/README.md` for what plugs into it.
class PushRepository {
  PushRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get _userId => _client.auth.currentUser?.id;

  /// Records that this device should receive notifications for this user.
  ///
  /// An upsert on the token rather than an insert, and that is load-bearing:
  /// FCM hands the same token to whoever installs the app on a given device,
  /// so when two people share a phone the second sign-in has to *take the
  /// token over*. Inserting beside the existing row would leave the first
  /// person receiving the second person's notifications — a privacy bug
  /// wearing a delivery bug's clothes.
  ///
  /// Never throws. Push is an enhancement; an app that refused to finish
  /// signing in because a token would not register would be trading something
  /// that matters for something that does not.
  Future<void> register({required String token, String? platform}) async {
    final String? userId = _userId;
    if (userId == null || token.isEmpty) return;

    try {
      await _client.from('device_tokens').upsert(
        {
          'token': token,
          'user_id': userId,
          'platform': platform,
          // Bumped on every registration, which is every app start. What tells
          // a live device from one uninstalled a year ago.
          'last_seen_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );
      debugPrint('Bulkr push: device_tokens row written.');
    } catch (error) {
      // A PostgrestException here is the interesting case: 42501 means
      // push_devices.sql has not been run, or its policies did not take.
      debugPrint('Bulkr push: device_tokens write failed — $error');
    }
  }

  /// Forgets this device.
  ///
  /// Called on sign-out, and it matters more than it looks: the token belongs
  /// to the phone rather than to the account, so leaving it behind means the
  /// next person to sign in here receives the last person's notifications
  /// until they happen to register their own.
  Future<void> unregister(String token) async {
    if (token.isEmpty) return;

    try {
      await _client.from('device_tokens').delete().eq('token', token);
    } catch (error) {
      debugPrint('Bulkr: push token not removed — $error');
    }
  }
}
