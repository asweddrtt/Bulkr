import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/relative_time.dart';
import '../models/post.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';
import 'post_label_chip.dart';

/// One post in the feed.
///
/// [onLike], [onComment] and [onSave] stay nullable: a null callback renders
/// the button dimmed and unresponsive rather than hiding it, which is how a
/// card in a context that cannot act on it — a preview, a deep link opened
/// before the feed exists — keeps the same shape as one in the feed.
///
/// The counts come off the post row, maintained by triggers, rather than being
/// counted per card.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onShowActions,
    this.onLike,
    this.onComment,
    this.onSave,
    this.onOpenAuthor,
    this.onSaveMeal,
    this.onLabelTap,
    this.isSavingMeal = false,
  });

  final Post post;

  /// Opens the overflow menu — delete for the author, report for everyone else.
  final VoidCallback onShowActions;

  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onSave;

  /// Opens the author's profile. Null until profiles are reachable.
  final VoidCallback? onOpenAuthor;

  /// Copies the attached meal into the reader's own library.
  final VoidCallback? onSaveMeal;

  /// This card's meal copy is in flight.
  final bool isSavingMeal;

  /// Filters the feed to this post's label.
  final VoidCallback? onLabelTap;

  static const Color _cardColor = Color(0xFF1A1A1A);
  static const Color _imageColor = Color(0xFF232323);
  static const Color _textMuted = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 14.h),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (post.isHidden) _buildHiddenNotice(),
          if (post.content != null && post.content!.trim().isNotEmpty)
            _buildContent(),
          if (post.hasImages) _PostImages(urls: post.imageUrls),
          if (post.attachedMeal != null) _buildMeal(context),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final ({String key, Map<String, String>? args}) stamp =
        RelativeTime.stamp(post.createdAt);

    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 14.h, 6.w, 10.h),
      child: Row(
        children: [
          _Avatar(url: post.authorAvatarUrl, name: post.authorName),
          SizedBox(width: 10.w),
          Expanded(
            child: PressScale(
              child: GestureDetector(
                onTap: onOpenAuthor,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      stamp.key.tr(namedArgs: stamp.args),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 10.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 8.w),
          PostLabelChip(label: post.label, onTap: onLabelTap),
          PressScale(
            child: GestureDetector(
              onTap: onShowActions,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                child: Icon(
                  Icons.more_horiz,
                  color: AppColors.textGray,
                  size: 18.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown only on the author's own copy — RLS hides a hidden post from
  /// everyone else — so the post reads as unpublished rather than as missing.
  Widget _buildHiddenNotice() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF2A2A2A),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
      child: Row(
        children: [
          Icon(Icons.visibility_off_sharp,
              color: AppColors.textGray, size: 13.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              'post_hidden_notice'.tr(),
              style: GoogleFonts.inter(
                color: AppColors.textGray,
                fontSize: 10.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
      child: Text(
        post.content!.trim(),
        // Long posts are clipped on the card rather than pushing every other
        // post off the screen. Tapping through to the post is where the whole
        // thing lives — which is why the limit is generous enough that most
        // posts never reach it.
        maxLines: 12,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13.sp,
          height: 1.45,
        ),
      ),
    );
  }

  /// The meal hanging off the post, and the one-tap way to take it.
  ///
  /// Deliberately a strip rather than a full meal card. The post is the thing
  /// being read; the meal is an attachment, and rendering it at full size would
  /// make every meal post twice as tall as every other kind.
  Widget _buildMeal(BuildContext context) {
    final meal = post.attachedMeal!;

    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 0),
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: SizedBox(
              width: 44.w,
              height: 44.w,
              child: meal.imageUrl == null
                  ? ColoredBox(
                      color: _imageColor,
                      child: Icon(
                        Icons.restaurant_sharp,
                        color: AppColors.textGray,
                        size: 18.sp,
                      ),
                    )
                  : Image.network(
                      meal.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: _imageColor,
                        child: Icon(
                          Icons.restaurant_sharp,
                          color: AppColors.textGray,
                          size: 18.sp,
                        ),
                      ),
                    ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  'post_meal_macros'.tr(namedArgs: {
                    'calories': '${meal.totals.caloriesRounded}',
                    'protein': '${meal.totals.proteinRounded}',
                  }),
                  style: GoogleFonts.inter(
                    color: _textMuted,
                    fontSize: 10.sp,
                  ),
                ),
                // Whoever wrote the recipe, when this is someone's copy of it.
                // Copying a meal makes the saver its `creator_id`, so without
                // this the original author disappears from their own work.
                if (meal.sourceCreatorUsername != null) ...[
                  SizedBox(height: 2.h),
                  Text(
                    'post_meal_credit'.tr(namedArgs: {
                      'username': meal.sourceCreatorUsername!,
                    }),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: AppColors.textGray,
                      fontSize: 9.sp,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isSavingMeal)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: SizedBox(
                width: 14.w,
                height: 14.w,
                child: const CircularProgressIndicator(
                  color: AppColors.primaryNeon,
                  strokeWidth: 2,
                ),
              ),
            )
          // Already taken. A tick rather than a disabled button: the state is
          // worth showing, and a greyed-out "save" invites a tap that would do
          // nothing.
          else if (post.showsMealSavedState)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    color: AppColors.primaryNeon,
                    size: 13.sp,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'post_meal_in_library'.tr().toUpperCase(),
                    style: GoogleFonts.inter(
                      color: AppColors.primaryNeon,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            )
          else if (post.canSaveMeal && onSaveMeal != null)
            PressScale(
              child: GestureDetector(
                onTap: onSaveMeal,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: AppColors.buttonNeon,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                  child: Text(
                    'post_save_meal'.tr().toUpperCase(),
                    style: GoogleFonts.inter(
                      color: Colors.black,
                      fontSize: 9.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: EdgeInsets.fromLTRB(6.w, 8.h, 6.w, 6.h),
      child: Row(
        children: [
          _ActionButton(
            icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
            count: post.likeCount,
            isActive: post.isLiked,
            activeColor: const Color(0xFFFF5A7A),
            onTap: onLike,
          ),
          _ActionButton(
            icon: Icons.mode_comment_outlined,
            count: post.commentCount,
            onTap: onComment,
          ),
          _ActionButton(
            icon: post.isSaved ? Icons.bookmark : Icons.bookmark_border,
            count: post.saveCount,
            isActive: post.isSaved,
            activeColor: AppColors.primaryNeon,
            onTap: onSave,
          ),
        ],
      ),
    );
  }
}

/// The author's picture, or their initial when they have none.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});

  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final double size = 34.w;

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
    // `name` falls back through display name to handle to a placeholder, so it
    // is never empty — but taking [0] of a string is not the place to rely on
    // that holding.
    final String initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return ColoredBox(
      color: const Color(0xFF2A2A2A),
      child: Center(
        child: Text(
          initial,
          style: GoogleFonts.anton(
            color: AppColors.primaryNeon,
            fontSize: 14.sp,
          ),
        ),
      ),
    );
  }
}

/// A post's photos.
///
/// One image renders plainly. More than one becomes a swipeable page with dots,
/// which is what `progress` needs — a before and an after are two images that
/// mean something as a pair, so they are shown one at a time and at the same
/// size rather than side by side at half of it.
class _PostImages extends StatefulWidget {
  const _PostImages({required this.urls});

  final List<String> urls;

  @override
  State<_PostImages> createState() => _PostImagesState();
}

class _PostImagesState extends State<_PostImages> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          // 4:5 rather than the meal card's 16:10. A body shot is portrait, and
          // a progress post cropped to landscape loses the part it is about.
          aspectRatio: 4 / 5,
          child: widget.urls.length == 1
              ? _Photo(url: widget.urls.first)
              : PageView.builder(
                  controller: _controller,
                  itemCount: widget.urls.length,
                  onPageChanged: (page) => setState(() => _page = page),
                  itemBuilder: (_, index) => _Photo(url: widget.urls[index]),
                ),
        ),
        if (widget.urls.length > 1)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < widget.urls.length; i++)
                  Container(
                    width: 5.w,
                    height: 5.w,
                    margin: EdgeInsets.symmetric(horizontal: 3.w),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? AppColors.primaryNeon
                          : AppColors.darkBorder,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF232323),
      child: Image.network(
        url,
        fit: BoxFit.cover,
        // A grey block while it loads, not a spinner. A feed of spinners
        // flickers; a feed of placeholders just fills in.
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const SizedBox.shrink(),
        errorBuilder: (_, __, ___) => Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: AppColors.textGray,
            size: 22.sp,
          ),
        ),
      ),
    );
  }
}

/// One of the three things you can do to a post.
///
/// A null [onTap] dims it and stops it responding, for a card shown somewhere
/// that cannot act on it.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.count,
    this.onTap,
    this.isActive = false,
    this.activeColor = AppColors.primaryNeon,
  });

  final IconData icon;
  final int count;
  final VoidCallback? onTap;
  final bool isActive;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    final Color tint = isActive
        ? activeColor
        : (enabled ? AppColors.textGray : const Color(0xFF4A4A4A));

    final Widget button = Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: tint, size: 17.sp),
          if (count > 0) ...[
            SizedBox(width: 6.w),
            Text(
              '$count',
              style: GoogleFonts.inter(
                color: tint,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );

    if (!enabled) return button;

    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: button,
      ),
    );
  }
}
