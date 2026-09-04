import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/person.dart';

/// Reads and writes who follows whom.
///
/// Follows are directional and stored as one row per direction, so "do I
/// follow them" and "do they follow me" are two different questions with two
/// different answers — and both get asked, because a profile shows the second
/// before you decide about the first.
class FollowRepository {
  FollowRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Columns of `users` that make up a public profile, plus the count
  /// aggregates.
  ///
  /// Every embed names its foreign key, and here it is not optional: `follows`
  /// points at `users` twice — `follower_id` and `followee_id` — so
  /// `follows(count)` is ambiguous between "people they follow" and "people
  /// who follow them" and answers PGRST201. The aliases matter for the same
  /// reason: two embeds of the same table would both land under the key
  /// `follows` and one would win.
  ///
  /// Biometrics are not selected. Not because the policy hides them — it does
  /// not, and `feed_follows.sql` says so — but because a query that does not
  /// ask for someone's weight cannot accidentally render it.
  static const String _personColumns = 'id, username, display_name, '
      'avatar_url, bio, is_trainer, '
      'followers:follows!follows_followee_id_fkey(count), '
      'following:follows!follows_follower_id_fkey(count), '
      'posts!posts_user_id_fkey(count)';

  /// How many people a list page holds.
  static const int pageSize = 30;

  /// The ceiling on how many follows For You will read.
  ///
  /// The feed asks for the ids and passes them to `.inFilter('user_id', ids)`,
  /// which becomes a query string — so this is bounded by URL length, not by
  /// taste. Well past what anyone follows by hand, and it fails safe: someone
  /// over the cap gets a feed from their oldest follows rather than an error.
  ///
  /// Going beyond this means moving the join into the database — a view or a
  /// SECURITY INVOKER function that takes the keyset cursor — which is a real
  /// change and not one worth making before anyone is near the limit.
  static const int followedIdsLimit = 500;

  String? get _userId => _client.auth.currentUser?.id;

  /// Everyone this user follows.
  ///
  /// Ids only, because that is all the feed query needs, and reading whole
  /// profiles to throw away everything but the id is a round trip's worth of
  /// bytes for nothing.
  Future<List<String>> followedIds([String? userId]) async {
    final String? id = userId ?? _userId;
    if (id == null) return const [];

    final List<Map<String, dynamic>> rows = await _client
        .from('follows')
        .select('followee_id')
        .eq('follower_id', id)
        .order('created_at', ascending: true)
        .limit(followedIdsLimit);

    return rows.map((row) => '${row['followee_id']}').toList(growable: false);
  }

  /// Follows someone, or stops.
  ///
  /// An insert and a delete. The primary key makes following twice a no-op
  /// rather than a second row, and the CHECK constraint refuses a self-follow —
  /// which the UI never offers, but the repository is not the only way in.
  Future<void> setFollowing({
    required String personId,
    required bool isFollowing,
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot follow without a signed-in user');
    }

    if (personId == userId) {
      throw StateError('Cannot follow yourself');
    }

    if (isFollowing) {
      // Upsert rather than insert: two taps racing would otherwise turn the
      // second into a 23505 the user has to see, for the outcome they wanted.
      await _client.from('follows').upsert(
            {'follower_id': userId, 'followee_id': personId},
            onConflict: 'follower_id,followee_id',
            ignoreDuplicates: true,
          );
    } else {
      await _client
          .from('follows')
          .delete()
          .eq('follower_id', userId)
          .eq('followee_id', personId);
    }
  }

  /// One person's public profile.
  ///
  /// Returns null when the row is not readable — either it does not exist, or
  /// they never finished onboarding, which the read policy treats the same way.
  /// A profile link to a half-signed-up account wants "not found", not an
  /// error screen.
  Future<Person?> fetchPerson(String personId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('users')
        .select(_personColumns)
        .eq('id', personId)
        .limit(1);

    if (rows.isEmpty) return null;

    final Person person = Person.fromRow(rows.first, currentUserId: _userId);
    final List<Person> resolved = await _withMyRelationship([person]);
    return resolved.first;
  }

  /// Accounts worth following, best first.
  ///
  /// Trainers lead, then whoever has been active most recently. Deliberately
  /// not "most followers": follower count is an aggregate here rather than a
  /// column, so it cannot be ordered on in the database — and it is the worse
  /// signal anyway. Someone who posted this week is a better follow than
  /// someone with four thousand followers who left in March, and activity
  /// cannot be farmed the way a follower count can.
  ///
  /// People the user already follows are filtered out on the client rather
  /// than in the query. Excluding them server-side would mean a `not.in` list
  /// of every follow, which is the same URL-length problem
  /// [followedIdsLimit] exists for — and over-fetching thirty rows to drop a
  /// few is cheaper than that.
  Future<List<Person>> fetchSuggested() async {
    final String? userId = _userId;

    final List<Map<String, dynamic>> rows = await _client
        .from('users')
        .select(_personColumns)
        .eq('onboarding_completed', true)
        .order('is_trainer', ascending: false)
        .order('last_active_at', ascending: false)
        .limit(pageSize * 2);

    final List<Person> people = rows
        .map((row) => Person.fromRow(row, currentUserId: userId))
        .where((person) => !person.isMe)
        .toList();

    final List<Person> resolved = await _withMyRelationship(people);

    return resolved
        .where((person) => !person.isFollowedByMe)
        .take(pageSize)
        .toList(growable: false);
  }

