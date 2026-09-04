import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group.dart';

/// Reads and writes groups and who is in them.
class GroupRepository {
  GroupRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Storage bucket for group pictures. Public-read, like the other two.
  static const String imageBucket = 'group-images';

  static const int pageSize = 50;

  /// The ceiling on how many groups feed the For You query.
  ///
  /// Bounded for the same reason [FollowRepository.followedIdsLimit] is: the
  /// ids end up in a query string. Nobody is in five hundred groups, and it
  /// fails safe — someone over the cap gets their oldest groups.
  static const int membershipLimit = 200;

  /// Columns of `groups` plus the count aggregates.
  ///
  /// Both foreign keys are named. `group_members` points at `groups` and at
  /// `users`, which is the junction shape PostgREST reads as many-to-many, so
  /// the aggregate has to say which relationship it is counting.
  static const String _groupColumns = '*, '
      'group_members!group_members_group_id_fkey(count), '
      'posts!posts_group_id_fkey(count)';

  String? get _userId => _client.auth.currentUser?.id;

  /// The groups this user is in, most recently joined first.
  Future<List<Group>> fetchMyGroups() async {
    final String? userId = _userId;
    if (userId == null) return const [];

    final List<Map<String, dynamic>> rows = await _client
        .from('group_members')
        .select('group_id, role, joined_at, groups($_groupColumns)')
        .eq('user_id', userId)
        .order('joined_at', ascending: false)
        .limit(pageSize);

    final List<Group> groups = [];
    for (final Map<String, dynamic> row in rows) {
      final Map<String, dynamic>? groupRow = _embedded(row['groups']);

      // A membership whose group is gone. Skipped rather than rendered as a
      // blank card.
      if (groupRow == null) continue;

      groups.add(Group.fromRow(
        groupRow,
        currentUserId: userId,
        isMember: true,
      ));
    }

    return groups;
  }

  /// Group ids this user belongs to.
  ///
  /// Ids only, because that is all the For You query needs — reading whole
  /// group rows to throw away everything but the id is bytes for nothing.
  Future<List<String>> memberGroupIds([String? userId]) async {
    final String? id = userId ?? _userId;
    if (id == null) return const [];

    final List<Map<String, dynamic>> rows = await _client
        .from('group_members')
        .select('group_id')
        .eq('user_id', id)
        .order('joined_at', ascending: true)
        .limit(membershipLimit);

    return rows.map((row) => '${row['group_id']}').toList(growable: false);
  }

  /// Public groups worth joining, newest first.
  ///
  /// Newest rather than biggest: member count is an aggregate here, for the
  /// same reasons follower count is, so it cannot be ordered on in the
  /// database.
  ///
  /// Private groups are absent because the read policy hides them, not because
  /// this query excludes them — which is the right way round. A private group
  /// the user is already in comes back through [fetchMyGroups].
  Future<List<Group>> fetchDiscoverable() async {
    final String? userId = _userId;

    final List<Map<String, dynamic>> rows = await _client
        .from('groups')
        .select(_groupColumns)
        .eq('is_private', false)
        .order('created_at', ascending: false)
        .limit(pageSize);

    final List<Group> groups = rows
        .map((row) => Group.fromRow(row, currentUserId: userId))
        .toList();

    return _withMyMembership(groups);
  }

  /// Groups whose name contains [query].
  Future<List<Group>> searchGroups(String query) async {
    final String needle = query.trim();
    if (needle.isEmpty) return const [];

    final List<Map<String, dynamic>> rows = await _client
        .from('groups')
        .select(_groupColumns)
        .ilike('name', '%${_escapeLike(needle)}%')
        .order('created_at', ascending: false)
        .limit(pageSize);

    final List<Group> groups = rows
        .map((row) => Group.fromRow(row, currentUserId: _userId))
        .toList();

    return _withMyMembership(groups);
  }

  /// One group.
  ///
  /// Returns null when the row is not readable — it does not exist, or it is
  /// private and this user is not in it. Both want "not found" rather than an
  /// error, and telling the two apart would itself leak that a private group
  /// exists.
  Future<Group?> fetchGroup(String groupId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('groups')
        .select(_groupColumns)
        .eq('id', groupId)
        .limit(1);

    if (rows.isEmpty) return null;

    final Group group = Group.fromRow(rows.first, currentUserId: _userId);
    final List<Group> resolved = await _withMyMembership([group]);
    return resolved.first;
  }

