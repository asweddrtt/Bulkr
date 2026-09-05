import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../core/post_link.dart';
import '../cubit/auth/auth_cubit.dart';
import '../cubit/author/author_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../data/follow_repository.dart';
import '../data/post_repository.dart';
import '../data/user_repository.dart';
import '../go_router/app_routes.dart';
import '../models/person.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../styles/app_color.dart';
import '../widgets/delete_account_sheet.dart';
import '../widgets/bulkr_nav_bar.dart';
import '../widgets/account_sheet.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/edit_profile_sheet.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/person_row.dart';
import '../widgets/post_actions_sheet.dart';
import '../widgets/post_card.dart';
import '../widgets/report_sheet.dart';
import 'blocked_people_screen.dart';
import 'post_comments_sheet.dart';
import 'post_composer_screen.dart';

/// The signed-in user's own profile.
///
/// Everything the old profile screen did — targets, weight history, the plan —
/// now lives on the dashboard, which is where a number you check daily
/// belongs. What is left is the thing a profile actually is: who you are, what
/// you have written about yourself, and what you have posted.
///
/// Built on [AuthorCubit], the same cubit that drives somebody else's profile,
/// pointed at the user's own id. That is what keeps the two screens agreeing
/// about what a profile shows — the difference between them is a follow button
/// and a back arrow, not a second implementation.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (previous, current) =>
          previous.profile?.id != current.profile?.id,
      builder: (context, state) {
        final UserProfile? profile = state.profile;

        // The shell loads the profile when it mounts, so this is a brief state
        // on a cold start rather than a screen anyone sits on.
        if (profile == null) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryNeon),
          );
        }

        return BlocProvider<AuthorCubit>(
          // Keyed on the id so signing in as somebody else builds a new cubit
          // rather than showing the previous user's posts under the new name.
          key: ValueKey(profile.id),
          create: (_) => AuthorCubit(
            followRepository: context.read<FollowRepository>(),
            postRepository: context.read<PostRepository>(),
            personId: profile.id,
          )..load(),
          child: const _ProfileView(),
        );
      },
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView();

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView> {
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
    return BlocListener<AuthorCubit, AuthorState>(
      listenWhen: (previous, current) =>
          current.actionErrorKey != null &&
          previous.actionErrorKey != current.actionErrorKey,
      listener: (context, state) {
        _notify(context, state.actionErrorDetail ?? state.actionErrorKey!.tr());
        context.read<AuthorCubit>().clearNotice();
      },
      child: Scaffold(
        // Transparent so the shell's background shows through: this screen
        // lives inside MainScreen's IndexedStack.
        backgroundColor: Colors.transparent,
        body: BlocBuilder<AuthorCubit, AuthorState>(
          builder: (context, state) {
            switch (state.status) {
              case AuthorStatus.initial:
              case AuthorStatus.loading:
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryNeon,
                  ),
                );

              // Your own row not being readable means the profile read policy
              // is missing, not that you do not exist — so this says what to
              // check rather than "nobody here".
              case AuthorStatus.notFound:
              case AuthorStatus.failure:
                return _Message(
                  icon: Icons.cloud_off_outlined,
                  title: 'profile_load_failed'.tr(),
                  body: state.errorMessage,
                  actionLabel: 'retry'.tr(),
                  onAction: () => context.read<AuthorCubit>().load(),
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
                      SliverToBoxAdapter(child: _Header(person: state.person!)),
                      if (state.hasNoPosts)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _Message(
                            icon: Icons.dynamic_feed_outlined,
                            title: 'profile_no_posts_mine'.tr(),
                            body: 'profile_no_posts_mine_body'.tr(),
                            actionLabel: 'feed_compose'.tr(),
                            onAction: () => PostComposerScreen.open(context),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                              20.w, 8.h, 20.w, BulkrNavBar.contentInset),
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
        ),
      ),
    );
  }
}

/// Who you are, what you wrote, and the numbers.
class _Header extends StatelessWidget {
  const _Header({required this.person});

