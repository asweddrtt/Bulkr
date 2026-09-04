import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/post.dart';
import 'sheet_action_row.dart';

/// What the user chose to do with a post from its overflow menu.
enum PostAction {
  /// Take the author's own post out of the feed, keeping the row. Reversible.
  hide,

  /// Put a hidden post back.
  unhide,

  /// Delete the author's own post. Irreversible.
  delete,

  /// Flag someone else's post for review.
  report,

  /// Copy a link to the post.
  share,
}

/// The overflow menu on a post card.
///
/// What it offers turns entirely on ownership, and the two sets do not overlap.
/// An author gets hide and delete; everyone else gets report. Showing report on
/// your own post is nonsense, and showing delete on someone else's implies a
/// power no user has.
class PostActionsSheet extends StatelessWidget {
  const PostActionsSheet({super.key, required this.post});

  final Post post;

  /// Resolves to the chosen action, or null when dismissed.
  static Future<PostAction?> show(BuildContext context, Post post) {
    return showModalBottomSheet<PostAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => PostActionsSheet(post: post),
    );
  }

  /// Offered on every post, yours and everyone else's.
  Widget _shareRow(BuildContext context) {
    return SheetActionRow(
      icon: Icons.link,
      label: 'post_share'.tr(),
      helper: 'post_share_helper'.tr(),
      onTap: () => Navigator.of(context).pop(PostAction.share),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: post.isMine ? 'post_your_post'.tr() : post.authorName,
      children: post.isMine ? _authorActions(context) : _readerActions(context),
    );
  }

  List<Widget> _authorActions(BuildContext context) {
    return [
      _shareRow(context),
      if (post.isHidden)
        SheetActionRow(
          icon: Icons.visibility_sharp,
          label: 'post_unhide'.tr(),
          helper: 'post_unhide_helper'.tr(),
          onTap: () => Navigator.of(context).pop(PostAction.unhide),
        )
      else
        SheetActionRow(
          icon: Icons.visibility_off_sharp,
          label: 'post_hide'.tr(),
          helper: 'post_hide_helper'.tr(),
          onTap: () => Navigator.of(context).pop(PostAction.hide),
        ),
      SheetActionRow(
        icon: Icons.delete_outline,
        label: 'post_delete'.tr(),
        helper: 'post_delete_helper'.tr(),
        isDestructive: true,
        onTap: () => Navigator.of(context).pop(PostAction.delete),
      ),
    ];
  }

  List<Widget> _readerActions(BuildContext context) {
    return [
      _shareRow(context),
      SheetActionRow(
        icon: Icons.flag_outlined,
        label: 'post_report'.tr(),
        helper: 'post_report_helper'.tr(),
        isDestructive: true,
        onTap: () => Navigator.of(context).pop(PostAction.report),
      ),
    ];
  }
}
