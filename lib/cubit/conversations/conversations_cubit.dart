import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/chat_repository.dart';
import '../../models/conversation.dart';

part 'conversations_state.dart';

/// The list of threads.
class ConversationsCubit extends Cubit<ConversationsState> {
  ConversationsCubit({required ChatRepository chatRepository})
      : _chat = chatRepository,
        super(const ConversationsState());

  final ChatRepository _chat;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(
        status: ConversationsStatus.loading,
        clearError: true,
      ));
    }

    try {
      final List<Conversation> conversations = await _chat.fetchConversations();
      if (isClosed) return;

      emit(state.copyWith(
        status: ConversationsStatus.ready,
        conversations: conversations,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: conversations failed to load — $detail');

      // A silent refresh that fails leaves the list alone: somebody asked for
      // fresher threads, not for the ones they were reading to be replaced by
      // an error.
      if (silent && state.status == ConversationsStatus.ready) return;

      emit(state.copyWith(
        status: ConversationsStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Zeroes one thread's badge without a round trip.
  ///
  /// Called when a thread is opened. The screen marks it read on the server
  /// too; this is so the list behind it agrees immediately rather than on the
  /// next refresh.
  void markSeen(String conversationId) {
    emit(state.copyWith(
      conversations: state.conversations
          .map((c) => c.id == conversationId ? c.withoutUnread() : c)
          .toList(),
    ));
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.code, error.message].whereType<String>().join(' · ');
    }
    return error.toString();
  }
}
