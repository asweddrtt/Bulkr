import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/activity_level.dart';
import '../models/gender.dart';
import '../models/nutrition_plan.dart';
import '../models/unit_system.dart';
import '../models/user_profile.dart';
import '../models/water_entry.dart';
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

  /// The signed-in user's id, or null when there is no session.
  ///
  /// Exposed because callers that hold onto a user id of their own — the
  /// onboarding flow keeps one in cubit state across five screens — need a way
  /// to fall back to the live session when theirs is missing.
  String? get currentUserId => _client.auth.currentUser?.id;

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

  /// Weigh-ins, oldest first, for the progress chart — at most one per day.
  ///
  /// Fetched newest-first so the limit keeps the most *recent* rows, then
  /// collapsed to the last weigh-in of each calendar day and sorted for
  /// plotting — otherwise a user with a long history would see their first 90
  /// days forever and never the current trend.
  ///
  /// [logWeight] already keeps one row per day going forward; the collapse here
  /// is what makes rows written before that rule — a re-run onboarding seed, a
  /// day someone logged four times — read as a single point too. [limit] caps
  /// rows read, so a history full of such duplicates yields fewer than [limit]
  /// days.
  Future<List<WeightEntry>> fetchWeightHistory({int limit = 90}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('weight_logs')
        .select()
        .eq('user_id', userId)
        .order('logged_at', ascending: false)
        .limit(limit);

    return WeightEntry.latestPerDay(rows.map(WeightEntry.fromMap));
  }

  /// Records today's weigh-in and moves the profile's current weight with it.
  ///
  /// Logging again on the same day overrides the earlier figure rather than
  /// stacking a second point on the chart: a day has one weight, and the last
  /// number the user entered is the one they meant. They can re-log as often as
  /// they like — only the final value for the day survives.
  ///
  /// Two writes, deliberately in this order: the log row is the historical
  /// record and the one the chart reads, so it lands first. If the profile
  /// update then fails, the user sees a stale headline number over a correct
  /// chart, which is recoverable — the reverse would silently lose the
  /// measurement.
  Future<void> logWeight({required double weightKg}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _writeDailyWeightLog(userId: userId, weightKg: weightKg);

    await _client.from('users').update({
      'current_weight_kg': weightKg,
      'last_active_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  /// Writes one weigh-in and clears whatever the same local day already held.
  ///
  /// Insert first, then delete the superseded rows — never the other way
  /// round. A failure between the two leaves a duplicate for the day, which
  /// [fetchWeightHistory] collapses to the newest row anyway; deleting first
  /// would leave a failed insert with no measurement at all for the day.
  ///
  /// `logged_at` is sent explicitly rather than left to the column default so
  /// the row's timestamp is the same clock the day boundary below is measured
  /// against.
  Future<void> _writeDailyWeightLog({
    required String userId,
    required double weightKg,
  }) async {
    final DateTime loggedAt = DateTime.now();
    final DateTime startOfDay =
        DateTime(loggedAt.year, loggedAt.month, loggedAt.day);
    final String stamp = loggedAt.toUtc().toIso8601String();

    await _client.from('weight_logs').insert({
      'user_id': userId,
      'weight_kg': weightKg,
      'logged_at': stamp,
    });

    // Bounded on both sides: only this user's own earlier rows from today, and
    // never the row just written.
    await _client
        .from('weight_logs')
        .delete()
        .eq('user_id', userId)
        .gte('logged_at', startOfDay.toUtc().toIso8601String())
        .lt('logged_at', stamp);
  }

  /// Moves the goalpost. Does not touch the calorie target: the target follows
  /// from the pace, not from how far away the goal is.
  Future<void> updateTargetWeight({required double targetWeightKg}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('users').update({
      'target_weight_kg': targetWeightKg,
    }).eq('id', userId);
  }

  // --- Water --------------------------------------------------------------

  /// Every drink recorded on [day], in the order they were drunk.
  ///
  /// The whole day rather than a `sum(ml)`, because the tracker needs both the
  /// total and the ability to take the last one back — and one query that
  /// answers both beats two that each answer half.
  Future<List<WaterEntry>> fetchWaterDay(DateTime day) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <WaterEntry>[];

    final rows = await _client
        .from('water_logs')
        .select()
        .eq('user_id', userId)
        .eq('log_date', _asDate(day))
        .order('logged_at', ascending: true);

    return rows.map(WaterEntry.fromRow).toList();
  }

  /// Records a drink of [millilitres] against [day].
  ///
  /// `log_date` is sent as the local day rather than left to a server default,
  /// for the reason `tracker_water.sql` gives: a default would put the day
  /// boundary at UTC midnight, which is the wrong midnight for everyone not on
  /// it. `logged_at` is sent for the same reason — it is the clock the rows are
  /// ordered by, and it should be the same clock the date came from.
  Future<void> logWater({required int millilitres, DateTime? day}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || millilitres <= 0) return;

    final DateTime when = day ?? DateTime.now();

    await _client.from('water_logs').insert({
      'user_id': userId,
      'log_date': _asDate(when),
      'ml': millilitres,
      'logged_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Removes one recorded drink.
  ///
  /// Scoped to the signed-in user as well as the id. Redundant against the RLS
  /// policy, and worth it: a stale id deletes nothing rather than erroring.
  Future<void> deleteWaterEntry(WaterEntry entry) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client
        .from('water_logs')
        .delete()
        .eq('id', entry.id)
        .eq('user_id', userId);
  }

  /// Sets or clears the daily water goal.
  ///
  /// Null clears it, and clearing is not the same as setting zero: with no
  /// stored value the goal goes back to being derived from bodyweight, which
  /// is the normal state and the one that keeps moving as the user bulks. That
  /// is the whole reason the column is nullable — see section 3 of
  /// `tracker_water.sql`.
  Future<void> updateWaterTarget({int? millilitres}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('users').update({
      'water_target_ml': millilitres,
    }).eq('id', userId);
  }

  // --- Leaving --------------------------------------------------------------

  /// The edge function that deletes an account.
  ///
  /// It has to be a function: `auth.users` is not reachable through PostgREST,
  /// and deleting a row there needs the service role — a key that must never
  /// be inside the app, since an `.apk` is a zip. See
  /// `supabase/functions/delete-account/README.md`.
  static const String deleteAccountFunction = 'delete-account';

  /// Deletes the signed-in account and everything belonging to it.
  ///
  /// Takes no user id, and that is the security model rather than an omission:
  /// the function reads the caller from their own verified JWT, so there is no
  /// parameter that could make this "delete any account you can name".
  ///
  /// Throws on failure, so the caller can say so rather than signing someone
  /// out of an account that still exists. Returns only once the account is
  /// actually gone.
  Future<void> deleteAccount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot delete an account without a signed-in user');
    }

    final FunctionResponse response = await _client.functions.invoke(
      deleteAccountFunction,
      method: HttpMethod.post,
    );

    // `invoke` does not throw on a non-2xx by itself, so the status is checked
    // here — otherwise a 500 would read as a successful deletion and the app
    // would sign the user out of an account that is still there.
    if (response.status >= 200 && response.status < 300) return;

    final Object? data = response.data;
    final String detail = data is Map && data['detail'] != null
        ? '${data['detail']}'
        : data is Map && data['error'] != null
            ? '${data['error']}'
            : 'HTTP ${response.status}';

    debugPrint('Bulkr: account deletion failed — $detail');
    throw Exception(detail);
  }

  /// Writes the two things a person says about themselves.
  ///
  /// The only columns on `users` a profile screen edits. Everything else on
  /// that row is a number the calorie engine derives things from, and belongs
  /// to the dashboard's own flows — changing a target weight recalculates a
  /// plan, and doing that from a bio field would be a surprise.
  ///
  /// A blank display name clears it rather than storing `''`, so
  /// [UserProfile.preferredName] falls back to the handle the way it does for
  /// someone who never set one. Same for the bio, so "has no about" is one
  /// value in the database instead of two.
  Future<void> updateProfile({
    String? displayName,
    String? bio,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final String? name = displayName?.trim();
    final String? about = bio?.trim();

    await _client.from('users').update({
      // Only the fields the caller passed. A null argument means "leave it
      // alone"; an empty string means "clear it", and those are different
      // instructions that would otherwise both arrive as null.
      if (displayName != null)
        'display_name': (name == null || name.isEmpty) ? null : name,
      if (bio != null) 'bio': (about == null || about.isEmpty) ? null : about,
    }).eq('id', userId);
  }

  /// Storage bucket holding profile pictures. Public-read, because an avatar
  /// appears next to every post its owner has written.
  static const String avatarBucket = 'avatars';

  /// Uploads a new profile picture and points `avatar_url` at it.
  ///
  /// Returns the stored URL, so the caller can show the new picture without
  /// refetching the row.
  ///
  /// A new filename every time, rather than one file per user overwritten in
  /// place. That is not arbitrary: a public storage URL is cached, and that URL
  /// is embedded in every post card this user appears on — so overwriting the
  /// object leaves the URL unchanged and every device that already loaded it
  /// keeps showing the old picture, which to the person who just changed theirs
  /// is indistinguishable from the change not saving.
  ///
  /// The previous file is left behind. Deleting it means parsing a storage path
  /// back out of the old URL and deleting that, three steps that can each fail,
  /// in service of a few kilobytes — and a failure there would block someone
  /// changing their picture. `supabase/feed_avatars.sql` section 2 says where
  /// the tidy-up belongs instead.
  Future<String> updateAvatar({
    required Uint8List bytes,
    String extension = 'jpg',
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot change the avatar without a signed-in user');
    }

    final String path =
        '$userId/${DateTime.now().toUtc().microsecondsSinceEpoch}.$extension';

    await _client.storage.from(avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _avatarContentType(extension),
            upsert: false,
          ),
        );

    final String url = _client.storage.from(avatarBucket).getPublicUrl(path);

    // The row is written after the upload, so a failed upload leaves the old
    // picture in place rather than pointing the column at nothing.
    await _client.from('users').update({'avatar_url': url}).eq('id', userId);

    return url;
  }

  /// Drops the profile picture, falling back to the initial.
  ///
  /// Does not restore whatever the OAuth provider supplied at sign-up: that
  /// URL is not kept anywhere once it has been overwritten, and inventing a way
  /// to get it back would mean storing two avatars to support an action nobody
  /// asked for.
  Future<void> clearAvatar() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('users').update({'avatar_url': null}).eq('id', userId);
  }

  static String _avatarContentType(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Writes a freshly calculated plan over the stored targets.
  Future<void> applyPlan({required NutritionPlan plan}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('users').update({
      'daily_calorie_target': plan.calories,
      'protein_target_g': plan.proteinG,
      'carbs_target_g': plan.carbsG,
      'fat_target_g': plan.fatG,
    }).eq('id', userId);
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

    // If a row already exists and the user did not type a handle themselves,
    // keep the one they already have: re-running this flow should update an
    // account, never rename it.
    if (!usernameWasEdited) {
      try {
        final existing = await fetchProfile();
        if (existing != null && existing.username.isNotEmpty) {
          candidate = existing.username;
        }
      } catch (_) {
        // Best effort — a failed read just means the generated handle stands.
      }
    }

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
  /// Goes through the same day-scoped write as [logWeight], so an account that
  /// re-runs onboarding replaces today's seed instead of adding a second one
  /// beside it.
  ///
  /// Deliberately non-fatal: the account is already created and usable at this
  /// point, and failing the whole flow over a chart data point would strand the
  /// user on screen 5 with a row that already exists.
  Future<void> _seedWeightLog({
    required String userId,
    required double weightKg,
  }) async {
    try {
      await _writeDailyWeightLog(userId: userId, weightKg: weightKg);
    } on PostgrestException catch (error) {
      // Still non-fatal, but no longer invisible: a rejected seed row is the
      // difference between "no weigh-ins yet" and "weight_logs cannot be
      // written to", and those look identical on the chart.
      debugPrint(
        'Bulkr: weight_logs seed rejected — ${error.code} · ${error.message}',
      );
      return;
    }
  }

  /// A DATE column — `date_of_birth`, `water_logs.log_date` — takes the day
  /// without a time component, and for a log that day is the user's local one.
  static String _asDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
