import 'package:bulkr/models/chat_message.dart';
import 'package:bulkr/models/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Conversation.fromRow', () {
    test('reads a summary row', () {
      final Conversation conversation = Conversation.fromRow({
        'conversation_id': 'c1',
        'last_message_at': '2026-01-02T10:00:00Z',
        'other_id': 'u2',
        'other_username': 'ali',
        'other_display_name': 'Ali H',
        'other_avatar_url': 'https://example.com/a.jpg',
        'last_body': 'on my way',
        'last_sender_id': 'u2',
        'unread_count': 3,
      });

      expect(conversation.id, 'c1');
      expect(conversation.otherName, 'Ali H');
      expect(conversation.unreadCount, 3);
      expect(conversation.hasUnread, isTrue);
      expect(conversation.otherIsGone, isFalse);
      expect(conversation.isLastFromMe('u1'), isFalse);
      expect(conversation.isLastFromMe('u2'), isTrue);
    });

    test('falls back to the handle, then to nothing', () {
      Conversation named(Map<String, dynamic> extra) => Conversation.fromRow({
            'conversation_id': 'c1',
            'last_message_at': '2026-01-02T10:00:00Z',
            ...extra,
          });

      expect(named({'other_username': 'ali'}).otherName, 'ali');
      expect(named({'other_display_name': '   '}).otherName, '');
    });

    // The other person deleting their account leaves the thread and its
    // history behind, so every column about them can come back null.
    test('survives a deleted account', () {
      final Conversation conversation = Conversation.fromRow({
        'conversation_id': 'c1',
        'last_message_at': '2026-01-02T10:00:00Z',
        'other_id': null,
        'last_body': 'see you',
        'last_sender_id': null,
      });

      expect(conversation.otherIsGone, isTrue);
      expect(conversation.otherName, '');
      expect(conversation.unreadCount, 0);
      expect(conversation.isLastFromMe('u1'), isFalse);
    });

    // Postgres hands a count(*) back as a string through PostgREST often
    // enough that parsing it is not optional.
    test('accepts a count that arrives as text', () {
      final Conversation conversation = Conversation.fromRow({
        'conversation_id': 'c1',
        'last_message_at': '2026-01-02T10:00:00Z',
        'unread_count': '7',
      });

      expect(conversation.unreadCount, 7);
    });

    test('withoutUnread clears only the badge', () {
      final Conversation conversation = Conversation.fromRow({
        'conversation_id': 'c1',
        'last_message_at': '2026-01-02T10:00:00Z',
        'other_id': 'u2',
        'other_display_name': 'Ali',
        'last_body': 'hey',
        'unread_count': 4,
      }).withoutUnread();

      expect(conversation.unreadCount, 0);
      expect(conversation.otherName, 'Ali');
      expect(conversation.lastBody, 'hey');
    });
  });

  group('ChatMessage', () {
    test('knows which side it belongs on', () {
      final ChatMessage mine = ChatMessage.fromRow(
        {
          'id': 'm1',
          'conversation_id': 'c1',
          'sender_id': 'u1',
          'body': 'hello',
          'created_at': '2026-01-02T10:00:00Z',
        },
        currentUserId: 'u1',
      );

      expect(mine.isMine, isTrue);
      expect(mine.isPending, isFalse);
      expect(mine.body, 'hello');

      final ChatMessage theirs = ChatMessage.fromRow(
        {
          'id': 'm2',
          'conversation_id': 'c1',
          'sender_id': 'u2',
          'body': 'hi',
          'created_at': '2026-01-02T10:01:00Z',
        },
        currentUserId: 'u1',
      );

      expect(theirs.isMine, isFalse);
    });

    // A message drawn before the server has one is marked, so the bubble can
    // dim it and unsend can refuse it — there is no row to delete yet.
    test('a pending message is marked as such', () {
      final ChatMessage pending = ChatMessage.pending(
        conversationId: 'c1',
        senderId: 'u1',
        body: 'sending',
      );

      expect(pending.isPending, isTrue);
      expect(pending.isMine, isTrue);
    });
  });
}