  final Person person;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _EditableAvatar(person: person),
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
                  ],
                ),
              ),
              PressScale(
                child: GestureDetector(
                  onTap: () => _edit(context, person),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(6.w),
                    child: Icon(
                      Icons.edit_outlined,
                      color: AppColors.textGray,
                      size: 19.sp,
                    ),
                  ),
                ),
              ),
              // Settings live here now rather than on the dashboard. Which
              // account am I signed in as, and how do I get out of it, are
              // questions about the person — and this is the screen about the
              // person. The dashboard is about the numbers.
              PressScale(
                child: GestureDetector(
                  onTap: () => _openAccount(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.all(6.w),
                    child: Icon(
                      Icons.settings_outlined,
                      color: AppColors.textGray,
                      size: 20.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // About. Absent when there is nothing written rather than showing a
          // placeholder — except that a profile with no about and no way to
          // add one is a dead end, so the prompt appears in its place.
          SizedBox(height: 14.h),
          if (person.hasBio)
            Text(
              person.bio!.trim(),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12.sp,
                height: 1.55,
              ),
            )
          else
            PressScale(
              child: GestureDetector(
                onTap: () => _edit(context, person),
                behavior: HitTestBehavior.opaque,
                child: Text(
                  'profile_add_about'.tr(),
                  style: GoogleFonts.inter(
                    color: AppColors.primaryNeon,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          SizedBox(height: 18.h),
          Row(
            children: [
              _Stat(value: person.postCount, labelKey: 'profile_posts_label'),
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
          SizedBox(height: 14.h),
          Divider(color: AppColors.darkBorder, height: 1),
        ],
      ),
    );
  }

  /// Which account am I in, and how do I get out of it.
  ///
  /// Signing out is followed by an explicit navigation: the router's guard only
  /// runs on route changes, so without it the user would sit on a profile
  /// belonging to a session that no longer exists.
  static Future<void> _openAccount(BuildContext context) async {
    final AuthCubit auth = context.read<AuthCubit>();
    final GoRouter router = GoRouter.of(context);
    final UserRepository users = context.read<UserRepository>();
    final String username =
        context.read<ProfileCubit>().state.profile?.username ?? '';

    await AccountSheet.show(
      context,
      email: auth.state.user?.email,
      username: username,
      onSignOut: () async {
        await auth.signOut();
        router.go(AppRoutes.welcome);
      },
      onManageBlocked: () => BlockedPeopleScreen.open(context),
      onDeleteAccount: () => _deleteAccount(context, auth, router, users),
    );
  }

  /// Deletes the account, after asking for the handle to be typed.
  ///
  /// A typed confirmation rather than a yes/no, because this is the one action
  /// in the app that nothing can undo: posts, comments, meals, logs and the
  /// login itself, gone, and other people's threads lose the replies. A dialog
  /// somebody can dismiss by tapping where OK usually is is not enough
  /// friction for that.
  ///
  /// Signs out afterwards rather than relying on the session expiring. The
  /// account behind it no longer exists, so every request from here would fail
  /// — better to be on the welcome screen than on a profile that cannot load.
  static Future<void> _deleteAccount(
    BuildContext context,
    AuthCubit auth,
    GoRouter router,
    UserRepository users,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String username =
        context.read<ProfileCubit>().state.profile?.username ?? '';

    final bool confirmed = await DeleteAccountSheet.show(context, username);
    if (!confirmed) return;

    try {
      await users.deleteAccount();
      await auth.signOut();
      router.go(AppRoutes.welcome);
    } catch (error) {
      // Deliberately not signed out on failure: the account still exists, and
      // dropping the session would leave someone unable to try again without
      // signing back in to an account they were told was deleted.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A2A2A),
            duration: const Duration(seconds: 6),
            content: Text(
              [
                'account_delete_failed'.tr(),
                '$error',
              ].join('\n'),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
            ),
          ),
        );
    }
  }

  /// Opens the editor and applies what comes back.
  ///
  /// The name and bio are written to `users`, which is [ProfileCubit]'s table
  /// — so it is reloaded too, or the dashboard would keep greeting the user by
  /// the name they just changed.
  static Future<void> _edit(BuildContext context, Person person) async {
    final AuthorCubit author = context.read<AuthorCubit>();
    final ProfileCubit profile = context.read<ProfileCubit>();

    final ProfileEdit? edit = await EditProfileSheet.open(
      context,
      displayName: person.displayName ?? '',
      bio: person.bio ?? '',
    );

    if (edit == null) return;

    await Future.wait([author.refresh(), profile.load()]);
  }
}

/// The profile picture, and the way to change it.
///
/// A tap opens the same source sheet the meal editor uses, so picking a photo
/// works the same way everywhere in the app. The camera icon in the corner is
/// what makes it discoverable — an avatar that happens to be tappable is an
/// avatar nobody taps.
class _EditableAvatar extends StatefulWidget {
  const _EditableAvatar({required this.person});

  final Person person;

  @override
  State<_EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends State<_EditableAvatar> {
  /// Resized on the way in, like every other photo the app takes. An avatar is
  /// rendered at 64 logical pixels and downloaded by everyone who reads a post
  /// — a full-resolution camera image would be several megabytes for something
  /// shown the size of a thumbnail.
  static const int _maxWidth = 512;
  static const int _quality = 85;

  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: _isSaving ? null : _change,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            PersonAvatar(
              url: widget.person.avatarUrl,
              name: widget.person.name,
              size: 64.w,
            ),
            if (_isSaving)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
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
                ),
              )
            else
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: EdgeInsets.all(4.w),
                  decoration: BoxDecoration(
                    color: AppColors.buttonNeon,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF121212), width: 2.w),
                  ),
                  child: Icon(
                    Icons.photo_camera,
                    color: Colors.black,
                    size: 10.sp,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _change() async {
    final UserRepository users = context.read<UserRepository>();
    final AuthorCubit author = context.read<AuthorCubit>();
    final ProfileCubit profile = context.read<ProfileCubit>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    // Removing is only offered when there is something to remove.
    final ImageSourceChoice? choice = await ImageSourceSheet.show(
      context,
      canRemove: widget.person.avatarUrl != null,
    );
    if (choice == null) return;

    if (choice == ImageSourceChoice.remove) {
      await _run(
        () => users.clearAvatar(),
        author: author,
        profile: profile,
        messenger: messenger,
      );
      return;
    }

    final ImageSource? source = choice.pluginSource;
    if (source == null) return;

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: _maxWidth.toDouble(),
        imageQuality: _quality,
      );
    } catch (error) {
      // A denied camera permission or a cancelled picker throws on some
      // platforms. Neither is worth an error: the user just gets no photo,
      // which they can see for themselves.
      debugPrint('Bulkr: avatar pick failed — $error');
      return;
    }

    if (picked == null) return;

    final Uint8List bytes = await picked.readAsBytes();
    final String extension = _extensionOf(picked.path);

    await _run(
      () => users.updateAvatar(bytes: bytes, extension: extension),
      author: author,
      profile: profile,
      messenger: messenger,
    );
  }

  /// Runs a write, then reloads both cubits that render an avatar.
  ///
  /// Both, because the picture appears in two places: this header, off
  /// `AuthorCubit`, and the dashboard's greeting, off `ProfileCubit`. Reloading
  /// only one leaves the other showing the previous photo until the app
  /// restarts.
  Future<void> _run(
    Future<void> Function() write, {
    required AuthorCubit author,
    required ProfileCubit profile,
    required ScaffoldMessengerState messenger,
  }) async {
    setState(() => _isSaving = true);

    try {
      await write();
      await Future.wait([author.refresh(), profile.load()]);
    } catch (error) {
      debugPrint('Bulkr: avatar write failed — $error');

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A2A2A),
            content: Text(
              '$error',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// The picker re-encodes to JPEG when it resizes, but honours the original
  /// extension when it does not, so the name is the only thing that knows.
  static String _extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final String extension = path.substring(dot + 1).toLowerCase();
    return extension.length > 5 ? 'jpg' : extension;
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
          style: GoogleFonts.anton(color: Colors.white, fontSize: 17.sp),
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

void _notify(BuildContext context, String message) {
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
}

Future<void> _openComments(BuildContext context, Post post) async {
  final AuthorCubit cubit = context.read<AuthorCubit>();
  final int? count = await PostCommentsSheet.show(context, post);

  if (count != null) cubit.setCommentCount(post.id, count);
}

Future<void> _showActions(BuildContext context, Post post) async {
  final AuthorCubit cubit = context.read<AuthorCubit>();
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

    // Every post here is the user's own, so the sheet never offers this — but
    // the switch is exhaustive and a silent fall-through would be a bug the
    // day that changes.
    // Unreachable for the same reason report is: every post here is the
    // user's own, so the sheet never offers the reader's actions. Handled
    // rather than fallen through, because the day that changes a silent
    // no-op would be the bug.
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
      if (!context.mounted) return;
      _notify(context, 'post_share_copied'.tr());
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
        padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 30.h),
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
