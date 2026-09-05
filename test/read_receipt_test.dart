import 'package:bulkr/cubit/chat/chat_cubit.dart';
import 'package:bulkr/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

ChatMessage msg({
  required String id,
  required bool mine,
  required DateTime at,
  bool pending = false,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'c1',
    body: id,
    createdAt: at,
    senderId: mine ? 'u1' : 'u2',
    isMine: mine,
    isPending: pending,
  );
}

void main() {
  final DateTime t0 = DateTime(2026, 1, 2, 10);

  group('ChatState.lastSeenMessage', () {
    test('is nothing until the other person has read anything', () {
      final ChatState state = ChatState(
        conversationId: 'c1',
        messages: [msg(id: 'm1', mine: true, at: t0)],
      );

      expect(state.lastSeenMessage, isNull);
    });

    test('is my newest message once they have read past it', () {
      final ChatState state = ChatState(
        conversationId: 'c1',
        messages: [
          msg(id: 'm1', mine: true, at: t0),
          msg(id: 'm2', mine: true, at: t0.add(const Duration(minutes: 1))),
        ],
        otherLastReadAt: t0.add(const Duration(minutes: 2)),
      );

      expect(state.lastSeenMessage?.id, 'm2');
    });

    // The receipt is about the last thing I said. If I have said something
    // since they looked, there is nothing to mark — not even on the older
    // message they did read, because a tick halfway up a thread reads as an
    // error rather than as history.
    test('is nothing when my newest message is younger than their read', () {
      final ChatState state = ChatState(
        conversationId: 'c1',
        messages: [
          msg(id: 'm1', mine: true, at: t0),
          msg(id: 'm2', mine: true, at: t0.add(const Duration(minutes: 5))),
        ],
        otherLastReadAt: t0.add(const Duration(minutes: 1)),
      );

      expect(state.lastSeenMessage, isNull);
    });

    test('ignores their messages when looking for mine', () {
      final ChatState state = ChatState(
        conversationId: 'c1',
        messages: [
          msg(id: 'm1', mine: true, at: t0),
          msg(id: 'm2', mine: false, at: t0.add(const Duration(minutes: 1))),
        ],
        otherLastReadAt: t0.add(const Duration(minutes: 2)),
      );

      expect(state.lastSeenMessage?.id, 'm1');
    });

    // A pending message has not reached the server, so it cannot have been
    // read — marking it seen would be the worst possible lie for this feature.
    test('never marks a pending message as seen', () {
      final ChatState state = ChatState(
        conversationId: 'c1',
        messages: [
          msg(id: 'm1', mine: true, at: t0),
          msg(
            id: 'pending-1',
            mine: true,
            at: t0.add(const Duration(minutes: 1)),
            pending: true,
          ),
        ],
        otherLastReadAt: t0.add(const Duration(minutes: 2)),
      );

      expect(state.lastSeenMessage?.id, 'm1');
    });

    test('is nothing in a thread where I have said nothing', () {
      final ChatState state = ChatState(
        conversationId: 'c1',
        messages: [msg(id: 'm1', mine: false, at: t0)],
        otherLastReadAt: t0.add(const Duration(minutes: 1)),
      );

      expect(state.lastSeenMessage, isNull);
    });
  });
}
