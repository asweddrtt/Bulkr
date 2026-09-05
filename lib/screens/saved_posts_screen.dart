import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../data/post_repository.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import '../widgets/post_label_chip.dart';
import '../widgets/person_row.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/post_card.dart';
import 'author_profile_screen.dart';
import 'post_comments_sheet.dart';

/// Everything this user has saved, most recently saved first.
///
/// [PostRepository.fetchSavedPosts] was written when saving was added and then
/// called by nothing, so saving a post put it somewhere with no way back to it.
/// This is that way back.
///
/// A grid of tiles rather than a column of full cards. A feed is for reading
/// as it comes; a saved list is for *finding* the one you meant, and full
/// cards make that a scroll through things you have already read. Two columns
/// puts a dozen in view at once, and tapping one opens it whole.
///
/// Reads the repository directly rather than through a cubit. It is one query
/// and two writes, opened deliberately rather than kept live, and the feed's
/// own cubit is the wrong home for it — that one holds two ordered, paged,
/// cursored slices, and none of that applies to a list of two hundred
/// bookmarks ordered by when they were made.
class SavedPostsScreen extends StatefulWidget {
  const SavedPostsScreen({super.key});

  /// Opens the list, and refreshes the feed on the way out.
  ///
  /// Unsaving something here changes the bookmark state of a card that may be
  /// on screen behind, and a feed still showing it as saved is the moment the
  /// two disagree.
  static Future<void> open(BuildContext context) async {
    final PostRepository posts = context.read<PostRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: posts,
          child: BlocProvider.value(
            value: feed,
            child: const SavedPostsScreen(),
          ),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  State<SavedPostsScreen> createState() => _SavedPostsScreenState();
}

class _SavedPostsScreenState extends State<SavedPostsScreen> {
  List<Post>? _posts;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Post> posts =
          await context.read<PostRepository>().fetchSavedPosts();

      if (!mounted) return;
      setState(() {
        _posts = posts;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _posts = const [];
        _error = '$error';
      });
    }
  }

  /// Unsaves, and takes the card out.
  ///
  /// Removing it here is right where removing it from a follow list would not
  /// be: this list *is* the saved set, so a post that is no longer saved has no
  /// business still being in it. A failure puts it back by reloading.
  Future<void> _unsave(Post post) async {
    final PostRepository posts = context.read<PostRepository>();

    setState(() {
      _posts = _posts?.where((other) => other.id != post.id).toList();
    });

    try {
      await posts.setSaved(postId: post.id, isSaved: false);
    } catch (_) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Post>? posts = _posts;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'saved_posts_title'.tr().toUpperCase(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 17.sp,
            letterSpacing: 1,
          ),
        ),
      ),
      body: posts == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            )
          : posts.isEmpty
              ? _Notice(
                  text: _error == null
                      ? 'saved_posts_empty'.tr()
                      : ['saved_posts_failed'.tr(), _error!].join('\n\n'),
                  onRetry: _error == null ? null : _load,
                )
              : RefreshIndicator(
                  color: AppColors.primaryNeon,
                  backgroundColor: const Color(0xFF1A1A1A),
                  onRefresh: _load,
                  child: GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 30.h),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12.h,
                      crossAxisSpacing: 12.w,
                      // Slightly taller than square. A photo post wants the
                      // extra room for its footer, and a text post wants it
                      // for the text.
                      childAspectRatio: 0.82,
                    ),
                    itemCount: posts.length,
                    itemBuilder: (_, index) => _SavedTile(
                      key: ValueKey('saved-${posts[index].id}'),
                      post: posts[index],
                      onOpen: () => _open(posts[index]),
                      onUnsave: () => _unsave(posts[index]),
                    ),
                  ),
                ),
    );
  }

  /// Opens one saved post whole.
  ///
  /// A route rather than a sheet: the card is tall, it has a comments sheet of
  /// its own to open on top, and a sheet over a sheet is where the back
  /// gesture stops meaning anything.
  Future<void> _open(Post post) async {
    final PostRepository posts = context.read<PostRepository>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: posts,
          child: _SavedPostScreen(post: post),
        ),
      ),
    );

    // It may have been unsaved from in there.
    await _load();
  }
}

/// One saved post, opened from the grid.
class _SavedPostScreen extends StatelessWidget {
  const _SavedPostScreen({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 30.h),
        children: [
          PostCard(
            post: post,
            // The overflow menu is deliberately absent: its reader actions
            // are about shaping a feed, and this is a reading list. Unsaving
            // is the one thing that makes sense here, and the bookmark
            // already does it.
            onShowActions: () => _unsaveAndClose(context),
            onSave: () => _unsaveAndClose(context),
            onComment: () => PostCommentsSheet.show(context, post),
            onOpenAuthor: () =>
                AuthorProfileScreen.open(context, post.authorId),
          ),
        ],
      ),
    );
  }

  /// Unsaving from in here also closes: this screen was reached from the saved
  /// list, and a post that is no longer saved has nothing to go back to.
  Future<void> _unsaveAndClose(BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context);
    await context
        .read<PostRepository>()
        .setSaved(postId: post.id, isSaved: false);
    navigator.pop();
  }
}

/// One post, small enough that a dozen fit on screen.
///
/// The photo when there is one, because that is what people recognise a post
/// by. Its text when there is not, because a tile with only a label on it is
/// a tile nobody can tell from the next one.
class _SavedTile extends StatelessWidget {
  const _SavedTile({
    super.key,
    required this.post,
    required this.onOpen,
    required this.onUnsave,
  });

  final Post post;
  final VoidCallback onOpen;
  final VoidCallback onUnsave;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onOpen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (post.hasImages)
                      Image.network(
                        post.imageUrls.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _textPreview(),
                      )
                    else
                      _textPreview(),
                    Positioned(
                      top: 6.h,
                      left: 6.w,
                      child: PostLabelChip(label: post.label),
                    ),
                    // Unsaving from the tile, so clearing out a reading list
                    // does not mean opening every post in it.
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: onUnsave,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: EdgeInsets.all(8.w),
                          child: Icon(
                            Icons.bookmark,
                            size: 18.sp,
                            color: AppColors.primaryNeon,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(10.w, 8.h, 10.w, 10.h),
                child: Row(
                  children: [
                    PersonAvatar(
                      url: post.authorAvatarUrl,
                      name: post.authorName,
                      size: 18.w,
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        post.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.offWhiteMuted,
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

  Widget _textPreview() {
    return Container(
      color: const Color(0xFF141414),
      padding: EdgeInsets.fromLTRB(10.w, 32.h, 10.w, 10.h),
      alignment: Alignment.topLeft,
      child: Text(
        post.content ?? '',
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 11.sp,
          height: 1.4,
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
            Icon(
              Icons.bookmark_border,
              size: 36.sp,
              color: AppColors.textGray,
            ),
            SizedBox(height: 14.h),
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
