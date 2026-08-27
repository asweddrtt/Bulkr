import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The small amount of state worth remembering on the device itself.
///
/// Not a cache of the user's data — that lives in Postgres and is read fresh.
/// This is only what launch needs in order to decide where to go, before any
/// network call has happened.
///
/// The Supabase session is *not* stored here. Supabase persists that itself,
/// also in shared preferences, and restores it during `Supabase.initialize`.
/// Duplicating it would create a second copy to keep in step with the first.
class AppPreferences {
  AppPreferences({SharedPreferences? preferences}) : _injected = preferences;

  final SharedPreferences? _injected;
  SharedPreferences? _cached;

  /// Holds the id of the user known to have finished onboarding, rather than a
  /// bare boolean.
  ///
  /// Keyed by user because one device can sign in as more than one account, and
  /// a flag that outlived its owner would drop the next account straight into an
  /// app with no profile behind it.
  static const String _onboardedUserKey = 'onboarding_completed_user_id';

  Future<SharedPreferences?> _prefs() async {
    if (_injected != null) return _injected;

    try {
      return _cached ??= await SharedPreferences.getInstance();
    } catch (error) {
      // Nothing here is essential — every reader falls back to asking the
      // server — so a platform channel that is unavailable is not fatal.
      debugPrint('Bulkr: shared preferences unavailable — $error');
      return null;
    }
  }

  /// Whether [userId] is known to have finished onboarding.
  ///
  /// False means "not known", not "has not" — the caller asks the server when
  /// this is false, and only skips that round trip when it is true.
  Future<bool> hasCompletedOnboarding(String userId) async {
    final SharedPreferences? prefs = await _prefs();
    return prefs?.getString(_onboardedUserKey) == userId;
  }

  Future<void> setCompletedOnboarding(String userId) async {
    final SharedPreferences? prefs = await _prefs();
    await prefs?.setString(_onboardedUserKey, userId);
  }

  /// Called on sign-out, so the next account decides for itself.
  Future<void> clear() async {
    final SharedPreferences? prefs = await _prefs();
    await prefs?.remove(_onboardedUserKey);
  }
}
