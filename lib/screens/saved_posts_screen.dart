import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../data/post_repository.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import '../widgets/post_card.dart';
import 'author_profile_screen.dart';
import 'post_comments_sheet.dart';

/// Everything this user has saved, most recently saved first.
///
/// [PostRepository.fetchSavedPosts] was written when saving was added and then
/// called by nothing, so saving a post put it somewhere with no way back to it.
/// This is that way back.
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
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
                    itemCount: posts.length,
                    itemBuilder: (_, index) {
                      final Post post = posts[index];

                      return PostCard(
                        key: ValueKey('saved-${post.id}'),
                        post: post,
                        // The overflow menu is deliberately absent: its
                        // reader actions are about shaping a feed, and this
                        // is a reading list. Unsaving is the one thing that
                        // makes sense here, and the bookmark already does it.
                        onShowActions: () => _unsave(post),
                        onSave: () => _unsave(post),
                        onComment: () =>
                            PostCommentsSheet.show(context, post),
                        onOpenAuthor: () =>
                            AuthorProfileScreen.open(context, post.authorId),
                      );
                    },
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
