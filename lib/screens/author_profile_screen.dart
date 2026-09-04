import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/post_link.dart';
import '../cubit/author/author_cubit.dart';
import '../cubit/feed/feed_cubit.dart';
import '../data/follow_repository.dart';
import '../data/post_repository.dart';
import '../models/person.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/person_row.dart';
import '../widgets/post_actions_sheet.dart';
import '../widgets/post_card.dart';
import '../widgets/report_sheet.dart';
import 'post_comments_sheet.dart';

/// One person's profile: who they are, and everything they have posted.
///
/// Where the feed's author name finally goes. `PostCard.onOpenAuthor` was a
/// dangling null until this existed, which meant tapping somebody's name did
/// nothing — the single most obvious thing to try on a social feed.
class AuthorProfileScreen extends StatelessWidget {
  const AuthorProfileScreen({super.key});

  /// Opens [personId]'s profile, and refreshes For You on the way out.
  ///
  /// The refresh is unconditional: following someone from here changes what the
  /// feed contains, and coming back to a feed that has not noticed is the exact
  /// moment the feature looks broken.
  static Future<void> open(BuildContext context, String personId) async {
    final FollowRepository follows = context.read<FollowRepository>();
    final PostRepository posts = context.read<PostRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => AuthorCubit(
            followRepository: follows,
            postRepository: posts,
            personId: personId,
          )..load(),
          child: BlocProvider.value(
            value: feed,
            child: const AuthorProfileScreen(),
          ),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthorCubit, AuthorState>(
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
        context.read<AuthorCubit>().clearNotice();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
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

    context.read<AuthorCubit>().loadMore();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthorCubit, AuthorState>(
      builder: (context, state) {
        switch (state.status) {
          case AuthorStatus.initial:
          case AuthorStatus.loading:
            return Column(
              children: [
                const _BackBar(),
                const Expanded(
                  child: Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primaryNeon),
                  ),
                ),
              ],
            );

          case AuthorStatus.notFound:
            return Column(
              children: [
                const _BackBar(),
                Expanded(
                  child: _Message(
                    icon: Icons.person_off_outlined,
                    title: 'profile_not_found'.tr(),
                    body: 'profile_not_found_body'.tr(),
                  ),
                ),
              ],
            );

          case AuthorStatus.failure:
            return Column(
              children: [
                const _BackBar(),
                Expanded(
                  child: _Message(
                    icon: Icons.cloud_off_outlined,
                    title: 'author_load_failed'.tr(),
                    body: state.errorMessage,
                    actionLabel: 'retry'.tr(),
                    onAction: () => context.read<AuthorCubit>().load(),
                  ),
                ),
              ],
            );

          case AuthorStatus.ready:
            return RefreshIndicator(
              color: AppColors.primaryNeon,
              backgroundColor: const Color(0xFF1A1A1A),
              onRefresh: () => context.read<AuthorCubit>().refresh(),
              child: CustomScrollView(
                controller: _controller,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: _BackBar()),
                  SliverToBoxAdapter(
                    child: _ProfileHeader(state: state),
                  ),
                  if (state.hasNoPosts)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _Message(
                        icon: Icons.dynamic_feed_outlined,
                        title: state.isMe
                            ? 'profile_no_posts_mine'.tr()
                            : 'profile_no_posts'.tr(),
                        body: state.isMe
                            ? 'profile_no_posts_mine_body'.tr()
                            : null,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
                      sliver: SliverList.builder(
                        itemCount:
                            state.posts.length + (state.hasMore ? 1 : 0),
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
                            onShowActions: () => _showActions(context, post),
                            onLike: () =>
                                context.read<AuthorCubit>().toggleLike(post),
                            onSave: () =>
                                context.read<AuthorCubit>().toggleSave(post),
                            onComment: () => _openComments(context, post),
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

/// Opens the thread, and takes the new count back to the card.
Future<void> _openComments(BuildContext context, Post post) async {
  final AuthorCubit cubit = context.read<AuthorCubit>();
  final int? count = await PostCommentsSheet.show(context, post);

  if (count != null) cubit.setCommentCount(post.id, count);
}

/// The overflow menu, acting on this screen's own copy of the post.
///
/// Routed through [AuthorCubit] rather than [FeedCubit] for the same reason
/// liking is: the feed has never loaded these posts, so its own update would
/// be a no-op and the card would not change.
Future<void> _showActions(BuildContext context, Post post) async {
  final AuthorCubit cubit = context.read<AuthorCubit>();
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.state});

  final AuthorState state;

  @override
  Widget build(BuildContext context) {
    final Person person = state.person!;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PersonAvatar(
                url: person.avatarUrl,
                name: person.name,
                size: 64.w,
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            person.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.anton(
                              color: Colors.white,
                              fontSize: 20.sp,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        if (person.isTrainer) ...[
                          SizedBox(width: 8.w),
                          const TrainerBadge(),
                        ],
                      ],
                    ),
                    if (person.handle != null) ...[
                      SizedBox(height: 2.h),
                      Text(
                        person.handle!,
                        style: GoogleFonts.inter(
                          color: AppColors.textGray,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                    // Shown before the follow button is reached, because it
                    // changes the decision: following back is a different act
                    // from following.
                    if (person.followsMe && !person.isMe) ...[
                      SizedBox(height: 6.h),
                      Text(
                        'profile_follows_you'.tr(),
                        style: GoogleFonts.inter(
                          color: AppColors.primaryNeon,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Their About, when they have written one. Same placement as on the
          // user's own profile, so a profile reads the same whoever is looking
          // at it — the only differences are the follow button and the back
          // arrow.
          if (person.hasBio) ...[
            SizedBox(height: 14.h),
            Text(
              person.bio!.trim(),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12.sp,
                height: 1.55,
              ),
            ),
          ],
          SizedBox(height: 18.h),
          Row(
            children: [
              _Stat(
                value: person.postCount,
                labelKey: 'profile_posts_label',
              ),
              SizedBox(width: 28.w),
              _Stat(
                value: person.followerCount,
                labelKey: 'profile_followers_label',
              ),
              SizedBox(width: 28.w),
              _Stat(
                value: person.followingCount,
                labelKey: 'profile_following_label',
              ),
            ],
          ),
          if (person.isFollowable) ...[
            SizedBox(height: 18.h),
            SizedBox(
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FollowButton(
                  isFollowing: person.isFollowedByMe,
                  isBusy: state.isFollowWriting,
                  onTap: () => context.read<AuthorCubit>().toggleFollow(),
                ),
              ),
            ),
          ],
          SizedBox(height: 8.h),
          Divider(color: AppColors.darkBorder, height: 1),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.labelKey});

  final int value;
  final String labelKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 17.sp,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          labelKey.tr().toUpperCase(),
          style: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 9.sp,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.9,
          ),
        ),
      ],
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
