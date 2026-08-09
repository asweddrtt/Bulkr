import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_level.dart';
import '../models/gender.dart';
import '../models/nutrition_plan.dart';
import '../models/unit_system.dart';
import '../models/user_profile.dart';
import '../models/weight_entry.dart';
import 'username_generator.dart';

/// Raised when the handle the user typed themselves is already taken. A
/// generated handle never surfaces this — the repository silently re-rolls it.
class UsernameTakenException implements Exception {
  const UsernameTakenException(this.username);

  final String username;

  @override
  String toString() => 'Username "$username" is already taken';
}

/// Writes the one row the whole onboarding flow has been building up to.
class UserRepository {
  UserRepository({SupabaseClient? client, UsernameGenerator? usernameGenerator})
      : _client = client ?? Supabase.instance.client,
        _usernames = usernameGenerator ?? UsernameGenerator();

  final SupabaseClient _client;
  final UsernameGenerator _usernames;

  /// Postgres unique-violation SQLSTATE.
  static const String _uniqueViolation = '23505';

  /// How many times to re-roll a *generated* handle before giving up.
  static const int _maxUsernameAttempts = 5;

  /// Best-effort "is this handle free?" check for the inline hint on screen 2.
  ///
  /// This is only a hint. Depending on the RLS policy on `users`, this client
  /// may not be able to see other people's rows at all, in which case every
  /// handle looks free. The authority is the unique constraint, enforced in
  /// [completeOnboarding].
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final match = await _client
          .from('users')
          .select('username')
          .eq('username', username)
          .maybeSingle();
      return match == null;
    } on PostgrestException {
      // Blocked by RLS, offline, whatever — don't block the user on a hint.
      return true;
    }
  }

  /// Reads back the signed-in user's profile row.
  ///
  /// Returns null when there's no session, or when the row doesn't exist yet —
  /// which is the normal state for an account that authenticated but abandoned
  /// onboarding before the final step.
  Future<UserProfile?> fetchProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (row == null) return null;
    return UserProfile.fromMap(row);
  }

  /// Weigh-ins, oldest first, for the progress chart.
  ///
  /// Fetched newest-first so the limit keeps the most *recent* entries, then
  /// reversed for plotting — otherwise a user with a long history would see
  /// their first 90 days forever and never the current trend.
  Future<List<WeightEntry>> fetchWeightHistory({int limit = 90}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('weight_logs')
        .select()
        .eq('user_id', userId)
        .order('logged_at', ascending: false)
        .limit(limit);

    return rows
        .map((row) => WeightEntry.fromMap(row))
        .toList()
        .reversed
        .toList();
  }

  /// Commits every field gathered across screens 1-5 as a single row, flags
  /// `onboarding_completed`, and seeds the first weight log so the progress
  /// chart has a day-one anchor instead of being empty.
  ///
  /// Returns the username actually stored, which may differ from [username]
  /// when a generated handle collided and had to be re-rolled.
  ///
  /// The weekly gain pace is intentionally absent: there is no column for it,
  /// and it exists only to derive [plan]'s calorie target.
  Future<String> completeOnboarding({
    required String userId,
    required String username,
    required bool usernameWasEdited,
    String? displayName,
    String? avatarUrl,
    required Gender gender,
    required DateTime dateOfBirth,
    required double heightCm,
    required double currentWeightKg,
    required double targetWeightKg,
    required ActivityLevel activityLevel,
    required UnitSystem units,
    required NutritionPlan plan,
  }) async {
    final activeUserId = _client.auth.currentUser?.id ?? userId;
    var candidate = username;

    for (var attempt = 0; attempt < _maxUsernameAttempts; attempt++) {
      try {
        await _client.from('users').upsert({
          'id': activeUserId,
          'username': candidate,
          'display_name': displayName,
          'avatar_url': avatarUrl,
          'gender': gender.dbValue,
          'date_of_birth': _asDate(dateOfBirth),
          'height_cm': heightCm,
          'current_weight_kg': currentWeightKg,
          'target_weight_kg': targetWeightKg,
          'activity_level': activityLevel.dbValue,
          'units': units.dbValue,
          'daily_calorie_target': plan.calories,
          'protein_target_g': plan.proteinG,
          'carbs_target_g': plan.carbsG,
          'fat_target_g': plan.fatG,
          'onboarding_completed': true,
          'last_active_at': DateTime.now().toUtc().toIso8601String(),
        });

        await _seedWeightLog(userId: activeUserId, weightKg: currentWeightKg);
        return candidate;
      } on PostgrestException catch (error) {
        final isUsernameCollision = error.code == _uniqueViolation &&
            (error.message.contains('username') ||
                (error.details?.toString().contains('username') ?? false));

        if (!isUsernameCollision) rethrow;

        // The user chose this handle deliberately — silently changing it under
        // them would be worse than telling them.
        if (usernameWasEdited) throw UsernameTakenException(candidate);

        candidate = _usernames.withSuffix(UsernameGenerator.slugify(username));
      }
    }

    throw UsernameTakenException(candidate);
  }

  /// Day-one entry in `weight_logs`.
  ///
  /// Deliberately non-fatal: the account is already created and usable at this
  /// point, and failing the whole flow over a chart data point would strand the
  /// user on screen 5 with a row that already exists.
  Future<void> _seedWeightLog({
    required String userId,
    required double weightKg,
  }) async {
    try {
      await _client.from('weight_logs').insert({
        'user_id': userId,
        'weight_kg': weightKg,
      });
    } on PostgrestException {
      return;
    }
  }

  /// `date_of_birth` is a DATE column — send it without a time component.
  static String _asDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
