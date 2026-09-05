import 'package:equatable/equatable.dart';

/// One message in a conversation.
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    this.senderId,
    this.isMine = false,
    this.isPending = false,
  });

  final String id;
  final String conversationId;
  final String body;
  final DateTime createdAt;

  /// Null when the sender has deleted their account. `messages.sender_id` is
  /// ON DELETE SET NULL, so what they said survives them — the name beside it
  /// is what goes.
  final String? senderId;

  final bool isMine;

  /// Written locally and not yet acknowledged by the server.
  ///
  /// Sending is optimistic: a message that waits for a round trip before
  /// appearing makes a conversation feel like email. The bubble renders dimmed
  /// until the real row arrives over the realtime channel and replaces it.
  final bool isPending;

  ChatMessage copyWith({bool? isPending}) => ChatMessage(
        id: id,
        conversationId: conversationId,
        body: body,
        createdAt: createdAt,
        senderId: senderId,
        isMine: isMine,
        isPending: isPending ?? this.isPending,
      );

  /// A message drawn before the server has one.
  ///
  /// The id is local and prefixed so it can never collide with a uuid from the
  /// server, which is what lets the real row replace this one by id when it
  /// arrives — over the realtime channel or as the insert's own return,
  /// whichever gets there first.
  factory ChatMessage.pending({
    required String conversationId,
    required String? senderId,
    required String body,
  }) {
    return ChatMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      body: body,
      createdAt: DateTime.now(),
      senderId: senderId,
      isMine: true,
      isPending: true,
    );
  }

  factory ChatMessage.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
  }) {
    final String? senderId = row['sender_id'] as String?;

    return ChatMessage(
      id: '${row['id']}',
      conversationId: '${row['conversation_id']}',
      body: '${row['body'] ?? ''}',
      createdAt:
          DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
      senderId: senderId,
      isMine: currentUserId != null && senderId == currentUserId,
    );
  }

  @override
  List<Object?> get props =>
      [id, conversationId, body, createdAt, senderId, isMine, isPending];
}
