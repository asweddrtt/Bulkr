import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

/// Follows, likes and comments, as a list.
///
/// Direct messages are not in here on purpose: they have their own inbox with
/// its own unread counts, and one message producing both a thread badge and a
/// notification row would be one event announced twice.
class NotificationRepository {
  NotificationRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// How many the screen holds. Notifications are a recent-events list, not an
  /// archive — nobody pages back through six months of likes — so this is a
  /// cap rather than a page size, and there is no cursor.
  static const int pageSize = 50;

  String? get _userId => _client.auth.currentUser?.id;

  /// The list, newest first.
  ///
  /// Rows whose `kind` this build does not recognise are dropped rather than
  /// rendered as a blank line: a newer server can add a kind, and an old client
  /// should quietly not show it.
  Future<List<AppNotification>> fetch() async {
    if (_userId == null) return const <AppNotification>[];

    final Object? result = await _client.rpc(
      'notification_feed',
      params: {'p_limit': pageSize},
    );

    if (result is! List) return const <AppNotification>[];

    return result
        .whereType<Map<String, dynamic>>()
        .map(AppNotification.fromRow)
        .whereType<AppNotification>()
        .toList();
  }

  /// Marks everything currently unread as read.
  ///
  /// All of them, not the ones on screen: opening the list is the act of
  /// having seen them, and leaving some unread because they were below the
  /// fold would make the badge disagree with what the user just did.
  ///
  /// `read_at` is the only column granted to `authenticated` on this table, so
  /// this is also the only edit anyone can make to a notification.
  Future<void> markAllRead() async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', userId)
        .isFilter('read_at', null);
  }

  /// Clears the whole list.
  ///
  /// A real delete, because there is nothing behind a notification worth
  /// keeping — the follow, the like and the comment all still exist in their
  /// own tables. This only throws away the record of having been told.
  Future<void> clearAll() async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client.from('notifications').delete().eq('user_id', userId);
  }

  /// How many are unread, for the badge.
  ///
  /// A count, not a fetch — the badge needs a number and the rows are a
  /// screenful of joins. Zero on failure, including the migration not having
  /// been run: a badge is not worth an error state, and zero is what an
  /// unreachable server looks like anyway.
  Future<int> unreadCount() async {
    final String? userId = _userId;
    if (userId == null) return 0;

    try {
      final int count = await _client
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', userId)
          .isFilter('read_at', null);

      return count;
    } catch (error) {
      debugPrint('Bulkr: notification count unavailable — $error');
      return 0;
    }
  }
}
