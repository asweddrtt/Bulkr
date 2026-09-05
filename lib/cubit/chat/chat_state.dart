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

  bool get isEmpty => messages.isEmpty;

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
      ];
}
