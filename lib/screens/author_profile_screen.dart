import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/post_link.dart';
import '../cubit/author/author_cubit.dart';
import '../cubit/feed/feed_cubit.dart';
import '../data/meal_repository.dart';
import '../data/moderation_repository.dart';
import '../data/follow_repository.dart';
import '../data/post_repository.dart';
import '../models/meal.dart';
import '../models/person.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import '../widgets/animations/motion.dart';
import '../widgets/meal_card.dart';
import '../widgets/sheet_action_row.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/person_row.dart';
import '../widgets/post_actions_sheet.dart';
import '../widgets/post_card.dart';
import '../widgets/report_sheet.dart';
import 'chat_screen.dart';
import 'people_list_screen.dart';
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
    final ModerationRepository moderation = context.read<ModerationRepository>();
    final MealRepository meals = context.read<MealRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => AuthorCubit(
            followRepository: follows,
            postRepository: posts,
            moderationRepository: moderation,
            mealRepository: meals,
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
                  SliverToBoxAdapter(
                    child: ProfileTabs(showsMeals: state.showsMeals),
                  ),
                  if (state.showsMeals)
                    MealsSliver(state: state)
                  else if (state.hasNoPosts)
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
  // Read before the await, like the cubit above it: the sheet is a route,
  // and reaching back through this context after it closes is reaching
  // through a context that may be gone.
  final PostRepository posts = context.read<PostRepository>();
  final PostAction? action = await PostActionsSheet.show(context, post);

  if (action == null) return;

  switch (action) {
    case PostAction.delete:
      await cubit.deletePost(post);

    case PostAction.hide:
      await cubit.setHidden(post, isHidden: true);

    case PostAction.unhide:
      await cubit.setHidden(post, isHidden: false);

    // Hiding and blocking are the feed's to own — the reader-side actions
    // exist to shape what arrives there, and doing them from a screen whose
    // whole purpose is to show one author's or one group's posts would empty
    // the screen the user deliberately opened. Offered here so the sheet is
    // consistent; handled by taking them back to the feed's own flow.
    case PostAction.hideFromFeed:
      await posts.hidePost(post.id);

    case PostAction.blockAuthor:
      if (post.isMine) return;
      await posts.blockAuthor(post.authorId);

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

/// Posts or meals.
///
/// A profile is two things somebody has made, and the feed only ever showed
/// one of them. Meals are the other half of what this app is for, and a
/// library nobody else can see is a library that only ever gets used once.
class ProfileTabs extends StatelessWidget {
  const ProfileTabs({super.key, required this.showsMeals});

  final bool showsMeals;

  @override
  Widget build(BuildContext context) {
    final AuthorCubit cubit = context.read<AuthorCubit>();

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 4.h),
      child: Row(
        children: [
          Expanded(
            child: _ProfileTab(
              labelKey: 'profile_tab_posts',
              isSelected: !showsMeals,
              onTap: () => cubit.showMeals(false),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: _ProfileTab(
              labelKey: 'profile_tab_meals',
              isSelected: showsMeals,
              onTap: () => cubit.showMeals(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
    required this.labelKey,
    required this.isSelected,
    required this.onTap,
  });

  final String labelKey;
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
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 9.h),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNeon : Colors.transparent,
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color: isSelected ? AppColors.primaryNeon : AppColors.darkBorder,
            ),
          ),
          child: Text(
            labelKey.tr().toUpperCase(),
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : AppColors.textGray,
              fontSize: 10.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// The meals half of a profile.
class MealsSliver extends StatelessWidget {
  const MealsSliver({super.key, required this.state});

  final AuthorState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingMeals && state.meals.isEmpty) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primaryNeon),
        ),
      );
    }

    if (state.meals.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _Message(
          icon: Icons.restaurant_menu_outlined,
          title: state.isMe
              ? 'profile_no_meals_mine'.tr()
              : 'profile_no_meals'.tr(),
          // Only worth saying on somebody else's: a private meal is invisible
          // by design, and "they have none" would be the wrong conclusion to
          // let someone draw from an empty list.
          body: state.isMe ? null : 'profile_no_meals_body'.tr(),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
      sliver: SliverList.builder(
        itemCount: state.meals.length,
        itemBuilder: (context, index) {
          final Meal meal = state.meals[index];
          // Read-only. Favouriting, logging and editing all belong to the
          // Meals tab, where the library is yours to manage; a profile is
          // somewhere you look at what somebody made. The card hides those
          // controls rather than greying them out.
          return MealCard(
            key: ValueKey('profile-meal-${meal.id}'),
            meal: meal,
          );
        },
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
          const Spacer(),
          // Blocking lives here rather than only on a post, because somebody
          // who has never posted cannot be blocked from a post — and "has
          // written nothing" is not a reason to be unreachable by the control
          // that stops them contacting you.
          BlocBuilder<AuthorCubit, AuthorState>(
            buildWhen: (previous, current) =>
                previous.isBlocked != current.isBlocked ||
                previous.isBlockWriting != current.isBlockWriting ||
                previous.person != current.person,
            builder: (context, state) {
              // Nothing to block on your own profile, and nothing to block
              // before the row has loaded.
              if (state.person == null || !state.person!.isFollowable) {
                return const SizedBox.shrink();
              }

              return PressScale(
                enabled: !state.isBlockWriting,
                child: GestureDetector(
                  onTap: () => _openProfileActions(context, state),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(8.w),
                    child: Icon(
                      Icons.more_horiz,
                      color: Colors.white,
                      size: 20.sp,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Block, or take a block back.
///
/// A sheet with one option rather than a bare icon that blocks on tap: this is
/// consequential and the icon it sits under says nothing about what it does.
Future<void> _openProfileActions(BuildContext context, AuthorState state) async {
  final AuthorCubit cubit = context.read<AuthorCubit>();
  final String name = state.person?.name ?? '';
  final bool blocked = state.isBlocked;

  final bool? chosen = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        // The Column with a minimum main axis size is what every other sheet
        // in the app has and this one did not: without it the box stretches
        // instead of wrapping its one row, which is what made this look
        // broken next to the rest of them.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A header, for the same reason. A single action floating in a
            // box says nothing about who it applies to — and this is a sheet
            // opened from a `...` that says nothing either.
            Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 16.sp,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 14.h),
            SheetActionRow(
              icon: blocked ? Icons.lock_open : Icons.block,
              label: blocked
                  ? 'profile_unblock'.tr(namedArgs: {'name': name})
                  : 'profile_block'.tr(namedArgs: {'name': name}),
              helper: blocked
                  ? 'profile_unblock_helper'.tr()
                  : 'post_block_author_helper'.tr(),
              isDestructive: !blocked,
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    ),
  );

  if (chosen != true || !context.mounted) return;

  // Unblocking needs no confirmation — it only ever gives access back.
  if (blocked) {
    await cubit.setBlocked(false);
    return;
  }

  final bool confirmed = await _confirmBlock(context, name);
  if (confirmed) await cubit.setBlocked(true);
}

/// The same wording the feed uses, because it is the same act.
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
                onTap: () => PeopleListScreen.open(
                  context,
                  personId: person.id,
                  side: FollowSide.followers,
                ),
              ),
              SizedBox(width: 28.w),
              _Stat(
                value: person.followingCount,
                labelKey: 'profile_following_label',
                onTap: () => PeopleListScreen.open(
                  context,
                  personId: person.id,
                  side: FollowSide.following,
                ),
              ),
            ],
          ),
          if (person.isFollowable) ...[
            SizedBox(height: 18.h),
            Row(
              children: [
                FollowButton(
                  isFollowing: person.isFollowedByMe,
                  isBusy: state.isFollowWriting,
                  onTap: () => context.read<AuthorCubit>().toggleFollow(),
                ),
                // Not shown while a block is in place. The server refuses the
                // conversation either way, and offering a button that can only
                // fail is worse than not offering it — the block sheet in the
                // corner is where that gets taken back.
                if (!state.isBlocked) ...[
                  SizedBox(width: 10.w),
                  _MessageButton(person: person),
                ],
              ],
            ),
          ],
          SizedBox(height: 8.h),
          Divider(color: AppColors.darkBorder, height: 1),
        ],
      ),
    );
  }
}

/// Opens a direct thread with the person whose profile this is.
///
/// Outlined rather than filled: following is the call to action on a profile,
/// and two solid buttons side by side would make neither of them the point.
class _MessageButton extends StatelessWidget {
  const _MessageButton({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ChatScreen.openWith(
          context,
          personId: person.id,
          name: person.name,
          avatarUrl: person.avatarUrl,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Text(
            'chat_message_action'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.9,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.labelKey, this.onTap});

  final int value;
  final String labelKey;

  /// Opens whatever the number counts. Null for a stat with nothing behind it
  /// — posts are already on the screen the stat is on.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget column = _column();
    if (onTap == null) return column;

    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: column,
      ),
    );
  }

  Widget _column() {
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
