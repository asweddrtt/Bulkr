import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../core/post_link.dart';
import '../cubit/group/group_cubit.dart';
import '../data/group_repository.dart';
import '../data/post_repository.dart';
import '../models/group.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/group_row.dart';
import '../widgets/post_actions_sheet.dart';
import '../widgets/post_card.dart';
import '../widgets/report_sheet.dart';
import 'author_profile_screen.dart';
import 'post_comments_sheet.dart';
import 'post_composer_screen.dart';

/// One group, and what has been posted in it.
class GroupScreen extends StatelessWidget {
  const GroupScreen({super.key});

  /// Opens [groupId], and refreshes For You on the way out.
  static Future<void> open(BuildContext context, String groupId) async {
    final GroupRepository groups = context.read<GroupRepository>();
    final PostRepository posts = context.read<PostRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => GroupCubit(
            groupRepository: groups,
            postRepository: posts,
            groupId: groupId,
          )..load(),
          child: BlocProvider.value(
            value: feed,
            child: const GroupScreen(),
          ),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GroupCubit, GroupState>(
      listenWhen: (previous, current) =>
          current.actionErrorKey != null &&
          previous.actionErrorKey != current.actionErrorKey,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2A2A2A),
              content: Text(
                state.actionErrorDetail ?? state.actionErrorKey!.tr(),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
              ),
            ),
          );
        context.read<GroupCubit>().clearNotice();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        floatingActionButton: BlocBuilder<GroupCubit, GroupState>(
          buildWhen: (previous, current) => previous.canPost != current.canPost,
          // Only members get the button, because only members can post — the
          // insert policy checks the same thing, so a button for a non-member
          // would be a button that fails.
          builder: (context, state) =>
              state.canPost ? const _PostButton() : const SizedBox.shrink(),
        ),
        body: SafeArea(child: _Body()),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final ScrollController _controller = ScrollController();

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

    context.read<GroupCubit>().loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GroupCubit, GroupState>(
      builder: (context, state) {
        switch (state.status) {
          case GroupStatus.initial:
          case GroupStatus.loading:
            return const Column(
              children: [
                _BackBar(),
                Expanded(
                  child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primaryNeon),
                  ),
                ),
              ],
            );

          case GroupStatus.notFound:
            return Column(
              children: [
                const _BackBar(),
                Expanded(
                  child: _Message(
                    icon: Icons.lock_outline,
                    title: 'group_not_found'.tr(),
                    body: 'group_not_found_body'.tr(),
                  ),
                ),
              ],
            );

          case GroupStatus.failure:
            return Column(
              children: [
                const _BackBar(),
                Expanded(
                  child: _Message(
                    icon: Icons.cloud_off_outlined,
                    title: 'group_load_failed'.tr(),
                    body: state.errorMessage,
                    actionLabel: 'retry'.tr(),
                    onAction: () => context.read<GroupCubit>().load(),
                  ),
                ),
              ],
            );

          case GroupStatus.ready:
            return RefreshIndicator(
              color: AppColors.primaryNeon,
              backgroundColor: const Color(0xFF1A1A1A),
              onRefresh: () => context.read<GroupCubit>().refresh(),
              child: CustomScrollView(
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: _BackBar()),
                  SliverToBoxAdapter(child: _GroupHeader(state: state)),
                  if (state.hasNoPosts)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _Message(
                        icon: Icons.dynamic_feed_outlined,
                        title: 'group_no_posts'.tr(),
                        body: state.canPost
                            ? 'group_no_posts_member_body'.tr()
                            : 'group_no_posts_body'.tr(),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 90.h),
                      sliver: SliverList.builder(
                        itemCount: state.posts.length + (state.hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= state.posts.length) {
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

                          final Post post = state.posts[index];

                          return PostCard(
                            key: ValueKey(post.id),
                            post: post,
                            // The group chip is suppressed here: every post on
                            // this screen is in this group, and repeating that
                            // on every card is noise.
                            showsGroup: false,
                            onShowActions: () => _showActions(context, post),
                            onLike: () =>
                                context.read<GroupCubit>().toggleLike(post),
                            onSave: () =>
                                context.read<GroupCubit>().toggleSave(post),
                            onComment: () => _openComments(context, post),
                            onOpenAuthor: post.isMine
                                ? null
                                : () => AuthorProfileScreen.open(
                                      context,
                                      post.authorId,
                                    ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
        }
      },
    );
  }
}

Future<void> _openComments(BuildContext context, Post post) async {
  final GroupCubit cubit = context.read<GroupCubit>();
  final int? count = await PostCommentsSheet.show(context, post);

  if (count != null) cubit.setCommentCount(post.id, count);
}

Future<void> _showActions(BuildContext context, Post post) async {
  final GroupCubit cubit = context.read<GroupCubit>();
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

    case PostAction.report:
      if (!context.mounted) return;
      await reportPostFlow(context, post);

    case PostAction.share:
      await Clipboard.setData(ClipboardData(text: PostLink.shareText(post)));

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

class _BackBar extends StatelessWidget {
  const _BackBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
      child: Row(
        children: [
          PressScale(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: Icon(Icons.arrow_back, color: Colors.white, size: 20.sp),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.state});

  final GroupState state;

  @override
  Widget build(BuildContext context) {
    final Group group = state.group!;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GroupAvatar(url: group.imageUrl, name: group.name, size: 60.w),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            group.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.anton(
                              color: Colors.white,
                              fontSize: 19.sp,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (group.isPrivate) ...[
                          SizedBox(width: 8.w),
                          Icon(
                            Icons.lock_outline,
                            color: AppColors.textGray,
                            size: 14.sp,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'group_stats'.tr(namedArgs: {
                        'members': '${group.memberCount}',
                        'posts': '${group.postCount}',
                      }),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 11.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (group.description != null &&
              group.description!.trim().isNotEmpty) ...[
            SizedBox(height: 14.h),
            Text(
              group.description!.trim(),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12.sp,
                height: 1.5,
              ),
            ),
          ],
          if (!group.isOwner) ...[
            SizedBox(height: 16.h),
            Align(
              alignment: Alignment.centerLeft,
              child: GroupJoinButton(
                isMember: group.isMember,
                isBusy: state.isMembershipWriting,
                onTap: () => context.read<GroupCubit>().toggleMembership(),
              ),
            ),
          ],
          SizedBox(height: 12.h),
          Divider(color: AppColors.darkBorder, height: 1),
        ],
      ),
    );
  }
}

class _PostButton extends StatelessWidget {
  const _PostButton();

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: () {
          final GroupCubit cubit = context.read<GroupCubit>();
          PostComposerScreen.open(
            context,
            groupId: cubit.state.groupId,
            groupName: cubit.state.group?.name,
            onPosted: cubit.postCreated,
          );
        },
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
                'group_post'.tr().toUpperCase(),
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

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 40.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textGray, size: 30.sp),
            SizedBox(height: 14.h),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 15.sp,
                letterSpacing: 1.1,
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
              SizedBox(height: 18.h),
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
          ],
        ),
      ),
    );
  }
}
