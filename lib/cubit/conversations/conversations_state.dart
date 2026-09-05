part of 'conversations_cubit.dart';

enum ConversationsStatus { initial, loading, ready, failure }

class ConversationsState extends Equatable {
  const ConversationsState({
    this.status = ConversationsStatus.initial,
    this.conversations = const [],
    this.errorMessage,
  });

  final ConversationsStatus status;
  final List<Conversation> conversations;
  final String? errorMessage;

  bool get isEmpty => conversations.isEmpty;

  /// What the badge on the nav would show. Summed here rather than asked for
  /// separately — the list already knows.
  int get unreadTotal {
    int total = 0;
    for (final Conversation conversation in conversations) {
      total += conversation.unreadCount;
    }
    return total;
  }

  ConversationsState copyWith({
    ConversationsStatus? status,
    List<Conversation>? conversations,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConversationsState(
      status: status ?? this.status,
      conversations: conversations ?? this.conversations,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, conversations, errorMessage];
}