  /// Creates a group. The owner is added as a member by a trigger.
  Future<Group> createGroup({
    required GroupDraft draft,
    Uint8List? imageBytes,
    String imageExtension = 'jpg',
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot create a group without a signed-in user');
    }

    if (!draft.canSubmit) {
      throw StateError('Cannot create a group without a valid name');
    }

    // The photo goes first, for the same reason it does when creating a meal
    // or a post: a failed upload should not leave a group row behind.
    String? imageUrl;
    if (imageBytes != null) {
      imageUrl = await _uploadImage(
        userId: userId,
        bytes: imageBytes,
        extension: imageExtension,
      );
    }

    final Map<String, dynamic> row = await _client
        .from('groups')
        .insert(draft.toRowValues(ownerId: userId, imageUrl: imageUrl))
        .select(_groupColumns)
        .single();

    // `isMember` is forced true rather than read back. The trigger inserts the
    // owner's membership row, but the `.select()` above ran in the same
    // statement as the insert and its aggregate may not see it — and an owner
    // who appears not to be in their own group cannot post to it.
    return Group.fromRow(row, currentUserId: userId, isMember: true);
  }

  /// Joins a group, or leaves it.
  ///
  /// An insert and a delete. The primary key makes joining twice a no-op, and
  /// the policy refuses joining as anything other than a plain member — so
  /// there is no way to join a group as its owner.
  Future<void> setMembership({
    required String groupId,
    required bool isMember,
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot join a group without a signed-in user');
    }

    if (isMember) {
      await _client.from('group_members').upsert(
            {'group_id': groupId, 'user_id': userId, 'role': 'member'},
            onConflict: 'group_id,user_id',
            ignoreDuplicates: true,
          );
    } else {
      // The policy refuses this for an owner, so leaving your own group
      // deletes nothing rather than orphaning it.
      await _client
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);
    }
  }

  /// Deletes a group the user owns.
  ///
  /// Membership rows cascade. Its posts do not — the foreign key is SET NULL,
  /// so they survive as ordinary feed posts. Deleting the room is not deleting
  /// what people wrote in it.
  Future<void> deleteGroup(String groupId) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot delete a group without a signed-in user');
    }

    await _client
        .from('groups')
        .delete()
        .eq('id', groupId)
        .eq('owner_id', userId);
  }

  /// Marks which of [groups] this user is in.
  ///
  /// One query for the whole list. Non-fatal: a list where every button reads
  /// "join" is wrong in a way the next load fixes, and tapping one for a group
  /// already joined is an upsert that changes nothing.
  Future<List<Group>> _withMyMembership(List<Group> groups) async {
    final String? userId = _userId;
    if (userId == null || groups.isEmpty) return groups;

    final List<String> ids = groups.map((group) => group.id).toList();

    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', userId)
          .inFilter('group_id', ids);

      final Set<String> joined = {
        for (final Map<String, dynamic> row in rows) '${row['group_id']}',
      };

      return groups
          .map((group) => group.copyWith(isMember: joined.contains(group.id)))
          .toList(growable: false);
    } catch (error) {
      debugPrint('Bulkr: could not resolve group membership — $error');
      return groups;
    }
  }

  Future<String> _uploadImage({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final String path =
        '$userId/${DateTime.now().toUtc().microsecondsSinceEpoch}.$extension';

    await _client.storage.from(imageBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(extension),
            upsert: false,
          ),
        );

    return _client.storage.from(imageBucket).getPublicUrl(path);
  }

  static String _contentTypeFor(String extension) {
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

  static Map<String, dynamic>? _embedded(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List &&
        value.isNotEmpty &&
        value.first is Map<String, dynamic>) {
      return value.first as Map<String, dynamic>;
    }
    return null;
  }

  /// Neutralises the wildcards in a user-typed search term, so `%` does not
  /// match every group in the database.
  static String _escapeLike(String term) => term
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
