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

  // --- Search history -----------------------------------------------------

  /// Terms the user has searched for, newest first.
  ///
  /// On the device rather than in a table, deliberately. What someone typed
  /// into a search box is a record of who they were curious about, and there
  /// is no feature here that needs it to follow them between devices — so the
  /// cheapest place to keep it is also the most private one, and clearing it
  /// means clearing it rather than deleting rows somebody could have read.
  static const String _searchHistoryKey = 'search_history';

  /// How many terms are kept. Enough to cover "the thing I looked at
  /// yesterday" and short enough to stay a list rather than an archive.
  static const int maxSearchHistory = 8;

  Future<List<String>> searchHistory() async {
    final SharedPreferences? prefs = await _prefs();
    return prefs?.getStringList(_searchHistoryKey) ?? const <String>[];
  }

  /// Puts [term] at the top, removing any earlier copy of it.
  ///
  /// Case-insensitive on the way in, so searching "Sara" after "sara" moves
  /// the one entry rather than making a second.
  Future<List<String>> rememberSearch(String term) async {
    final String trimmed = term.trim();
    if (trimmed.isEmpty) return searchHistory();

    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return const <String>[];

    final List<String> existing =
        prefs.getStringList(_searchHistoryKey) ?? <String>[];

    final List<String> updated = [
      trimmed,
      ...existing.where(
        (entry) => entry.toLowerCase() != trimmed.toLowerCase(),
      ),
    ].take(maxSearchHistory).toList();

    await prefs.setStringList(_searchHistoryKey, updated);
    return updated;
  }

  /// Removes one term — the x on a row.
  Future<List<String>> forgetSearch(String term) async {
    final SharedPreferences? prefs = await _prefs();
    if (prefs == null) return const <String>[];

    final List<String> updated =
        (prefs.getStringList(_searchHistoryKey) ?? <String>[])
            .where((entry) => entry != term)
            .toList();

    await prefs.setStringList(_searchHistoryKey, updated);
    return updated;
  }

  Future<void> clearSearchHistory() async {
    final SharedPreferences? prefs = await _prefs();
    await prefs?.remove(_searchHistoryKey);
  }

  /// Called on sign-out, so the next account decides for itself.
  ///
  /// Takes the search history with it. The next person to sign in on this
  /// device should not be looking at what the last one searched for.
  Future<void> clear() async {
    final SharedPreferences? prefs = await _prefs();
    await prefs?.remove(_onboardedUserKey);
    await prefs?.remove(_searchHistoryKey);
  }
}
