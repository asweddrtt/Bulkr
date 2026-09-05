part of 'chat_cubit.dart';

enum ChatStatus { initial, loading, ready, failure }

class ChatState extends Equatable {
  const ChatState({
    required this.conversationId,
    this.status = ChatStatus.initial,
    this.messages = const [],
    this.hasMore = false,
    this.isLoadingOlder = false,
    this.isSending = false,
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
    this.otherLastReadAt,
  });

  final String conversationId;
  final ChatStatus status;

  /// Oldest first, so the list reads downwards the way the conversation
  /// happened.
  final List<ChatMessage> messages;

  final bool hasMore;
  final bool isLoadingOlder;

  /// A send is in flight. Kept out of [status] so sending never blanks the
  /// thread that is already on screen.
  final bool isSending;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  /// When the other person last opened this thread.
  ///
  /// Null when they never have, when there is nobody else in it, or when the
  /// read failed — all three show no receipt, because a tick that appeared
  /// because a query errored would be worse than no tick at all.
  final DateTime? otherLastReadAt;

  bool get isEmpty => messages.isEmpty;

  /// The last message this user sent, if it is the kind a receipt can be shown
  /// under: theirs, stored, and older than the other person's last read.
  ///
  /// One receipt at the bottom rather than a tick on every bubble. Read
  /// receipts are cumulative — reading a thread reads everything above — so a
  /// column of identical ticks says nothing the last one does not.
  ChatMessage? get lastSeenMessage {
    final DateTime? seenAt = otherLastReadAt;
    if (seenAt == null) return null;

    for (final ChatMessage message in messages.reversed) {
      if (!message.isMine || message.isPending) continue;
      return message.createdAt.isAfter(seenAt) ? null : message;
    }
    return null;
  }

  ChatState copyWith({
    ChatStatus? status,
    List<ChatMessage>? messages,
    bool? hasMore,
    bool? isLoadingOlder,
    bool? isSending,
    String? errorMessage,
    bool clearError = false,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearActionError = false,
    DateTime? otherLastReadAt,
  }) {
    return ChatState(
      conversationId: conversationId,
      status: status ?? this.status,
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      isSending: isSending ?? this.isSending,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorKey:
          clearActionError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail: clearActionError
          ? null
          : (actionErrorDetail ?? this.actionErrorDetail),
      otherLastReadAt: otherLastReadAt ?? this.otherLastReadAt,
    );
  }

  @override
  List<Object?> get props => [
        conversationId,
        status,
        messages,
        hasMore,
        isLoadingOlder,
        isSending,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
        otherLastReadAt,
      ];
}
