import 'package:bulkr/models/app_notification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row(Map<String, dynamic> extra) => {
        'id': 'n1',
        'kind': 'like',
        'created_at': '2026-01-02T10:00:00Z',
        ...extra,
      };

  group('AppNotification.fromRow', () {
    test('reads a row from notification_feed()', () {
      final AppNotification? item = AppNotification.fromRow(row({
        'kind': 'reply',
        'actor_id': 'u2',
        'actor_username': 'ali',
        'actor_display_name': 'Ali H',
        'post_id': 'p1',
        'post_excerpt': 'week 4 update',
        'comment_id': 'c1',
        'comment_excerpt': 'same here',
      }));

      expect(item, isNotNull);
      expect(item!.kind, NotificationKind.reply);
      expect(item.actorName, 'Ali H');
      expect(item.isUnread, isTrue);
      // The comment wins over the post: a reply is about what was said.
      expect(item.detail, 'same here');
    });

    // A newer server can add a kind. An older client should quietly not show
    // it rather than render a blank line or crash on an enum lookup.
    test('drops a kind this build does not know', () {
      expect(AppNotification.fromRow(row({'kind': 'reaction'})), isNull);
      expect(AppNotification.fromRow(row({'kind': null})), isNull);
    });

    // The actor's account going away must not rewrite the history of what
    // happened to everyone else — the row survives them.
    test('survives a deleted actor', () {
      final AppNotification item = AppNotification.fromRow(row({
        'actor_id': null,
        'post_excerpt': 'week 4 update',
      }))!;

      expect(item.hasActor, isFalse);
      expect(item.actorName, '');
      expect(item.detail, 'week 4 update');
    });

    test('read_at makes it read', () {
      final AppNotification item = AppNotification.fromRow(row({
        'read_at': '2026-01-02T11:00:00Z',
      }))!;

      expect(item.isUnread, isFalse);
    });

    test('a follow has no detail line, because there is nothing to show', () {
      final AppNotification item =
          AppNotification.fromRow(row({'kind': 'follow'}))!;

      expect(item.kind, NotificationKind.follow);
      expect(item.detail, isNull);
    });

    test('an empty excerpt is no detail', () {
      final AppNotification item = AppNotification.fromRow(row({
        'post_excerpt': '   ',
        'comment_excerpt': '',
      }))!;

      expect(item.detail, isNull);
    });

    test('asRead marks without disturbing anything else', () {
      final AppNotification item = AppNotification.fromRow(row({
        'actor_display_name': 'Ali',
        'post_excerpt': 'week 4',
      }))!;

      final AppNotification read = item.asRead();

      expect(read.isUnread, isFalse);
      expect(read.actorName, 'Ali');
      expect(read.detail, 'week 4');
      expect(read.id, item.id);
    });

    test('every kind maps to a message key', () {
      for (final NotificationKind kind in NotificationKind.values) {
        expect(NotificationKind.fromDb(kind.dbValue), kind);
        expect(kind.messageKey, isNotEmpty);
      }
    });
  });
}
