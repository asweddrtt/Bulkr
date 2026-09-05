part of 'notifications_cubit.dart';

enum NotificationsStatus { initial, loading, ready, failure }

class NotificationsState extends Equatable {
  const NotificationsState({
    this.status = NotificationsStatus.initial,
    this.items = const [],
    this.unreadCount = 0,
    this.errorMessage,
    this.actionErrorKey,
  });

  final NotificationsStatus status;
  final List<AppNotification> items;

  /// Kept separately from `items.where(isUnread).length` on purpose: the badge
  /// is refreshed on its own, by a count query, without the list ever being
  /// loaded. Deriving it from an empty list would show zero for someone who
  /// has never opened the screen.
  final int unreadCount;

  final String? errorMessage;

  /// Translation key for a write that failed, cleared once shown.
  final String? actionErrorKey;

  bool get isEmpty => items.isEmpty;

  bool get hasUnread => unreadCount > 0;

  NotificationsState copyWith({
    NotificationsStatus? status,
    List<AppNotification>? items,
    int? unreadCount,
    String? errorMessage,
    bool clearError = false,
    String? actionErrorKey,
    bool clearActionError = false,
  }) {
    return NotificationsState(
      status: status ?? this.status,
      items: items ?? this.items,
      unreadCount: unreadCount ?? this.unreadCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorKey:
          clearActionError ? null : (actionErrorKey ?? this.actionErrorKey),
    );
  }

  @override
  List<Object?> get props =>
      [status, items, unreadCount, errorMessage, actionErrorKey];
}
