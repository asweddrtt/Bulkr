import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/chat/chat_cubit.dart';
import '../data/chat_repository.dart';
import '../models/chat_message.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/person_row.dart';
import 'author_profile_screen.dart';

/// One conversation.
class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.title,
    this.otherId,
    this.avatarUrl,
  });

  final String title;
  final String? otherId;
  final String? avatarUrl;

  /// Opens a thread with [personId], creating it if there is not one.
  ///
  /// The round trip happens before the route is pushed, so a failure — a
  /// block, most likely — reports itself where the user is rather than on a
  /// screen that then has to explain why it is empty.
  static Future<void> openWith(
    BuildContext context, {
    required String personId,
    required String name,
    String? avatarUrl,
  }) async {
    final ChatRepository chat = context.read<ChatRepository>();
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    String conversationId;
    try {
      conversationId = await chat.openDirect(personId);
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A2A2A),
            content: Text(
              'chat_unavailable'.tr(),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
            ),
          ),
        );
      return;
    }

    await open(
      navigator: navigator,
      chat: chat,
      conversationId: conversationId,
      currentUserId: chat.currentUserId,
      title: name,
      otherId: personId,
      avatarUrl: avatarUrl,
    );
  }

  /// Opens a thread that already exists.
  static Future<void> open({
    required NavigatorState navigator,
    required ChatRepository chat,
    required String conversationId,
    required String? currentUserId,
    required String title,
    String? otherId,
    String? avatarUrl,
  }) {
    return navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: chat,
          child: BlocProvider(
            create: (_) => ChatCubit(
              chatRepository: chat,
              conversationId: conversationId,
              currentUserId: currentUserId,
            )..load(),
            child: ChatScreen(
              title: title,
              otherId: otherId,
              avatarUrl: avatarUrl,
            ),
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
        titleSpacing: 0,
        title: PressScale(
          enabled: otherId != null,
          child: GestureDetector(
            onTap: otherId == null
                ? null
                : () => AuthorProfileScreen.open(context, otherId!),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                PersonAvatar(url: avatarUrl, name: title, size: 30.w),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.anton(
                      color: Colors.white,
                      fontSize: 16.sp,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: BlocListener<ChatCubit, ChatState>(
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
                  [state.actionErrorKey!.tr(), state.actionErrorDetail]
                      .whereType<String>()
                      .join('\n'),
                  style:
                      GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
                ),
              ),
            );
          context.read<ChatCubit>().clearActionError();
        },
        child: Column(
          children: [
            const Expanded(child: _Thread()),
            const _Composer(),
          ],
        ),
      ),
    );
  }
}

class _Thread extends StatefulWidget {
  const _Thread();

  @override
  State<_Thread> createState() => _ThreadState();
}

class _ThreadState extends State<_Thread> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  /// The list is reversed, so "older" is further down the scroll extent rather
  /// than up it — which is what makes a chat load backwards while reading
  /// forwards.
  void _onScroll() {
    if (!_controller.hasClients) return;
    final ScrollPosition position = _controller.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    context.read<ChatCubit>().loadOlder();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        switch (state.status) {
          case ChatStatus.initial:
          case ChatStatus.loading:
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            );

          case ChatStatus.failure:
            return _Notice(
              text: [
                'chat_load_failed'.tr(),
                state.errorMessage,
              ].whereType<String>().join('\n\n'),
              onRetry: () => context.read<ChatCubit>().load(),
            );

          case ChatStatus.ready:
            if (state.isEmpty) return _Notice(text: 'chat_empty'.tr());

            // Reversed, so the newest message is at the bottom and the list
            // stays pinned there as messages arrive — the alternative is a
            // scroll position that jumps every time somebody types.
            final List<ChatMessage> newestFirst =
                state.messages.reversed.toList();

            return ListView.builder(
              controller: _controller,
              reverse: true,
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
              itemCount: newestFirst.length + (state.isLoadingOlder ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= newestFirst.length) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: AppColors.primaryNeon,
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  );
                }

                final ChatMessage message = newestFirst[index];

                return _Bubble(
                  message: message,
                  // Only under the last one they have seen. Read receipts are
                  // cumulative — opening a thread reads everything above — so
                  // a column of identical ticks would say nothing this one
                  // does not.
                  isSeen: state.lastSeenMessage?.id == message.id,
                );
              },
            );
        }
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.isSeen = false});

  final ChatMessage message;

  /// This is the newest message the other person has read. Drawn as a line
  /// under the bubble rather than as a tick inside it: the receipt is about
  /// the conversation reaching them, not about the words.
  final bool isSeen;

  @override
  Widget build(BuildContext context) {
    final bool mine = message.isMine;

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        _bubble(context, mine),
        if (isSeen)
          Padding(
            padding: EdgeInsets.only(top: 2.h, right: 4.w, bottom: 2.h),
            child: Text(
              'chat_seen'.tr(),
              style: GoogleFonts.inter(
                color: AppColors.textGray,
                fontSize: 9.sp,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bubble(BuildContext context, bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // Long press rather than a tap: a bubble is text to be read, and a tap
        // target that removes it would be one mis-tap from deleting what you
        // said.
        onLongPress:
            mine && !message.isPending ? () => _unsend(context, message) : null,
        child: Container(
          constraints: BoxConstraints(maxWidth: 0.72.sw),
          margin: EdgeInsets.symmetric(vertical: 3.h),
          padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 9.h),
          decoration: BoxDecoration(
            color: mine
                ? AppColors.primaryNeon.withValues(
                    // Dimmed while it is still only on this device.
                    alpha: message.isPending ? 0.45 : 1,
                  )
                : const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14.r),
              topRight: Radius.circular(14.r),
              bottomLeft: Radius.circular(mine ? 14.r : 4.r),
              bottomRight: Radius.circular(mine ? 4.r : 14.r),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message.body,
                style: GoogleFonts.inter(
                  color: mine ? Colors.black : Colors.white,
                  fontSize: 13.sp,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                DateFormat.Hm().format(message.createdAt),
                style: GoogleFonts.inter(
                  color: mine
                      ? Colors.black.withValues(alpha: 0.55)
                      : AppColors.textGray,
                  fontSize: 9.sp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _unsend(BuildContext context, ChatMessage message) async {
    final ChatCubit cubit = context.read<ChatCubit>();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        title: Text(
          'chat_unsend_title'.tr(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 15.sp,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'chat_unsend_body'.tr(),
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
              'chat_unsend_action'.tr().toUpperCase(),
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

    if (confirmed == true) await cubit.unsend(message);
  }
}

class _Composer extends StatefulWidget {
  const _Composer();

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty;

  void _send() {
    if (!_canSend) return;
    final String body = _controller.text;
    // Cleared before the await, not after: the message is already on screen
    // optimistically, and a field that stays full while it sends invites a
    // second send of the same thing.
    _controller.clear();
    context.read<ChatCubit>().send(body);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E0E),
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.sp,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 11.h),
                    hintText: 'chat_hint'.tr(),
                    hintStyle: GoogleFonts.inter(
                      color: AppColors.textGray,
                      fontSize: 13.sp,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            PressScale(
              enabled: _canSend,
              child: GestureDetector(
                onTap: _send,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 40.w,
                  height: 40.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _canSend
                        ? AppColors.primaryNeon
                        : const Color(0xFF1F1F1F),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 20.sp,
                    color: _canSend ? Colors.black : AppColors.textGray,
                  ),
                ),
              ),
            ),
          ],
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
