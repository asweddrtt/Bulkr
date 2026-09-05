import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/notification_repository.dart';
import '../../models/app_notification.dart';

part 'notifications_state.dart';

/// The notifications list, and the badge that counts it.
///
/// App-wide, like [ConversationsCubit] and for the same reason: the dot on the
/// feed header and the screen behind it must be the same list, or they will
/// disagree the moment one of them refreshes.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({required NotificationRepository repository})
      : _repository = repository,
        super(const NotificationsState());

  final NotificationRepository _repository;

  /// Reads the badge without reading the list.
  ///
  /// What the feed header calls on launch and on resume. One count, not a
  /// screenful of joins, for a number that only moves a dot.
  Future<void> refreshBadge() async {
    final int unread = await _repository.unreadCount();
    if (isClosed) return;

    // Only the count. The list, if one has been loaded, stays as it was — this
    // is a cheaper question than "what are they", and answering it must not
    // quietly invalidate the more expensive answer.
    emit(state.copyWith(unreadCount: unread));
  }

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(
        status: NotificationsStatus.loading,
        clearError: true,
      ));
    }

    try {
      final List<AppNotification> items = await _repository.fetch();
      if (isClosed) return;

      emit(state.copyWith(
        status: NotificationsStatus.ready,
        items: items,
        unreadCount: items.where((item) => item.isUnread).length,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: notifications failed to load — $detail');

      if (silent && state.status == NotificationsStatus.ready) return;

      emit(state.copyWith(
        status: NotificationsStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Marks everything read, on screen first.
  ///
  /// Optimistic, unlike most writes in this app, because the cost of being
  /// wrong is a badge that comes back on the next refresh — and the alternative
  /// is a list that stays bold for half a second after the user has plainly
  /// seen it.
  Future<void> markAllRead() async {
    if (state.unreadCount == 0) return;

    final NotificationsState before = state;

    emit(state.copyWith(
      items: state.items.map((item) => item.asRead()).toList(),
      unreadCount: 0,
    ));

    try {
      await _repository.markAllRead();
    } catch (error) {
      if (isClosed) return;
      debugPrint('Bulkr: could not mark notifications read — $error');
      emit(before);
    }
  }

  /// Throws the list away.
  Future<void> clearAll() async {
    final NotificationsState before = state;

    emit(state.copyWith(
      status: NotificationsStatus.ready,
      items: const [],
      unreadCount: 0,
    ));

    try {
      await _repository.clearAll();
    } catch (error) {
      if (isClosed) return;
      debugPrint('Bulkr: could not clear notifications — $error');
      emit(before.copyWith(
        actionErrorKey: 'notifications_clear_failed',
      ));
    }
  }

  void clearActionError() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearActionError: true));
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.code, error.message].whereType<String>().join(' · ');
    }
    return error.toString();
  }
}
