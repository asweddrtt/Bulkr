import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/person.dart';
import '../styles/app_color.dart';
import 'bulkr_image.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';

/// Follow, or unfollow.
///
/// Filled when there is something to do and outlined once it is done, which is
/// the convention every app with a follow button has settled on for a reason:
/// the loud state is the call to action, and "following" is a status rather
/// than an invitation.
class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.isFollowing,
    required this.onTap,
    this.isBusy = false,
    this.isCompact = false,
  });

  final bool isFollowing;
  final VoidCallback onTap;

  /// A write is in flight. Only used where following is not optimistic; in the
  /// lists it never is, because a follow button that waits feels broken.
  final bool isBusy;

  /// The smaller version, for a row in a list rather than a profile header.
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final Color background =
        isFollowing ? Colors.transparent : AppColors.buttonNeon;
    final Color foreground = isFollowing ? AppColors.textGray : Colors.black;

    return PressScale(
      child: GestureDetector(
        onTap: isBusy ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.enter,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12.w : 20.w,
            vertical: isCompact ? 7.h : 10.h,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color: isFollowing ? AppColors.darkBorder : AppColors.buttonNeon,
            ),
          ),
          child: isBusy
              ? SizedBox(
                  width: isCompact ? 11.sp : 13.sp,
                  height: isCompact ? 11.sp : 13.sp,
                  child: CircularProgressIndicator(
                    color: foreground,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  (isFollowing ? 'unfollow_action' : 'follow_action')
                      .tr()
                      .toUpperCase(),
                  style: GoogleFonts.inter(
                    color: foreground,
                    fontSize: isCompact ? 9.sp : 11.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.9,
                  ),
                ),
        ),
      ),
    );
  }
}

/// One person in a list: who they are, and the button.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.person,
    required this.onToggleFollow,
    this.onOpen,
    this.isBusy = false,
  });

  final Person person;

  final VoidCallback onToggleFollow;

  /// Opens their profile.
  final VoidCallback? onOpen;

  /// A follow write is in flight for this row. Per-row rather than per-list, so
  /// one slow request does not freeze every other button on screen.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Row(
          children: [
            PersonAvatar(
              url: person.avatarUrl,
              name: person.name,
              size: 40.w,
            ),
            SizedBox(width: 12.w),
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
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (person.isTrainer) ...[
                        SizedBox(width: 6.w),
                        const TrainerBadge(),
                      ],
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    // Posts rather than followers. It is the number that
                    // answers the question the reader is actually asking —
                    // will following this account put anything in my feed.
                    'person_post_count'
                        .tr(namedArgs: {'count': '${person.postCount}'}),
                    style: GoogleFonts.inter(
                      color: AppColors.textGray,
                      fontSize: 10.sp,
                    ),
                  ),
                ],
              ),
            ),
            if (person.isFollowable) ...[
              SizedBox(width: 10.w),
              FollowButton(
                isFollowing: person.isFollowedByMe,
                onTap: onToggleFollow,
                isBusy: isBusy,
                isCompact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The marker on a trainer's name.
///
/// Says "trainer", not "verified", and the difference is deliberate: nothing
/// checks the claim, and a badge that implies it was checked would be a lie the
/// UI is telling on the account's behalf.
class TrainerBadge extends StatelessWidget {
  const TrainerBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: AppColors.primaryNeon.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3.r),
        border: Border.all(color: AppColors.primaryNeon.withValues(alpha: 0.4)),
      ),
      child: Text(
        'trainer_badge'.tr().toUpperCase(),
        style: GoogleFonts.inter(
          color: AppColors.primaryNeon,
          fontSize: 8.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// Someone's picture, or their initial when they have none.
///
/// Shared rather than reimplemented per screen — the feed card, the comments
/// sheet and the people lists all draw the same thing, and three copies of it
/// is how they drift apart.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.url,
    required this.name,
    required this.size,
  });

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: url == null || url!.isEmpty
            ? _buildInitial()
            : BulkrImage(
                url: url!,
                width: size,
                height: size,
                fallback: _buildInitial(),
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
            fontSize: size * 0.42,
          ),
        ),
      ),
    );
  }
}
