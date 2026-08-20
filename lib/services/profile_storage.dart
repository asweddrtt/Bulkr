import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_profile.dart';

/// Persists the signed-in athlete's profile on the device.
class ProfileStorage {
  static const String _key = 'bulkr.user_profile.v1';

  const ProfileStorage();

  Future<UserProfile?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_key);
    if (raw == null) return null;

    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A profile written by an incompatible build is dropped rather than
      // blocking start-up; the athlete signs in again.
      await prefs.remove(_key);
      return null;
    }
  }

  Future<void> save(UserProfile profile) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(profile.toJson()));
  }

  Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
