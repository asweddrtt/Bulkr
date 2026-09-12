import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/analytics_events.dart';
import '../core/error_text.dart';
import '../core/telemetry.dart';
import '../data/moderation_repository.dart';
import '../data/post_repository.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import '../widgets/post_card.dart';
import 'author_profile_screen.dart';
import 'post_comments_sheet.dart';

/// One post, fetched by id.
///
/// The destination a shared link finally has. `PostLink.forPost` has been
/// putting `com.alimahmoud.bulkr://post/<id>` on the clipboard from four
/// screens, and `PostRepository.fetchPost` was written "for a deep link or a
/// share target" and had no callers — the two ends of a feature with nothing
/// in between. This is the middle.
///
/// Reached two ways, and they matter differently:
///
///   - from a link somebody was sent, which is the whole point, and where the
///     post may be one the reader cannot see
///   - from a push notification, where the same applies
///
/// So it fetches rather than being handed a [Post], and it has a real "not
/// available" state rather than assuming the row comes back. A link outlives
/// the post it points at: it can be deleted, made private, or belong to
/// somebody who has since blocked the reader — and all three arrive here as a
/// null.
class PostScreen extends StatefulWidget {
  const PostScreen({super.key, required this.postId, required this.source});

  final String postId;

  /// How this was reached — `deep_link`, `push`. Recorded, because the only
  /// way to know whether sharing does anything is to count the opens against
  /// the `post_shared` events.
  final String source;

  static Future<void> open(
    BuildContext context,
    String postId, {
    required String source,
  }) {
    final PostRepository posts = context.read<PostRepository>();
    final ModerationRepository moderation = context.read<ModerationRepository>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MultiRepositoryProvider(
          providers: [
            RepositoryProvider.value(value: posts),
            RepositoryProvider.value(value: moderation),
          ],
          child: PostScreen(postId: postId, source: source),
        ),
      ),
    );
  }

  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  Post? _post;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(Telemetry.send(AnalyticsEvent.postOpened(source: widget.source)));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final Post? post =
          await context.read<PostRepository>().fetchPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _loading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      // Reported rather than only shown: a link that fails to open is
      // invisible from this end, and the person who sent it will be told the
      // app is broken.
      unawaited(Telemetry.recordError(error, stackTrace,
          reason: 'opening a post from ${widget.source}'));
      unawaited(Telemetry.send(AnalyticsEvent.requestFailed(
        operation: 'post.fetch',
        kind: describeFailure(error).kind.name,
      )));
      setState(() {
        _error = describeError(error);
        _loading = false;
      });
    }
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
          'post_title'.tr().toUpperCase(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 15.sp,
            letterSpacing: 1,
          ),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryNeon),
      );
    }

    if (_error != null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        title: 'post_load_failed'.tr(),
        body: _error,
        actionLabel: 'retry'.tr(),
        onAction: _load,
      );
    }

    final Post? post = _post;
    if (post == null) {
      // Not an error. A link outlives what it points at, and "this is gone"
      // is a true and complete answer — the reader does not need to know
      // which of deleted, private or blocked it was, and telling them would
      // leak something about a post they are not allowed to see.
      return _Message(
        icon: Icons.link_off,
        title: 'post_unavailable_title'.tr(),
        body: 'post_unavailable_body'.tr(),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 30.h),
      children: [
        PostCard(
          post: post,
          // No overflow menu. Its actions — hide, report, block — are about
          // shaping a feed, and arriving from a link is not being in one.
          onShowActions: () {},
          onComment: () => PostCommentsSheet.show(context, post),
          onOpenAuthor: () =>
              AuthorProfileScreen.open(context, post.authorId),
        ),
      ],
    );
  }
}

/// The two states that are not a post: it failed, or it is gone.
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
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textGray, size: 34.sp),
            SizedBox(height: 14.h),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 15.sp,
                letterSpacing: 1,
              ),
            ),
            if (body != null) ...[
              SizedBox(height: 8.h),
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
              TextButton(
                onPressed: onAction,
                child: Text(
                  actionLabel!.toUpperCase(),
                  style: GoogleFonts.inter(
                    color: AppColors.primaryNeon,
                    fontSize: 12.sp,
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
