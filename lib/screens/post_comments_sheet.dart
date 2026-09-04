import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/relative_time.dart';
import '../cubit/comments/comments_cubit.dart';
import '../data/post_repository.dart';
import '../models/post.dart';
import '../models/post_comment.dart';
import '../models/post_label.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';

/// One post's conversation.
///
/// A sheet rather than a screen, and a tall one. A comment is written while
/// looking at the post it is about, so the feed stays visible behind it — and
/// unlike the composer, nothing here needs more room than a keyboard leaves.
class PostCommentsSheet extends StatelessWidget {
  const PostCommentsSheet({super.key});

  /// Opens the thread for [post].
  ///
  /// Resolves to the post's comment count as the sheet closes, so the card
  /// behind it can show the new number without a refetch. Null when the sheet
  /// was dismissed before anything loaded.
  static Future<int?> show(BuildContext context, Post post) {
    final PostRepository posts = context.read<PostRepository>();

    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      // The sheet holds a text field, so it has to be able to grow past half
      // the screen and sit above the keyboard.
      isScrollControlled: true,
      builder: (_) => BlocProvider(
        create: (_) => CommentsCubit(postRepository: posts, post: post)..load(),
        child: const PostCommentsSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CommentsCubit, CommentsState>(
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
        context.read<CommentsCubit>().clearNotice();
      },
      child: Padding(
        // Lifts the whole sheet above the keyboard. Without it the field is
        // behind it and the user types blind.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
            border: Border(top: BorderSide(color: AppColors.darkBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _Header(),
              Flexible(child: _Body()),
              _Composer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CommentsCubit, CommentsState>(
      buildWhen: (previous, current) =>
          previous.totalCount != current.totalCount,
      builder: (context, state) => Padding(
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 12.w, 10.h),
        child: Row(
          children: [
            Expanded(
              child: Text(
                state.totalCount == 0
                    ? 'comments_title'.tr().toUpperCase()
                    : 'comments_title_count'
                        .tr(namedArgs: {'count': '${state.totalCount}'})
                        .toUpperCase(),
                style: GoogleFonts.anton(
                  color: Colors.white,
                  fontSize: 16.sp,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            PressScale(
              child: GestureDetector(
                // Hands the count back so the card can update its number.
                onTap: () => Navigator.of(context).pop(state.totalCount),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: Icon(Icons.close, color: Colors.white, size: 19.sp),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CommentsCubit, CommentsState>(
      builder: (context, state) {
        switch (state.status) {
          case CommentsStatus.initial:
          case CommentsStatus.loading:
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 40.h),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNeon),
              ),
            );

          case CommentsStatus.failure:
            return Padding(
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 30.h),
              child: Column(
                children: [
                  Text(
                    'comments_load_failed'.tr(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 13.sp,
                    ),
                  ),
                  if (state.errorMessage != null) ...[
                    SizedBox(height: 8.h),
                    Text(
                      state.errorMessage!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 11.sp,
                      ),
                    ),
                  ],
                  SizedBox(height: 16.h),
                  PressScale(
                    child: GestureDetector(
                      onTap: () => context.read<CommentsCubit>().load(),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 18.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.buttonNeon,
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          'retry'.tr().toUpperCase(),
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
              ),
            );

          case CommentsStatus.ready:
            if (state.isEmpty) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 40.h, horizontal: 40.w),
                child: Column(
                  children: [
                    Icon(
                      Icons.mode_comment_outlined,
                      color: AppColors.textGray,
                      size: 26.sp,
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      // A question with no answers wants a different nudge from
                      // a photo with no comments.
                      state.post.label == PostLabel.question
                          ? 'comments_empty_question'.tr()
                          : 'comments_empty'.tr(),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 12.sp,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              shrinkWrap: true,
              itemCount: state.threads.length,
              itemBuilder: (context, index) {
                final PostComment thread = state.threads[index];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CommentRow(comment: thread),
                    // Replies are indented once and never again — the database
                    // refuses a third level, so there is no deeper case to
                    // draw.
                    for (final PostComment reply in thread.replies)
                      Padding(
                        padding: EdgeInsets.only(left: 34.w),
                        child: _CommentRow(comment: reply),
                      ),
                  ],
                );
              },
            );
        }
      },
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});

  final PostComment comment;

  @override
  Widget build(BuildContext context) {
    final ({String key, Map<String, String>? args}) stamp =
        RelativeTime.stamp(comment.createdAt);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(url: comment.authorAvatarUrl, name: comment.authorName),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      stamp.key.tr(namedArgs: stamp.args),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 10.sp,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 3.h),
                Text(
                  comment.content,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 5.h),
                Row(
                  children: [
                    _TextAction(
                      label: 'comment_reply'.tr(),
                      onTap: () =>
                          context.read<CommentsCubit>().replyTo(comment),
                    ),
                    if (comment.canDelete) ...[
                      SizedBox(width: 16.w),
                      _TextAction(
                        label: 'comment_delete'.tr(),
                        isDestructive: true,
                        onTap: () =>
                            context.read<CommentsCubit>().delete(comment),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain-text button, for the low-weight actions under a comment.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final Color tint = onTap == null
        ? const Color(0xFF4A4A4A)
        : (isDestructive ? const Color(0xFFFF5722) : AppColors.textGray);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          color: tint,
          fontSize: 9.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// The field, and the reply target above it.
class _Composer extends StatefulWidget {
  const _Composer();

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CommentsCubit, CommentsState>(
      listenWhen: (previous, current) => previous.draft != current.draft,
      listener: (context, state) {
        // The cubit clears the draft on submit and puts it back on failure, so
        // the field follows it — but only when they actually disagree, or every
        // keystroke would reset the cursor to the end.
        if (_controller.text != state.draft) {
          _controller.text = state.draft;
          _controller.selection =
              TextSelection.collapsed(offset: state.draft.length);
        }
      },
      buildWhen: (previous, current) =>
          previous.isReplying != current.isReplying ||
          previous.replyingToName != current.replyingToName ||
          previous.canSubmit != current.canSubmit ||
          previous.isSubmitting != current.isSubmitting ||
          previous.isTooLong != current.isTooLong,
      builder: (context, state) {
        // Tapping Reply on a comment aims the field at that thread, so it also
        // has to put the cursor there — otherwise the label appears and nothing
        // else happens.
        if (state.isReplying && !_focus.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && state.isReplying) _focus.requestFocus();
          });
        }

        return Container(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 12.w, 12.h),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.darkBorder)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (state.isReplying) ...[
                  Row(
                    children: [
                      Icon(
                        Icons.reply,
                        color: AppColors.primaryNeon,
                        size: 12.sp,
                      ),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          'comment_replying_to'.tr(namedArgs: {
                            'name': state.replyingToName ?? '',
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppColors.primaryNeon,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            context.read<CommentsCubit>().cancelReply(),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: EdgeInsets.all(6.w),
                          child: Icon(
                            Icons.close,
                            color: AppColors.textGray,
                            size: 13.sp,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        onChanged: (value) =>
                            context.read<CommentsCubit>().setDraft(value),
                        maxLines: 4,
                        minLines: 1,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13.sp,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: state.isReplying
                              ? 'comment_reply_hint'.tr()
                              : 'comment_hint'.tr(),
                          hintStyle: GoogleFonts.inter(
                            color: AppColors.textGray,
                            fontSize: 13.sp,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    PressScale(
                      child: GestureDetector(
                        onTap: state.canSubmit
                            ? () => context.read<CommentsCubit>().submit()
                            : null,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: EdgeInsets.all(9.w),
                          decoration: BoxDecoration(
                            color: state.canSubmit
                                ? AppColors.buttonNeon
                                : const Color(0xFF2A2A2A),
                            shape: BoxShape.circle,
                          ),
                          child: state.isSubmitting
                              ? SizedBox(
                                  width: 14.sp,
                                  height: 14.sp,
                                  child: const CircularProgressIndicator(
                                    color: Colors.black,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.arrow_upward,
                                  color: state.canSubmit
                                      ? Colors.black
                                      : AppColors.textGray,
                                  size: 15.sp,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (state.isTooLong) ...[
                  SizedBox(height: 4.h),
                  Text(
                    'comment_too_long'.tr(namedArgs: {
                      'max': '${CommentsState.maxLength}',
                    }),
                    style: GoogleFonts.inter(
                      color: const Color(0xFFFF5722),
                      fontSize: 10.sp,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The commenter's picture, or their initial when they have none.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final double size = 26.w;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? _buildInitial()
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildInitial(),
              ),
      ),
    );
  }

  Widget _buildInitial() {
    final String initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return ColoredBox(
      color: const Color(0xFF2A2A2A),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.anton(
            color: AppColors.primaryNeon,
            fontSize: 11.sp,
          ),
        ),
      ),
    );
  }
}
