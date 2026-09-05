import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/person.dart';

/// Blocking people, and hiding single posts.
///
/// Two different things kept together because they answer the same question
/// from the reader's side — "I do not want to see this" — and because the feed
/// consults both on every load.
///
/// They are enforced very differently, and that is deliberate. **Blocking** is
/// in the row-level security policy: `public.can_view` refuses a blocked
/// author's rows in either direction, so a client that declined to filter would
/// still get nothing. **Hiding** is filtered here, in the query, because it is
/// a preference rather than a permission — and because a post the reader cannot
/// select is a post that cannot be listed back to them, which would make
/// "here is what you have hidden, tap to restore" impossible to build.
class ModerationRepository {
  ModerationRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// How many hidden ids the feed will carry into a query.
  ///
  /// A `not in (...)` list goes into the URL, and PostgREST reads it from a
  /// query string with a length limit. Someone who has hidden more than this
  /// has told us something the app should answer with a mute rather than a
  /// list, but until then the newest are the ones most likely to still be in
  /// the feed they are reading.
  static const int maxHiddenFilter = 200;

  String? get _userId => _client.auth.currentUser?.id;

  // --- Blocking -----------------------------------------------------------

  /// Stops each of you seeing the other.
  ///
  /// One row, and the policy checks both directions — see section 2 of
  /// `social_privacy.sql`. So this needs no second write, and the blocked
  /// person is never told.
  ///
  /// Unfollows in both directions too. A block that left a follow in place
  /// would leave the blocked person listed as a follower on a profile they can
  /// no longer read, which reads as the block not having worked.
  Future<void> block(String personId) async {
    final String? userId = _userId;
    if (userId == null || personId == userId) return;

    await _client.from('blocks').upsert(
      {'blocker_id': userId, 'blocked_id': personId},
      onConflict: 'blocker_id,blocked_id',
    );

    try {
      await _client
          .from('follows')
          .delete()
          .or('and(follower_id.eq.$userId,followee_id.eq.$personId),'
              'and(follower_id.eq.$personId,followee_id.eq.$userId)');
    } catch (error) {
      // The block is the part that matters and it has already landed. A
      // stale follow row is untidy, not unsafe.
      debugPrint('Bulkr: could not clear follows after a block — $error');
    }
  }

  Future<void> unblock(String personId) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('blocks')
        .delete()
        .eq('blocker_id', userId)
        .eq('blocked_id', personId);
  }

  /// Ids this user has blocked.
  ///
  /// Only their own — the policy on `blocks` refuses to show anyone who has
  /// blocked *them*, which is exactly the list a blocked person should not be
  /// handed.
  Future<Set<String>> blockedIds() async {
    final String? userId = _userId;
    if (userId == null) return <String>{};

    final rows = await _client
        .from('blocks')
        .select('blocked_id')
        .eq('blocker_id', userId);

    return rows.map((row) => '${row['blocked_id']}').toSet();
  }

  /// The people this user has blocked, for the list that undoes it.
  ///
  /// Readable even though they are blocked: `users` is readable to anyone
  /// signed in, and it is `posts` and `meals` that `can_view` gates. Someone
  /// who cannot see who they blocked cannot unblock them.
  Future<List<Person>> blockedPeople() async {
    final String? userId = _userId;
    if (userId == null) return const <Person>[];

    final rows = await _client
        .from('blocks')
        .select('blocked_id, created_at, '
            'users!blocks_blocked_id_fkey(id, username, display_name, '
            'avatar_url, bio, is_trainer)')
        .eq('blocker_id', userId)
        .order('created_at', ascending: false);

    final List<Person> people = [];

    for (final Map<String, dynamic> row in rows) {
      final Map<String, dynamic>? person = _embedded(row['users']);
      if (person == null) continue;
      people.add(Person.fromRow(person));
    }

    return people;
  }

  Future<bool> isBlocked(String personId) async {
    final String? userId = _userId;
    if (userId == null) return false;

    final row = await _client
        .from('blocks')
        .select('blocked_id')
        .eq('blocker_id', userId)
        .eq('blocked_id', personId)
        .maybeSingle();

    return row != null;
  }

  // --- Hiding a post ------------------------------------------------------

  /// Takes one post out of this reader's feed, for them alone.
  ///
  /// Nothing like `posts.is_hidden`, which is the author or the report
  /// threshold pulling a post for everybody.
  Future<void> hidePost(String postId) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client.from('hidden_posts').upsert(
      {'user_id': userId, 'post_id': postId},
      onConflict: 'user_id,post_id',
    );
  }

  Future<void> unhidePost(String postId) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('hidden_posts')
        .delete()
        .eq('user_id', userId)
        .eq('post_id', postId);
  }

  /// Post ids this reader has hidden, newest first and capped.
  Future<Set<String>> hiddenPostIds() async {
    final String? userId = _userId;
    if (userId == null) return <String>{};

    final rows = await _client
        .from('hidden_posts')
        .select('post_id')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(maxHiddenFilter);

    return rows.map((row) => '${row['post_id']}').toSet();
  }

  static Map<String, dynamic>? _embedded(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty) {
      final Object? first = value.first;
      if (first is Map<String, dynamic>) return first;
    }
    return null;
  }
}
