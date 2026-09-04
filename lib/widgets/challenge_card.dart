import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/challenge.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';

/// The challenge strip on a post.
///
/// Deliberately a strip and not a screen. The post is the announcement — its
/// author's words, its photos, its comments — and this is the machinery
/// hanging off it: the goal, how long is left, how many are in, and the one
/// button that matters.
///
/// The leaderboard is behind a tap rather than inline. Five names and five
/// numbers on every challenge card would make the feed unreadable, and the
/// standings are something you go and look at rather than something you scroll
/// past.
class ChallengeCard extends StatelessWidget {
  const ChallengeCard({
    super.key,
    required this.challenge,
    required this.onToggleJoin,
    this.onOpenLeaderboard,
    this.isBusy = false,
  });

  final Challenge challenge;

  final VoidCallback onToggleJoin;

  /// Opens the standings. Null on a challenge with nobody in it — an empty
  /// leaderboard is a screen that says nothing.
  final VoidCallback? onOpenLeaderboard;

  /// A join write is in flight.
  final bool isBusy;

  static const Color _accent = Color(0xFFFB923C);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 0),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.local_fire_department_sharp,
                color: _accent,
                size: 15.sp,
              ),
              SizedBox(width: 7.w),
              Expanded(
                child: Text(
                  challenge.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              _Fact(
                icon: Icons.flag_outlined,
                text: 'challenge_goal'.tr(namedArgs: {
                  'amount': _formatGoal(challenge.goalAmount),
                  'unit': challenge.metric.unitKey.tr(),
                }),
              ),
              SizedBox(width: 14.w),
              _Fact(
                icon: Icons.schedule,
                text: _timing(),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              if (challenge.participantCount > 0 &&
                  onOpenLeaderboard != null) ...[
                Expanded(
                  child: PressScale(
                    child: GestureDetector(
                      onTap: onOpenLeaderboard,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(
                            Icons.leaderboard_outlined,
                            color: AppColors.textGray,
                            size: 13.sp,
                          ),
                          SizedBox(width: 6.w),
                          Flexible(
                            child: Text(
                              'challenge_participants'.tr(namedArgs: {
                                'count': '${challenge.participantCount}',
                              }),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: AppColors.textGray,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: AppColors.textGray,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    'challenge_be_first'.tr(),
                    style: GoogleFonts.inter(
                      color: AppColors.textGray,
                      fontSize: 10.sp,
                    ),
                  ),
                ),
              SizedBox(width: 10.w),
              _buildButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildButton() {
    // A finished challenge shows its state rather than a dead button. The
    // insert policy refuses a late join, so offering one would be offering
    // something the database will turn down.
    if (challenge.hasEnded) {
      return Text(
        'challenge_ended'.tr().toUpperCase(),
        style: GoogleFonts.inter(
          color: AppColors.textGray,
          fontSize: 9.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.9,
        ),
      );
    }

    final bool joined = challenge.hasJoined;

    return PressScale(
      child: GestureDetector(
        onTap: isBusy ? null : onToggleJoin,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: joined ? Colors.transparent : _accent,
            borderRadius: BorderRadius.circular(5.r),
            border: Border.all(color: joined ? AppColors.darkBorder : _accent),
          ),
          child: isBusy
              ? SizedBox(
                  width: 11.sp,
                  height: 11.sp,
                  child: CircularProgressIndicator(
                    color: joined ? AppColors.textGray : Colors.black,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  (joined ? 'challenge_leave' : 'challenge_join')
                      .tr()
                      .toUpperCase(),
                  style: GoogleFonts.inter(
                    color: joined ? AppColors.textGray : Colors.black,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.9,
                  ),
                ),
        ),
      ),
    );
  }

  /// The one line about time, which says a different thing in each of the
  /// three states a challenge can be in.
  String _timing() {
    if (challenge.hasEnded) return 'challenge_finished'.tr();

    if (challenge.hasNotStarted) {
      return 'challenge_starts_in'
          .tr(namedArgs: {'days': '${challenge.daysUntilStart}'});
    }

    final int days = challenge.daysLeft;
    // Under a day left is "today", not "0 days left" — which reads as already
    // over and would stop people joining on the last day.
    if (days < 1) return 'challenge_ends_today'.tr();

    return 'challenge_days_left'.tr(namedArgs: {'days': '$days'});
  }

  /// Trims a trailing `.0`, so a 5 kg goal reads as "5" and a 2.5 kg one still
  /// reads as "2.5".
  static String _formatGoal(double amount) {
    if (amount == amount.roundToDouble()) return '${amount.round()}';
    return amount.toStringAsFixed(1);
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textGray, size: 12.sp),
        SizedBox(width: 5.w),
        Text(
          text,
          style: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 10.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
