import 'package:equatable/equatable.dart';

/// One row of the conversation list.
///
/// Not a `conversations` row — it is what `public.conversation_summaries()`
/// returns: the thread, who else is in it, the last thing said, and how much
/// of it is unread. That function exists because assembling this client-side
/// would be one request per thread.
class Conversation extends Equatable {
  const Conversation({
    required this.id,
    required this.lastMessageAt,
    this.otherId,
    this.otherUsername,
    this.otherDisplayName,
    this.otherAvatarUrl,
    this.lastBody,
    this.lastSenderId,
    this.unreadCount = 0,
  });

  final String id;
  final DateTime lastMessageAt;

  /// The other person. Null when they have deleted their account — the thread
  /// and its history stay, which is why every one of these is nullable.
  final String? otherId;
  final String? otherUsername;
  final String? otherDisplayName;
  final String? otherAvatarUrl;

  final String? lastBody;
  final String? lastSenderId;

  final int unreadCount;

  bool get hasUnread => unreadCount > 0;

  /// Whether the last thing said was said by this user, so the list can mark
  /// it — "you: on my way" reads differently from "on my way".
  bool isLastFromMe(String? currentUserId) =>
      currentUserId != null && lastSenderId == currentUserId;

  /// What to call them. Falls through display name, handle, then a placeholder
  /// for somebody who is gone.
  String get otherName {
    final String? display = otherDisplayName?.trim();
    if (display != null && display.isNotEmpty) return display;

    final String? handle = otherUsername?.trim();
    if (handle != null && handle.isNotEmpty) return handle;

    return '';
  }

  bool get otherIsGone => otherId == null;

  /// This conversation with its badge cleared, for the moment it is opened.
  Conversation withoutUnread() => Conversation(
        id: id,
        lastMessageAt: lastMessageAt,
        otherId: otherId,
        otherUsername: otherUsername,
        otherDisplayName: otherDisplayName,
        otherAvatarUrl: otherAvatarUrl,
        lastBody: lastBody,
        lastSenderId: lastSenderId,
      );

  factory Conversation.fromRow(Map<String, dynamic> row) => Conversation(
        id: '${row['conversation_id']}',
        lastMessageAt: DateTime.tryParse('${row['last_message_at']}')?.toLocal() ??
            DateTime.now(),
        otherId: row['other_id'] as String?,
        otherUsername: row['other_username'] as String?,
        otherDisplayName: row['other_display_name'] as String?,
        otherAvatarUrl: row['other_avatar_url'] as String?,
        lastBody: row['last_body'] as String?,
        lastSenderId: row['last_sender_id'] as String?,
        unreadCount: _asInt(row['unread_count']),
      );

  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse('${raw ?? ''}'.trim()) ?? 0;
  }

  @override
  List<Object?> get props => [
        id,
        lastMessageAt,
        otherId,
        otherUsername,
        otherDisplayName,
        otherAvatarUrl,
        lastBody,
        lastSenderId,
        unreadCount,
      ];
}
