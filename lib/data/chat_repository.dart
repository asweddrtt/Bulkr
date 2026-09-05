import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';

/// Direct messages.
///
/// The only repository in the app that holds a live connection. Everything
/// else answers a question and returns; this one also opens a channel and
/// keeps pushing until it is closed, which is why [subscribe] hands back a
/// `StreamSubscription`-shaped thing the caller has to dispose.
class ChatRepository {
  ChatRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// How many messages a page of history holds.
  ///
  /// A thread is read from the bottom and paged backwards, so this is "how far
  /// back does opening it reach" rather than "how much is there".
  static const int pageSize = 40;

  String? get _userId => _client.auth.currentUser?.id;

  /// The signed-in user's id, for a screen that has to hand it to a cubit.
  String? get currentUserId => _userId;

  // --- The list ------------------------------------------------------------

  /// Every conversation with something in it, most recent first.
  ///
  /// One call to `conversation_summaries()`, which does the lateral joins for
  /// the last message and the unread count server-side. Assembling this from
  /// PostgREST would be a request per thread — the shape that makes a chat
  /// list slow the moment somebody has twenty.
  Future<List<Conversation>> fetchConversations() async {
    if (_userId == null) return const <Conversation>[];

    final List<dynamic> rows =
        await _client.rpc('conversation_summaries') as List<dynamic>;

    return rows
        .whereType<Map<String, dynamic>>()
        .map(Conversation.fromRow)
        .toList();
  }

  // --- One thread ----------------------------------------------------------

  /// The id of the direct conversation with [personId], creating it if needed.
  ///
  /// Through the `start_direct_conversation` function rather than an insert,
  /// because starting a thread means writing the *other* person's membership
  /// row — which no policy scoped to `auth.uid()` can allow, and which is
  /// exactly why that function is SECURITY DEFINER. It also makes this safe
  /// against two devices opening the same thread at once: the second conflicts
  /// on `direct_key` and gets the first one's id.
  Future<String> openDirect(String personId) async {
    final Object? id =
        await _client.rpc('start_direct_conversation', params: {
      'p_other': personId,
    });

    if (id == null) throw StateError('Could not open that conversation');
    return '$id';
  }

  /// A page of history, newest first.
  ///
  /// [before] pages backwards: pass the oldest message already on screen and
  /// this returns what came before it. Keyset rather than offset, for the
  /// reason the feed uses keyset — a thread takes inserts while it is being
  /// read, and an offset would repeat and skip rows as it grew.
  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    DateTime? before,
  }) async {
    final String? userId = _userId;

    var query = _client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await query
        .order('created_at', ascending: false)
        .limit(pageSize);

    // Reversed on the way out: the query wants newest first so the limit takes
    // the recent end, and the screen wants oldest first so it reads downwards.
    return rows
        .map((row) => ChatMessage.fromRow(row, currentUserId: userId))
        .toList()
        .reversed
        .toList();
  }

  /// Sends [body] into [conversationId].
  ///
  /// Returns the stored row. The screen has already drawn an optimistic copy,
  /// and this is what replaces it — matched on nothing, because the same
  /// message also arrives over the realtime channel and whichever gets there
  /// first is the one that wins.
  Future<ChatMessage> send({
    required String conversationId,
    required String body,
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot send a message without a signed-in user');
    }

    final String trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw StateError('Cannot send an empty message');
    }

    final Map<String, dynamic> row = await _client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': userId,
          'body': trimmed,
        })
        .select()
        .single();

    return ChatMessage.fromRow(row, currentUserId: userId);
  }

  /// Removes one of your own messages.
  Future<void> unsend(String messageId) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('messages')
        .delete()
        .eq('id', messageId)
        .eq('sender_id', userId);
  }

  /// When the other person last read this conversation.
  ///
  /// Their `last_read_at`, which the membership policy lets a member of the
  /// same thread read — that is what makes a read receipt possible without a
  /// second table or a function.
  ///
  /// Null when there is no other member, when they have never opened it, or
  /// when the read fails. All three render the same way: no receipt. A tick
  /// that appears because a query errored would be worse than no tick, since
  /// the whole value of it is that it is trustworthy.
  Future<DateTime?> fetchOtherLastRead(String conversationId) async {
    final String? userId = _userId;
    if (userId == null) return null;

    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('conversation_members')
          .select('last_read_at')
          .eq('conversation_id', conversationId)
          .neq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return null;
      return DateTime.tryParse('${rows.first['last_read_at']}')?.toLocal();
    } catch (error) {
      debugPrint('Bulkr: read receipt unavailable — $error');
      return null;
    }
  }

  /// Marks everything in [conversationId] as read, as of now.
  ///
  /// A timestamp rather than a counter — see the note on
  /// `conversation_members.last_read_at`. Non-fatal by contract: the caller
  /// treats a failure as "the badge is stale", which the next open corrects.
  Future<void> markRead(String conversationId) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('conversation_members')
        .update({'last_read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('conversation_id', conversationId)
        .eq('user_id', userId);
  }

  // --- Live ----------------------------------------------------------------

  /// Watches [conversationId] for messages arriving and being unsent.
  ///
  /// A channel per open thread, torn down with the screen. The filter is
  /// applied server-side, so a busy app is not receiving every message in the
  /// database and discarding the ones it does not want — and row-level
  /// security still applies on top, so a thread this user is not in would send
  /// nothing even without the filter.
  ///
  /// Returns the channel so the caller can unsubscribe. Not a `Stream`,
  /// deliberately: a stream would hide the fact that this holds a socket, and
  /// the one thing a caller must not forget is to close it.
  RealtimeChannel subscribe(
    String conversationId, {
    required void Function(ChatMessage message) onMessage,
    required void Function(String messageId) onDeleted,
  }) {
    final String? userId = _userId;

    final RealtimeChannel channel = _client
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            onMessage(
              ChatMessage.fromRow(payload.newRecord, currentUserId: userId),
            );
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            // A delete payload carries only the old row, and only carries all
            // of it because `messages` is set to REPLICA IDENTITY FULL — see
            // section 7 of `chat_schema.sql`. Without that this would be a
            // primary key and nothing to match a conversation on, which is
            // why the filter is not applied here and the id is checked
            // instead.
            final Object? id = payload.oldRecord['id'];
            if (id != null) onDeleted('$id');
          },
        );

    return channel..subscribe();
  }

  /// Closes a channel opened by [subscribe].
  Future<void> unsubscribe(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}
