import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/chat_repository.dart';
import '../../models/chat_message.dart';

part 'chat_state.dart';

/// One conversation, live.
///
/// Holds a realtime channel for as long as it exists, which is the reason
/// [close] matters more here than in any other cubit in the app: an
/// unsubscribed channel is a socket the app keeps paying for after the screen
/// has gone.
class ChatCubit extends Cubit<ChatState> {
  ChatCubit({
    required ChatRepository chatRepository,
    required String conversationId,
    required String? currentUserId,
  })  : _chat = chatRepository,
        _currentUserId = currentUserId,
        super(ChatState(conversationId: conversationId));

  final ChatRepository _chat;
  final String? _currentUserId;

  RealtimeChannel? _channel;

  static const String _sendFailedKey = 'chat_send_failed';
  static const String _unsendFailedKey = 'chat_unsend_failed';

  /// Loads the most recent page and starts listening.
  Future<void> load() async {
    emit(state.copyWith(status: ChatStatus.loading, clearError: true));

    try {
      final List<ChatMessage> messages =
          await _chat.fetchMessages(state.conversationId);

      if (isClosed) return;

      emit(state.copyWith(
        status: ChatStatus.ready,
        messages: messages,
        // A short first page means there is nothing older; a full one means
        // there might be. "Might" is the honest answer and the one that keeps
        // the spinner from lying about a thread that ends exactly on a page
        // boundary.
        hasMore: messages.length >= ChatRepository.pageSize,
        clearError: true,
      ));

      _listen();
      await markRead();
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: conversation failed to load — $detail');
      emit(state.copyWith(status: ChatStatus.failure, errorMessage: detail));
    }
  }

  /// Reads further back.
  Future<void> loadOlder() async {
    if (!state.hasMore || state.isLoadingOlder || state.messages.isEmpty) {
      return;
    }

    emit(state.copyWith(isLoadingOlder: true));

    try {
      final List<ChatMessage> older = await _chat.fetchMessages(
        state.conversationId,
        before: state.messages.first.createdAt,
      );

      if (isClosed) return;

      emit(state.copyWith(
        messages: [...older, ...state.messages],
        hasMore: older.length >= ChatRepository.pageSize,
        isLoadingOlder: false,
      ));
    } catch (error) {
      if (isClosed) return;
      debugPrint('Bulkr: older messages failed — ${_describe(error)}');
      emit(state.copyWith(isLoadingOlder: false));
    }
  }

  /// Subscribes to the thread.
  ///
  /// Both handlers are idempotent, and have to be: the message you send
  /// arrives back over this channel as well as being returned by the insert,
  /// so whichever lands second must not produce a second bubble.
  void _listen() {
    _channel = _chat.subscribe(
      state.conversationId,
      onMessage: _receive,
      onDeleted: _remove,
    );
  }

  void _receive(ChatMessage message) {
    if (isClosed) return;

    final bool known = state.messages.any((m) => m.id == message.id);
    if (known) return;

    // Drops the optimistic copy of this exact message if one is still on
    // screen: same sender, same text, still pending. Matching on content
    // rather than id because a pending message has no server id yet — that is
    // the whole reason it is pending.
    final List<ChatMessage> without = message.isMine
        ? state.messages
            .where((m) => !(m.isPending && m.body == message.body))
            .toList()
        : state.messages;

    emit(state.copyWith(messages: [...without, message]));

    // Anything that arrives while the thread is open has been seen.
    if (!message.isMine) markRead();
  }

  void _remove(String messageId) {
    if (isClosed) return;
    emit(state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    ));
  }

  /// Sends, showing it immediately.
  ///
  /// Optimistic, unlike almost everything else in this app. A calorie total
  /// that claims to have saved and did not is worth half a second of waiting
  /// to avoid; a chat message that waits for a round trip before appearing
  /// makes the conversation feel like email. A send that fails takes its
  /// bubble away again and says so, because the one outcome a chat must never
  /// produce is a message that looks sent and is not.
  Future<void> send(String body) async {
    final String trimmed = body.trim();
    if (trimmed.isEmpty || state.isSending) return;

    final ChatMessage pending = ChatMessage.pending(
      conversationId: state.conversationId,
      senderId: _currentUserId,
      body: trimmed,
    );

    emit(state.copyWith(
      messages: [...state.messages, pending],
      isSending: true,
      clearError: true,
    ));

    try {
      final ChatMessage sent = await _chat.send(
        conversationId: state.conversationId,
        body: trimmed,
      );

      if (isClosed) return;

      // The realtime channel may have got here first, in which case the
      // pending copy is already gone and this is a no-op.
      final bool known = state.messages.any((m) => m.id == sent.id);

      emit(state.copyWith(
        isSending: false,
        messages: known
            ? state.messages
            : [
                ...state.messages.where((m) => m.id != pending.id),
                sent,
              ],
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: send failed — $detail');

      // The bubble goes. Leaving a failed message looking sent is the one
      // outcome a chat must never produce.
      emit(state.copyWith(
        isSending: false,
        messages: state.messages.where((m) => m.id != pending.id).toList(),
        actionErrorKey: _sendFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  Future<void> unsend(ChatMessage message) async {
    if (!message.isMine || message.isPending) return;

    final ChatState before = state;
    emit(state.copyWith(
      messages: state.messages.where((m) => m.id != message.id).toList(),
    ));

    try {
      await _chat.unsend(message.id);
    } catch (error) {
      if (isClosed) return;
      // Restored, not just reported: the bubble was taken off screen
      // optimistically and the message is still there.
      emit(before.copyWith(
        actionErrorKey: _unsendFailedKey,
        actionErrorDetail: _describe(error),
      ));
    }
  }

  /// Marks the thread read. Never throws — a stale badge is not worth an
  /// error, and the next open corrects it.
  Future<void> markRead() async {
    try {
      await _chat.markRead(state.conversationId);
    } catch (error) {
      debugPrint('Bulkr: could not mark read — $error');
    }
  }

  void clearActionError() => emit(state.copyWith(clearActionError: true));

  @override
  Future<void> close() async {
    final RealtimeChannel? channel = _channel;
    _channel = null;
    if (channel != null) await _chat.unsubscribe(channel);
    return super.close();
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.code, error.message].whereType<String>().join(' · ');
    }
    return error.toString();
  }
}
