import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/conversations/conversations_cubit.dart';
import '../data/chat_repository.dart';
import '../models/conversation.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/person_row.dart';
import 'chat_screen.dart';

/// The inbox.
///
/// Reads from [ConversationsCubit], which is provided app-wide rather than
/// here — the unread badge in the feed header needs the same numbers, and two
/// cubits counting the same threads would disagree the moment one of them
/// refreshed.
class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  /// Opens the inbox, reloading it on the way in.
  ///
  /// The list is kept alive between visits so the badge stays warm, which
  /// means what is on screen when it opens is as old as the last refresh. The
  /// reload is silent for that reason: there are rows to show already, and
  /// blanking them to a spinner would be throwing away good data to look busy.
  static Future<void> open(BuildContext context) {
    final ConversationsCubit cubit = context.read<ConversationsCubit>();
    final ChatRepository chat = context.read<ChatRepository>();

    cubit.refresh();

    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: chat,
          child: BlocProvider.value(
            value: cubit,
            child: const ConversationsScreen(),
          ),
        ),
      ),
    );
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
          'chat_inbox_title'.tr().toUpperCase(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 17.sp,
            letterSpacing: 1,
          ),
        ),
      ),
      body: BlocBuilder<ConversationsCubit, ConversationsState>(
        builder: (context, state) {
          switch (state.status) {
            case ConversationsStatus.initial:
            case ConversationsStatus.loading:
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNeon),
              );

            case ConversationsStatus.failure:
              return _Notice(
                text: [
                  'chat_inbox_failed'.tr(),
                  state.errorMessage,
                ].whereType<String>().join('\n\n'),
                onRetry: () => context.read<ConversationsCubit>().load(),
              );

            case ConversationsStatus.ready:
              return RefreshIndicator(
                color: AppColors.primaryNeon,
                backgroundColor: const Color(0xFF1A1A1A),
                onRefresh: () => context.read<ConversationsCubit>().refresh(),
                child: state.isEmpty
                    // Still a scroll view, so the empty state can be pulled to
                    // refresh like the full one. An inbox that cannot be
                    // refreshed until it has something in it is exactly
                    // backwards.
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: 0.28.sh),
                          _Notice(text: 'chat_inbox_empty'.tr()),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
                        itemCount: state.conversations.length,
                        separatorBuilder: (_, __) => Divider(
                          color: AppColors.darkBorder,
                          height: 1,
                          thickness: 1,
                          indent: 54.w,
                        ),
                        itemBuilder: (_, index) {
                          final Conversation conversation =
                              state.conversations[index];
                          return _ConversationTile(
                            key: ValueKey('thread-${conversation.id}'),
                            conversation: conversation,
                          );
                        },
                      ),
              );
          }
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({super.key, required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final ChatRepository chat = context.read<ChatRepository>();
    final String? currentUserId = chat.currentUserId;
    final bool unread = conversation.hasUnread;

    // Somebody who deleted their account leaves the thread behind. It still
    // opens — the history is the user's own as much as it was theirs — so the
    // row says who is missing rather than showing a blank name.
    final String name = conversation.otherIsGone
        ? 'chat_person_gone'.tr()
        : (conversation.otherName.isEmpty
            ? 'chat_person_gone'.tr()
            : conversation.otherName);

    return PressScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(
          context,
          chat: chat,
          currentUserId: currentUserId,
          name: name,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          child: Row(
            children: [
              PersonAvatar(
                url: conversation.otherAvatarUrl,
                name: name,
                size: 44.w,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          _stamp(conversation.lastMessageAt),
                          style: GoogleFonts.inter(
                            color: unread
                                ? AppColors.primaryNeon
                                : AppColors.textGray,
                            fontSize: 10.sp,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 3.h),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _preview(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              // Unread is carried by weight and colour rather
                              // than by the badge alone — the badge is a
                              // number, and the line being brighter is what
                              // you actually see scanning the list.
                              color: unread
                                  ? Colors.white
                                  : AppColors.offWhiteMuted,
                              fontSize: 12.sp,
                              fontWeight:
                                  unread ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          SizedBox(width: 8.w),
                          _UnreadBadge(count: conversation.unreadCount),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _preview(BuildContext context) {
    final String? body = conversation.lastBody?.trim();
    if (body == null || body.isEmpty) return 'chat_inbox_no_messages'.tr();

    final ChatRepository chat = context.read<ChatRepository>();
    if (!conversation.isLastFromMe(chat.currentUserId)) return body;

    return 'chat_inbox_from_you'.tr(namedArgs: {'body': body});
  }

  Future<void> _open(
    BuildContext context, {
    required ChatRepository chat,
    required String? currentUserId,
    required String name,
  }) async {
    final ConversationsCubit cubit = context.read<ConversationsCubit>();
    final NavigatorState navigator = Navigator.of(context);

    // Zeroed before the thread opens rather than after it closes: the badge
    // behind the screen you are reading should not still be counting the
    // messages on it.
    cubit.markSeen(conversation.id);

    await ChatScreen.open(
      navigator: navigator,
      chat: chat,
      conversationId: conversation.id,
      currentUserId: currentUserId,
      title: name,
      otherId: conversation.otherId,
      avatarUrl: conversation.otherAvatarUrl,
    );

    // Whatever was said while the thread was open belongs in the list too.
    await cubit.refresh();
  }

  /// A time today, a weekday this week, a date before that.
  ///
  /// The same ladder every messaging app uses, and for the same reason: the
  /// older something is the less precisely you need to know when it was.
  static String _stamp(DateTime at) {
    final DateTime now = DateTime.now();
    final Duration since = now.difference(at);

    if (since.inDays == 0 && now.day == at.day) {
      return DateFormat.Hm().format(at);
    }
    if (since.inDays < 7) return DateFormat.E().format(at);
    return DateFormat.yMd().format(at);
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Past a point the exact number stops being information and starts being
    // a wide badge.
    final String label = count > 99 ? '99+' : '$count';

    return Container(
      constraints: BoxConstraints(minWidth: 18.w),
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryNeon,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: Colors.black,
          fontSize: 9.sp,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
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
