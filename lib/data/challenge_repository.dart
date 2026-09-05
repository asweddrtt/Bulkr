import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/challenge.dart';

/// Reads and writes challenges, and reads their leaderboards.
class ChallengeRepository {
  ChallengeRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Columns of `challenges` plus the participant count.
  ///
  /// The foreign key is named because `challenge_participants` points at both
  /// `challenges` and `users`, which is the junction shape PostgREST reads as
  /// many-to-many.
  static const String _challengeColumns =
      '*, challenge_participants!challenge_participants_challenge_id_fkey(count)';

  String? get _userId => _client.auth.currentUser?.id;

  /// The challenges attached to these posts, keyed by post id.
  ///
  /// One query for a whole page of the feed rather than one per card, and one
  /// more to resolve which of them this user has joined. Returns a map because
  /// the caller is matching them back onto posts, and a list would make every
  /// card search it.
  Future<Map<String, Challenge>> fetchForPosts(List<String> postIds) async {
    if (postIds.isEmpty) return const {};

    final String? userId = _userId;

    final List<Map<String, dynamic>> rows = await _client
        .from('challenges')
        .select(_challengeColumns)
        .inFilter('post_id', postIds);

    final List<Challenge> challenges = rows
        .map((row) => Challenge.fromRow(row, currentUserId: userId))
        .toList();

    final List<Challenge> resolved = await _withMyParticipation(challenges);

    return {
      for (final Challenge challenge in resolved) challenge.postId: challenge,
    };
  }

  /// One post's challenge, or null when it has none.
  Future<Challenge?> fetchForPost(String postId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('challenges')
        .select(_challengeColumns)
        .eq('post_id', postId)
        .limit(1);

    if (rows.isEmpty) return null;

    final Challenge challenge =
        Challenge.fromRow(rows.first, currentUserId: _userId);
    final List<Challenge> resolved = await _withMyParticipation([challenge]);
    return resolved.first;
  }

  /// Every challenge this user has joined, newest first.
  ///
  /// The leaderboard used to be reachable from exactly one place: a challenge
  /// post, while it was still on screen. Scroll past it and the challenge you
  /// had joined was gone — the standings, the deadline, all of it — until the
  /// post happened to come round again.
  ///
  /// Two queries rather than an embed. `challenge_participants` points at both
  /// `challenges` and `users` and has nothing else of its own, which is the
  /// exact shape PostgREST reads as a junction table, so embedding from that
  /// side is where PGRST201 comes from. Asking for the ids and then the rows
  /// is one more round trip and no ambiguity.
  Future<List<Challenge>> fetchMine() async {
    final String? userId = _userId;
    if (userId == null) return const <Challenge>[];

    final List<Map<String, dynamic>> joins = await _client
        .from('challenge_participants')
        .select('challenge_id')
        .eq('user_id', userId);

    final List<String> ids = [
      for (final Map<String, dynamic> row in joins) '${row['challenge_id']}',
    ];

    if (ids.isEmpty) return const <Challenge>[];

    final List<Map<String, dynamic>> rows = await _client
        .from('challenges')
        .select(_challengeColumns)
        .inFilter('id', ids)
        // Live ones first, then the most recently finished. Someone opening
        // this is almost always looking at something still running.
        .order('ends_at', ascending: false);

    return rows
        .map((row) => Challenge.fromRow(row, currentUserId: userId))
        // Every one of these came out of this user's own participation rows,
        // so joining is already established and `_withMyParticipation` would
        // be a third query to learn what the first one said.
        .map((challenge) => challenge.copyWith(hasJoined: true))
        .toList();
  }

  /// Attaches a challenge to a post the user wrote.
  ///
  /// The policy checks the same thing — only a post's author may attach one —
  /// so a mismatch here fails at the database rather than creating a challenge
  /// on somebody else's announcement.
  Future<Challenge> createForPost({
    required String postId,
    required ChallengeDraft draft,
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot create a challenge without a signed-in user');
    }

    if (!draft.canSubmit) {
      throw StateError('Cannot create a challenge without a title and a goal');
    }

    final Map<String, dynamic> row = await _client
        .from('challenges')
        .insert(draft.toRowValues(postId: postId, createdBy: userId))
        .select(_challengeColumns)
        .single();

    return Challenge.fromRow(row, currentUserId: userId);
  }

  /// Joins a challenge, or leaves it.
  ///
  /// Nothing is sent about the starting weight. A trigger fills it in from the
  /// user's own `users` row, and discards whatever the insert supplied —
  /// otherwise a client could start a challenge at 40 kg and top the
  /// leaderboard from a standing start.
  Future<void> setJoined({
    required String challengeId,
    required bool hasJoined,
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot join a challenge without a signed-in user');
    }

    if (hasJoined) {
      await _client.from('challenge_participants').upsert(
            {'challenge_id': challengeId, 'user_id': userId},
            onConflict: 'challenge_id,user_id',
            ignoreDuplicates: true,
          );
    } else {
      await _client
          .from('challenge_participants')
          .delete()
          .eq('challenge_id', challengeId)
          .eq('user_id', userId);
    }
  }

  /// A challenge's standings, most gained first.
  ///
  /// Read through the `challenge_leaderboard` function rather than from the
  /// tables, and it has to be: `challenge_participants` is readable only by
  /// its own participant, because the row carries a start weight. The function
  /// runs as its owner and returns deltas — how much each person has gained,
  /// never what anyone weighs.
  ///
  /// So this is not a convenience wrapper. It is the only way the leaderboard
  /// exists at all.
  Future<List<ChallengeStanding>> fetchLeaderboard(String challengeId) async {
    final List<dynamic> rows = await _client.rpc(
      'challenge_leaderboard',
      params: {'challenge': challengeId},
    ) as List<dynamic>;

    final String? userId = _userId;

    return rows
        .whereType<Map<String, dynamic>>()
        .map((row) => ChallengeStanding.fromRow(row, currentUserId: userId))
        .toList(growable: false);
  }

  /// Marks which of [challenges] this user has joined.
  ///
  /// Reads only this user's own participation rows, which is all the policy
  /// allows and all this needs. Non-fatal: a Join button that should say
  /// "joined" is wrong in a way the next load fixes, and tapping it is an
  /// upsert that changes nothing.
  Future<List<Challenge>> _withMyParticipation(
    List<Challenge> challenges,
  ) async {
    final String? userId = _userId;
    if (userId == null || challenges.isEmpty) return challenges;

    final List<String> ids =
        challenges.map((challenge) => challenge.id).toList();

    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('challenge_participants')
          .select('challenge_id')
          .eq('user_id', userId)
          .inFilter('challenge_id', ids);

      final Set<String> joined = {
        for (final Map<String, dynamic> row in rows) '${row['challenge_id']}',
      };

      return challenges
          .map((challenge) =>
              challenge.copyWith(hasJoined: joined.contains(challenge.id)))
          .toList(growable: false);
    } catch (error) {
      debugPrint('Bulkr: could not resolve challenge participation — $error');
      return challenges;
    }
  }
}
