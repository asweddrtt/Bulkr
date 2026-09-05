import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/conversations/conversations_cubit.dart';
import '../cubit/feed/feed_cubit.dart';
import '../cubit/meals/meals_cubit.dart';
import '../cubit/notifications/notifications_cubit.dart';
import '../core/post_link.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import '../widgets/bulkr_nav_bar.dart';
import '../widgets/animations/motion.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/post_actions_sheet.dart';
import '../widgets/post_card.dart';
import '../widgets/report_sheet.dart';
import '../widgets/post_label_chip.dart';
import 'author_profile_screen.dart';
import 'challenge_leaderboard_sheet.dart';
import 'group_screen.dart';
import 'conversations_screen.dart';
import 'notifications_screen.dart';
import 'search_screen.dart';
import 'post_comments_sheet.dart';
import 'post_composer_screen.dart';

/// The feed.
///
/// Two views over one table. **For You** is the people the user chose to hear
/// from, newest first. **Discover** is everything public, ranked by engagement
/// decayed by age. One label filter sits above both, because what someone wants
/// to read about is not a property of which feed they happen to be in.
class FeedScreen extends StatelessWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<FeedCubit, FeedState>(
          listenWhen: (previous, current) =>
              current.actionErrorKey != null &&
              previous.actionErrorKey != current.actionErrorKey,
          listener: (context, state) => _showNotice(
            context,
            state.actionErrorDetail ?? state.actionErrorKey!.tr(),
          ),
        ),
        // Kept separate from the failure listener rather than folded in behind
        // a flag: confusing the two means telling someone a failure went
        // through.
        BlocListener<FeedCubit, FeedState>(
          listenWhen: (previous, current) =>
              current.actionMessageKey != null &&
              previous.actionMessageKey != current.actionMessageKey,
          listener: (context, state) =>
              _showNotice(context, state.actionMessageKey!.tr()),
        ),
      ],
      child: Scaffold(
        // Transparent so the shell's background shows through: this screen
        // lives inside MainScreen's IndexedStack, and its own Scaffold exists
        // only to host the floating action button.
        backgroundColor: Colors.transparent,
        // Lifted clear of the shell's floating nav bar. This Scaffold is
        // nested inside MainScreen's and knows nothing about that bar, so
        // left alone it puts the button underneath the glass.
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: BulkrNavBar.fabInset),
          child: const _ComposeButton(),
        ),
        body: Column(
          children: [
            const _FeedHeader(),
            Expanded(
              child: BlocBuilder<FeedCubit, FeedState>(
                buildWhen: (previous, current) => previous.tab != current.tab,
                // IndexedStack, not a swap: each feed keeps its own scroll
                // position, so switching tabs and coming back does not throw
                // the reader back to the top of where they were.
                builder: (context, state) => IndexedStack(
                  index: state.tab.index,
                  children: const [
                    _FeedList(tab: FeedTab.forYou),
                    _FeedList(tab: FeedTab.discover),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2A2A2A),
          content: Text(
            message,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
          ),
        ),
      );
    context.read<FeedCubit>().clearNotice();
  }
}

/// Title, the two tabs, and the label filter. Always visible: the feed scrolls
/// underneath it, so changing filter never needs a scroll back to the top
/// first.
class _FeedHeader extends StatelessWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'feed_title'.tr().toUpperCase(),
                  style: GoogleFonts.anton(
                    fontSize: 26.sp,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const _FeedTabs(),
              const _BellButton(),
              const _InboxButton(),
              // One icon, not two. People and groups used to have one each,
              // which made the header a menu of the app's data model rather
              // than of what anyone wants to do — and "find the thing I am
              // thinking of" does not know which kind it is.
              PressScale(
                child: GestureDetector(
                  onTap: () => SearchScreen.open(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.only(left: 6.w),
                    child: Icon(
                      Icons.search,
                      color: AppColors.textGray,
                      size: 21.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        BlocBuilder<FeedCubit, FeedState>(
          buildWhen: (previous, current) => previous.label != current.label,
          builder: (context, state) => PostLabelFilterBar(
            selected: state.label,
            onSelected: (label) => context.read<FeedCubit>().selectLabel(label),
          ),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }
}

/// Follows, likes and comments.
///
/// Stateful only to kick the first badge read, the same way [_InboxButton] is:
/// [NotificationsCubit] lives above the router and is lazy, so the first
/// signed-in screen has to ask it once. This asks for the *count* rather than
/// the list — one number for a dot, not a screenful of joins for a screen
/// nobody has opened.
class _BellButton extends StatefulWidget {
  const _BellButton();

  @override
  State<_BellButton> createState() => _BellButtonState();
}

class _BellButtonState extends State<_BellButton> {
  @override
  void initState() {
    super.initState();
    context.read<NotificationsCubit>().refreshBadge();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (previous, current) =>
          previous.hasUnread != current.hasUnread,
      builder: (context, state) {
        return PressScale(
          child: GestureDetector(
            onTap: () => NotificationsScreen.open(context),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(left: 10.w),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.textGray,
                    size: 21.sp,
                  ),
                  if (state.hasUnread)
                    Positioned(
                      top: -1.h,
                      right: 0,
                      child: Container(
                        width: 8.w,
                        height: 8.w,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryNeon,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The way into direct messages, with a count of what is waiting.
///
/// Stateful only to kick the first load: [ConversationsCubit] lives above the
/// router and is deliberately lazy, so something signed-in has to ask it for
/// the list once. The feed is the first signed-in screen anybody sees, which
/// makes it the honest place to do that.
class _InboxButton extends StatefulWidget {
  const _InboxButton();

  @override
  State<_InboxButton> createState() => _InboxButtonState();
}

class _InboxButtonState extends State<_InboxButton> {
  @override
  void initState() {
    super.initState();
    final ConversationsCubit cubit = context.read<ConversationsCubit>();
    if (cubit.state.status == ConversationsStatus.initial) cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConversationsCubit, ConversationsState>(
      buildWhen: (previous, current) =>
          previous.unreadTotal != current.unreadTotal,
      builder: (context, state) {
        final int unread = state.unreadTotal;

        return PressScale(
          child: GestureDetector(
            onTap: () => ConversationsScreen.open(context),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.only(left: 10.w),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.message,
                    color: AppColors.textGray,
                    size: 21.sp,
                  ),
                  // A dot rather than a number: at this size a two-digit count
                  // is unreadable, and the inbox itself is one tap away with
                  // the real numbers on it.
                  if (unread > 0)
                    Positioned(
                      top: -1.h,
                      right: -1.w,
                      child: Container(
                        width: 8.w,
                        height: 8.w,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryNeon,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeedTabs extends StatelessWidget {
  const _FeedTabs();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeedCubit, FeedState>(
      buildWhen: (previous, current) => previous.tab != current.tab,
      builder: (context, state) => Container(
        padding: EdgeInsets.all(3.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            _Tab(
              label: 'feed_for_you'.tr(),
              isSelected: state.tab == FeedTab.forYou,
              onTap: () => context.read<FeedCubit>().selectTab(FeedTab.forYou),
            ),
            _Tab(
              label: 'feed_discover'.tr(),
              isSelected: state.tab == FeedTab.discover,
              onTap: () =>
                  context.read<FeedCubit>().selectTab(FeedTab.discover),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.enter,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNeon : Colors.transparent,
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : AppColors.textGray,
              fontSize: 9.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// One feed's list of posts.
///
/// Owns its own scroll controller, which is what makes the [IndexedStack] above
/// worth having: the position lives with the list rather than with the screen.
class _FeedList extends StatefulWidget {
  const _FeedList({required this.tab});

  final FeedTab tab;

  @override
  State<_FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<_FeedList> {
  final ScrollController _controller = ScrollController();

  /// How far from the bottom to start fetching the next page.
  ///
  /// Roughly two cards' worth, so the next posts are usually there before the
  /// reader reaches the end and the scroll never visibly stops.
  static const double _prefetchExtent = 900;

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

  void _onScroll() {
    if (!_controller.hasClients) return;

    final ScrollPosition position = _controller.position;
    if (position.pixels < position.maxScrollExtent - _prefetchExtent) return;

    // The hidden feed in the IndexedStack cannot be scrolled, so this cannot
    // normally fire for the wrong tab — but `loadMore` acts on whichever tab is
    // current, so a stray call would page the other feed. Cheap to rule out.
    final FeedCubit cubit = context.read<FeedCubit>();
    if (cubit.state.tab != widget.tab) return;

    cubit.loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeedCubit, FeedState>(
      builder: (context, state) {
        final FeedSlice slice = state.sliceFor(widget.tab);

        switch (slice.status) {
          case FeedStatus.initial:
          case FeedStatus.loading:
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            );

          case FeedStatus.failure:
            return _FeedMessage(
              icon: Icons.cloud_off_outlined,
              title: 'feed_load_failed'.tr(),
              body: slice.errorMessage,
              actionLabel: 'retry'.tr(),
              onAction: () => context.read<FeedCubit>().load(),
            );

          case FeedStatus.ready:
            return RefreshIndicator(
              color: AppColors.primaryNeon,
              backgroundColor: const Color(0xFF1A1A1A),
              onRefresh: () => context.read<FeedCubit>().refresh(),
              child: slice.posts.isEmpty
                  ? _buildEmpty(context, state)
                  : _buildList(context, slice, busyPostId: state.busyPostId),
            );
        }
      },
    );
  }

  /// The empty state, which is three different messages.
  ///
  /// A feed emptied by the label filter is not the same as a feed with nothing
  /// in it, and For You empty is not the same as Discover empty. Telling
  /// someone "nothing here yet" while a filter they set is hiding twelve posts
  /// is the kind of thing that gets reported as a bug.
  Widget _buildEmpty(BuildContext context, FeedState state) {
    // Scrollable so pull-to-refresh still works on an empty feed — a
    // RefreshIndicator over a non-scrollable child has nothing to pull.
    return ListView(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 60.h),
        if (state.isFiltered)
          _FeedMessage(
            icon: Icons.filter_alt_off_outlined,
            title: 'feed_empty_filtered'.tr(namedArgs: {
              'label': state.label!.labelKey.tr(),
            }),
            body: 'feed_empty_filtered_body'.tr(),
            actionLabel: 'feed_clear_filter'.tr(),
            onAction: () => context.read<FeedCubit>().clearLabel(),
          )
        else if (widget.tab == FeedTab.forYou)
          // The cold start. A new account follows nobody, so this is the first
          // thing most users see on this tab — which is why it points at
          // Discover rather than just saying the feed is empty.
          // The cold start, and now with somewhere to go. "Follow a few
          // people" was only useful advice once there was a screen for doing
          // it — before this slice the button could only offer Discover.
          _FeedMessage(
            icon: Icons.group_outlined,
            title: 'feed_empty_for_you'.tr(),
            body: 'feed_empty_for_you_body'.tr(),
            actionLabel: 'feed_find_people'.tr(),
            onAction: () => SearchScreen.open(context),
            secondaryLabel: 'feed_browse_discover'.tr(),
            onSecondary: () =>
                context.read<FeedCubit>().selectTab(FeedTab.discover),
          )
        else
          _FeedMessage(
            icon: Icons.explore_outlined,
            title: 'feed_empty_discover'.tr(),
            body: 'feed_empty_discover_body'.tr(),
            actionLabel: 'feed_write_first'.tr(),
            onAction: () => PostComposerScreen.open(context),
          ),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    FeedSlice slice, {
    String? busyPostId,
  }) {
    return ListView.builder(
      controller: _controller,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, BulkrNavBar.contentInset),
      // One extra slot for the paging spinner at the tail.
      itemCount: slice.posts.length + (slice.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= slice.posts.length) return _buildTail(slice);

        final Post post = slice.posts[index];
        final bool isSavingMeal = busyPostId == post.id;

        return PostCard(
          // Keyed by post id, not by index. Without it, deleting a post makes
          // every card below it reuse the state of the one that was there —
          // which for a multi-photo post means the carousel stays on page 2 of
          // a post that no longer has two photos.
          key: ValueKey(post.id),
          post: post,
          onShowActions: () => _showActions(context, post),
          onLabelTap: () => context.read<FeedCubit>().selectLabel(post.label),
          onLike: () => context.read<FeedCubit>().toggleLike(post),
          onSave: () => context.read<FeedCubit>().toggleSave(post),
          onComment: () => _openComments(context, post),
          onSaveMeal: post.canSaveMeal ? () => _saveMeal(context, post) : null,
          isSavingMeal: isSavingMeal,
          onOpenAuthor: post.isMine
              ? null
              : () => AuthorProfileScreen.open(context, post.authorId),
          onOpenGroup: post.groupId == null
              ? null
              : () => GroupScreen.open(context, post.groupId!),
          onToggleChallenge: post.hasChallenge
              ? () => context.read<FeedCubit>().toggleChallenge(post)
              : null,
          onOpenLeaderboard: post.hasChallenge
              ? () => ChallengeLeaderboardSheet.show(context, post.challenge!)
              : null,
          isJoiningChallenge: busyPostId == post.id,
        );
      },
    );
  }

  Widget _buildTail(FeedSlice slice) {
    return Padding(
      padding: EdgeInsets.only(bottom: 24.h),
      child: Center(
        child: SizedBox(
          width: 18.w,
          height: 18.w,
          child: const CircularProgressIndicator(
            color: AppColors.primaryNeon,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }

  /// Opens the thread, and takes the new comment count back to the card.
  ///
  /// The sheet resolves to the count as it closes rather than the feed
  /// refetching the post: the sheet already knows the number, and a round trip
  /// to learn something you were just told is a round trip too many.
  Future<void> _openComments(BuildContext context, Post post) async {
    final FeedCubit cubit = context.read<FeedCubit>();
    final int? count = await PostCommentsSheet.show(context, post);

    if (count != null) cubit.setCommentCount(post.id, count);
  }

  /// Copies the post's meal into the reader's library, and refreshes the Meals
  /// tab so it is there when they look.
  Future<void> _saveMeal(BuildContext context, Post post) async {
    final MealsCubit meals = context.read<MealsCubit>();

    await context.read<FeedCubit>().saveMeal(
          post,
          onSaved: (_) => meals.refresh(),
        );
  }

  /// Confirms a block, because it is not something to do by mistyping a tap.
  ///
  /// Says what it will actually do, in both directions. "Block" on its own
  /// reads as "stop seeing them"; half of what it means is that they stop
  /// seeing you, and someone should know that before they choose it.
  Future<bool> _confirmBlock(BuildContext context, String name) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        title: Text(
          'post_block_confirm_title'.tr(namedArgs: {'name': name}),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 15.sp,
            letterSpacing: 1,
          ),
        ),
        content: Text(
          'post_block_confirm_body'.tr(namedArgs: {'name': name}),
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
              style: GoogleFonts.inter(
                color: AppColors.textGray,
                fontSize: 12.sp,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'post_block_confirm_action'.tr().toUpperCase(),
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

    return confirmed ?? false;
  }

  Future<void> _showActions(BuildContext context, Post post) async {
    final FeedCubit cubit = context.read<FeedCubit>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final PostAction? action = await PostActionsSheet.show(context, post);

    if (action == null) return;

    switch (action) {
      case PostAction.delete:
        await cubit.deletePost(post);

      case PostAction.hide:
        await cubit.setHidden(post, isHidden: true);

      case PostAction.unhide:
        await cubit.setHidden(post, isHidden: false);

      case PostAction.hideFromFeed:
        await cubit.hidePost(post);

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2A2A2A),
              duration: const Duration(seconds: 4),
              content: Text(
                'post_hidden_notice'.tr(),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
              ),
              // Hiding is quiet and reversible, so the undo belongs on the
              // notice rather than in a settings screen someone has to find.
              action: SnackBarAction(
                label: 'undo'.tr().toUpperCase(),
                textColor: AppColors.primaryNeon,
                onPressed: () => cubit.unhidePost(post),
              ),
            ),
          );

      case PostAction.blockAuthor:
        if (!context.mounted) return;
        final bool confirmed = await _confirmBlock(context, post.authorName);
        if (!confirmed) return;
        await cubit.blockAuthor(post);

      case PostAction.report:
        if (!context.mounted) return;
        await reportPostFlow(context, post);

      case PostAction.share:
        await Clipboard.setData(
          ClipboardData(text: PostLink.shareText(post)),
        );

        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2A2A2A),
              content: Text(
                'post_share_copied'.tr(),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
              ),
            ),
          );
    }
  }
}

/// Whatever the feed has to say when it is not showing posts.
class _FeedMessage extends StatelessWidget {
  const _FeedMessage({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// A second, quieter way out. The cold-start state has two reasonable
  /// answers — go find people, or go read what everyone else posted — and
  /// picking one for the user would be picking wrong half the time.
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textGray, size: 34.sp),
            SizedBox(height: 16.h),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 17.sp,
                letterSpacing: 1.2,
              ),
            ),
            if (body != null) ...[
              SizedBox(height: 10.h),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 12.sp,
                  height: 1.5,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: 20.h),
              PressScale(
                child: GestureDetector(
                  onTap: onAction,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 11.h),
                    decoration: BoxDecoration(
                      color: AppColors.buttonNeon,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      actionLabel!.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              SizedBox(height: 10.h),
              GestureDetector(
                onTap: onSecondary,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.h),
                  child: Text(
                    secondaryLabel!.toUpperCase(),
                    style: GoogleFonts.inter(
                      color: AppColors.textGray,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
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

class _ComposeButton extends StatelessWidget {
  const _ComposeButton();

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: () => PostComposerScreen.open(context),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 13.h),
          decoration: BoxDecoration(
            color: AppColors.buttonNeon,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.black, size: 18.sp),
              SizedBox(width: 8.w),
              Text(
                'feed_compose'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
