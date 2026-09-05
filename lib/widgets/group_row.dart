import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/group.dart';
import '../styles/app_color.dart';
import 'bulkr_image.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';

/// One group in a list.
class GroupRow extends StatelessWidget {
  const GroupRow({
    super.key,
    required this.group,
    required this.onToggleMembership,
    this.onOpen,
  });

  final Group group;
  final VoidCallback onToggleMembership;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 10.h),
        child: Row(
          children: [
            GroupAvatar(
              url: group.smallImageUrl,
              name: group.name,
              size: 44.w,
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
                          group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (group.isPrivate) ...[
                        SizedBox(width: 6.w),
                        Icon(
                          Icons.lock_outline,
                          color: AppColors.textGray,
                          size: 12.sp,
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'group_stats'.tr(namedArgs: {
                      'members': '${group.memberCount}',
                      'posts': '${group.postCount}',
                    }),
                    style: GoogleFonts.inter(
                      color: AppColors.textGray,
                      fontSize: 10.sp,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            // An owner gets no button. They cannot leave their own group —
            // the policy refuses it — and "joined" on a group you created
            // states the obvious.
            if (group.isOwner)
              Text(
                'group_owner'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppColors.primaryNeon,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.9,
                ),
              )
            else
              GroupJoinButton(
                isMember: group.isMember,
                onTap: onToggleMembership,
                isCompact: true,
              ),
          ],
        ),
      ),
    );
  }
}

/// Join, or leave.
class GroupJoinButton extends StatelessWidget {
  const GroupJoinButton({
    super.key,
    required this.isMember,
    required this.onTap,
    this.isBusy = false,
    this.isCompact = false,
  });

  final bool isMember;
  final VoidCallback onTap;
  final bool isBusy;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final Color foreground = isMember ? AppColors.textGray : Colors.black;

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
            color: isMember ? Colors.transparent : AppColors.buttonNeon,
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color: isMember ? AppColors.darkBorder : AppColors.buttonNeon,
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
                  (isMember ? 'group_leave' : 'group_join').tr().toUpperCase(),
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

/// A group's picture, or its initial when it has none.
///
/// Square with rounded corners rather than circular, which is how a group
/// reads as a place and a person reads as a person.
class GroupAvatar extends StatelessWidget {
  const GroupAvatar({
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.2),
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
    final String initial =
        name.trim().isEmpty ? '#' : name.trim()[0].toUpperCase();

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