  /// People whose handle or name contains [query].
  ///
  /// Matches both, because someone looking for a person will type whichever
  /// they remember. Served by the trigram indexes — `ilike '%term%'` cannot use
  /// a btree, which is why those indexes exist.
  Future<List<Person>> searchPeople(String query) async {
    final String needle = query.trim();
    if (needle.isEmpty) return const [];

    final String pattern = '%${_escapeLike(needle)}%';

    final List<Map<String, dynamic>> rows = await _client
        .from('users')
        .select(_personColumns)
        .eq('onboarding_completed', true)
        .or('username.ilike.$pattern,display_name.ilike.$pattern')
        .order('is_trainer', ascending: false)
        .order('last_active_at', ascending: false)
        .limit(pageSize);

    final List<Person> people = rows
        .map((row) => Person.fromRow(row, currentUserId: _userId))
        .toList();

    return _withMyRelationship(people);
  }

  /// The people following [personId].
  Future<List<Person>> fetchFollowers(String personId) =>
      _fetchRelated(personId: personId, column: 'followee_id', join: 'follower');

  /// The people [personId] follows.
  Future<List<Person>> fetchFollowing(String personId) =>
      _fetchRelated(personId: personId, column: 'follower_id', join: 'followee');

  /// One side of the follow graph, read through the join table.
  ///
  /// [column] is which end of `follows` is being matched, and [join] names the
  /// foreign key to embed the *other* end through — the two always disagree,
  /// which is the whole reason this cannot be one query with a flag.
  Future<List<Person>> _fetchRelated({
    required String personId,
    required String column,
    required String join,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('follows')
        .select('person:users!follows_${join}_id_fkey($_personColumns)')
        .eq(column, personId)
        .order('created_at', ascending: false)
        .limit(pageSize * 4);

    final List<Person> people = [];
    for (final Map<String, dynamic> row in rows) {
      final Map<String, dynamic>? personRow = _embedded(row['person']);

      // A follow whose other end is not readable — never onboarded, or gone.
      // Skipped rather than rendered as a blank row.
      if (personRow == null) continue;

      people.add(Person.fromRow(personRow, currentUserId: _userId));
    }

    return _withMyRelationship(people);
  }

  /// Marks, for each of [people], whether this user follows them and whether
  /// they follow this user.
  ///
  /// Two queries for the whole list rather than one per row. Non-fatal: a list
  /// where every button reads "follow" is wrong in a way the next load fixes,
  /// and tapping one that was already followed is an upsert that changes
  /// nothing.
  Future<List<Person>> _withMyRelationship(List<Person> people) async {
    final String? userId = _userId;
    if (userId == null || people.isEmpty) return people;

    final List<String> ids = people.map((person) => person.id).toList();

    try {
      final results = await Future.wait([
        _client
            .from('follows')
            .select('followee_id')
            .eq('follower_id', userId)
            .inFilter('followee_id', ids),
        _client
            .from('follows')
            .select('follower_id')
            .eq('followee_id', userId)
            .inFilter('follower_id', ids),
      ]);

      final Set<String> iFollow = {
        for (final Map<String, dynamic> row in results[0])
          '${row['followee_id']}',
      };
      final Set<String> followsMe = {
        for (final Map<String, dynamic> row in results[1])
          '${row['follower_id']}',
      };

      return people
          .map((person) => person.copyWith(
                isFollowedByMe: iFollow.contains(person.id),
                followsMe: followsMe.contains(person.id),
              ))
          .toList(growable: false);
    } catch (error) {
      debugPrint('Bulkr: could not resolve follow state — $error');
      return people;
    }
  }

  static Map<String, dynamic>? _embedded(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty && value.first is Map<String, dynamic>) {
      return value.first as Map<String, dynamic>;
    }
    return null;
  }

  /// Neutralises the wildcards in a user-typed search term.
  ///
  /// Without this, typing `%` matches every account in the database and `_`
  /// matches any single character — so a search for "a_i" would quietly return
  /// "ali", "abi" and "api". Backslash is escaped first, or escaping the
  /// others would double-escape it.
  static String _escapeLike(String term) => term
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
