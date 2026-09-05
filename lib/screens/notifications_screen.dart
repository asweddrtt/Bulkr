import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/relative_time.dart';
import '../cubit/notifications/notifications_cubit.dart';
import '../models/app_notification.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/person_row.dart';
import 'author_profile_screen.dart';

/// Follows, likes and comments.
///
/// Everything social in the app used to be invisible unless you went looking
/// for it — somebody follows you and the only way to find out was to open the
/// right screen. This is the screen that says so.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  static Future<void> open(BuildContext context) {
    final NotificationsCubit cubit = context.read<NotificationsCubit>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: const NotificationsScreen(),
        ),
      ),
    );
  }

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();

    final NotificationsCubit cubit = context.read<NotificationsCubit>();

    // Silent when there is already a list: reopening should not blank what is
    // there to fetch the same thing again.
    cubit.load(silent: cubit.state.status == NotificationsStatus.ready);

    // Opening the screen is the act of having seen them. Marking read here
    // rather than on the way out means the badge clears while the user is
    // looking at what cleared it.
    cubit.markAllRead();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'notifications_title'.tr().toUpperCase(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 17.sp,
            letterSpacing: 1,
          ),
        ),
        actions: [
          BlocBuilder<NotificationsCubit, NotificationsState>(
            buildWhen: (previous, current) =>
                previous.isEmpty != current.isEmpty,
            builder: (context, state) {
              if (state.isEmpty) return const SizedBox.shrink();

              return TextButton(
                onPressed: () => _confirmClear(context),
                child: Text(
                  'notifications_clear'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<NotificationsCubit, NotificationsState>(
        listenWhen: (previous, current) =>
            previous.actionErrorKey != current.actionErrorKey &&
            current.actionErrorKey != null,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF2A2A2A),
                content: Text(
                  state.actionErrorKey!.tr(),
                  style:
                      GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
                ),
              ),
            );
          context.read<NotificationsCubit>().clearActionError();
        },
        builder: (context, state) {
          switch (state.status) {
            case NotificationsStatus.initial:
            case NotificationsStatus.loading:
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNeon),
              );

            case NotificationsStatus.failure:
              return _Notice(
                text: [
                  'notifications_failed'.tr(),
                  state.errorMessage,
                ].whereType<String>().join('\n\n'),
                onRetry: () => context.read<NotificationsCubit>().load(),
              );

            case NotificationsStatus.ready:
              return RefreshIndicator(
                color: AppColors.primaryNeon,
                backgroundColor: const Color(0xFF1A1A1A),
                onRefresh: () => context.read<NotificationsCubit>().refresh(),
                child: state.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: 0.28.sh),
                          _Notice(text: 'notifications_empty'.tr()),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
                        itemCount: state.items.length,
                        separatorBuilder: (_, __) => Divider(
                          color: AppColors.darkBorder,
                          height: 1,
                          thickness: 1,
                          indent: 48.w,
                        ),
                        itemBuilder: (_, index) => _NotificationTile(
                          key: ValueKey('notification-${state.items[index].id}'),
                          notification: state.items[index],
                        ),
                      ),
              );
          }
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final NotificationsCubit cubit = context.read<NotificationsCubit>();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        title: Text(
          'notifications_clear_title'.tr(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 15.sp,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'notifications_clear_body'.tr(),
          style: GoogleFonts.inter(
            color: AppColors.offWhiteMuted,
            fontSize: 12.sp,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'cancel'.tr().toUpperCase(),
              style:
                  GoogleFonts.inter(color: AppColors.textGray, fontSize: 12.sp),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'notifications_clear'.tr().toUpperCase(),
              style: GoogleFonts.inter(
                color: const Color(0xFFFF5722),
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) await cubit.clearAll();
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({super.key, required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final String name = notification.actorName.isEmpty
        ? 'notification_someone'.tr()
        : notification.actorName;

    final ({String key, Map<String, String>? args}) stamp =
        RelativeTime.stamp(notification.createdAt);

    final String? detail = notification.detail;

    return PressScale(
      enabled: notification.hasActor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Every kind of notification is about a person, and a person is the
        // one destination all four have in common. A like and a comment are
        // also about a post, but there is no screen that opens one post on its
        // own — the feed is a list — so sending someone to a dead end would be
        // worse than sending them to the profile they can act on.
        onTap: notification.hasActor
            ? () => AuthorProfileScreen.open(context, notification.actorId!)
            : null,
        child: Container(
          // Unread is carried by a wash behind the row rather than by a dot:
          // the list is read by scanning, and a tinted block is visible without
          // being looked for.
          color: notification.isUnread
              ? AppColors.primaryNeon.withValues(alpha: 0.06)
              : Colors.transparent,
          padding: EdgeInsets.symmetric(vertical: 12.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  PersonAvatar(
                    url: notification.actorAvatarUrl,
                    name: name,
                    size: 38.w,
                  ),
                  Positioned(
                    right: -2.w,
                    bottom: -2.h,
                    child: Container(
                      padding: EdgeInsets.all(3.w),
                      decoration: const BoxDecoration(
                        color: Color(0xFF121212),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _iconFor(notification.kind),
                        size: 11.sp,
                        color: AppColors.primaryNeon,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.kind.messageKey.tr(namedArgs: {'name': name}),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12.sp,
                        height: 1.4,
                      ),
                    ),
                    if (detail != null) ...[
                      SizedBox(height: 3.h),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textGray,
                          fontSize: 11.sp,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                stamp.key.tr(namedArgs: stamp.args),
                style: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 10.sp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(NotificationKind kind) {
    switch (kind) {
      case NotificationKind.follow:
        return Icons.person_add_alt_1_rounded;
      case NotificationKind.like:
        return Icons.favorite_rounded;
      case NotificationKind.comment:
        return Icons.mode_comment_rounded;
      case NotificationKind.reply:
        return Icons.reply_rounded;
    }
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppColors.textGray,
                fontSize: 12.sp,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: 18.h),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.darkBorder),
                ),
                child: Text(
                  'retry'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
