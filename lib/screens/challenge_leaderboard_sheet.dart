import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/challenge_repository.dart';
import '../models/challenge.dart';
import '../styles/app_color.dart';
import '../widgets/person_row.dart';

/// A challenge's standings.
///
/// Reads through `challenge_leaderboard()`, a SECURITY DEFINER function, and it
/// has to: `challenge_participants` is readable only by its own participant,
/// because the row carries the weight they started at. The function returns
/// deltas — how much each person has gained — and never a weight.
///
/// So every number on this screen is a difference. Nobody's bodyweight appears
/// here, and none can be worked out from what does.
class ChallengeLeaderboardSheet extends StatefulWidget {
  const ChallengeLeaderboardSheet({
    super.key,
    required this.challenge,
    required this.repository,
  });

  final Challenge challenge;
  final ChallengeRepository repository;

  static Future<void> show(BuildContext context, Challenge challenge) {
    final ChallengeRepository repository = context.read<ChallengeRepository>();

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ChallengeLeaderboardSheet(
        challenge: challenge,
        repository: repository,
      ),
    );
  }

  @override
  State<ChallengeLeaderboardSheet> createState() =>
      _ChallengeLeaderboardSheetState();
}

class _ChallengeLeaderboardSheetState extends State<ChallengeLeaderboardSheet> {
  /// Held as a future and rendered through a FutureBuilder rather than through
  /// a cubit. There is one read, nothing writes, and nothing else on the
  /// screen depends on it — a cubit here would be three files to hold one
  /// list.
  late Future<List<ChallengeStanding>> _standings;

  @override
  void initState() {
    super.initState();
    _standings = widget.repository.fetchLeaderboard(widget.challenge.id);
  }

  void _reload() {
    setState(() {
      _standings = widget.repository.fetchLeaderboard(widget.challenge.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          Flexible(
            child: FutureBuilder<List<ChallengeStanding>>(
              future: _standings,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.h),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primaryNeon,
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _buildMessage(
                    'challenge_leaderboard_failed'.tr(),
                    onRetry: _reload,
                  );
                }

                final List<ChallengeStanding> standings =
                    snapshot.data ?? const [];

                if (standings.isEmpty) {
                  return _buildMessage('challenge_leaderboard_empty'.tr());
                }

                return ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 20.h),
                  itemCount: standings.length,
                  separatorBuilder: (_, __) =>
                      Divider(color: AppColors.darkBorder, height: 1),
                  itemBuilder: (context, index) => _StandingRow(
                    standing: standings[index],
                    rank: index + 1,
                    goal: widget.challenge.goalAmount,
                    unitKey: widget.challenge.metric.unitKey,
                  ),
                );
              },
            ),
          ),
          SafeArea(top: false, child: SizedBox(height: 8.h)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 12.w, 10.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'challenge_leaderboard_title'.tr().toUpperCase(),
                  style: GoogleFonts.anton(
                    color: Colors.white,
                    fontSize: 16.sp,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  widget.challenge.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.all(8.w),
              child: Icon(Icons.close, color: Colors.white, size: 19.sp),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String text, {VoidCallback? onRetry}) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 30.w, vertical: 34.h),
      child: Column(
        children: [
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
            SizedBox(height: 14.h),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'retry'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppColors.primaryNeon,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.standing,
    required this.rank,
    required this.goal,
    required this.unitKey,
  });

  final ChallengeStanding standing;
  final int rank;
  final double goal;
  final String unitKey;

  @override
  Widget build(BuildContext context) {
    final double progress = standing.progressTowards(goal);

    return Container(
      // The reader's own row is tinted, so they can find themselves in a long
      // list without counting.
      color: standing.isMe
          ? AppColors.primaryNeon.withValues(alpha: 0.06)
          : Colors.transparent,
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
      child: Row(
        children: [
          SizedBox(
            width: 22.w,
            child: Text(
              '$rank',
              style: GoogleFonts.anton(
                // Only the top three get the accent. Every rank highlighted is
                // no rank highlighted.
                color: rank <= 3 ? AppColors.primaryNeon : AppColors.textGray,
                fontSize: 14.sp,
              ),
            ),
          ),
          PersonAvatar(
            url: standing.avatarUrl,
            name: standing.name,
            size: 30.w,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  standing.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 5.h),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2.r),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3.h,
                    backgroundColor: AppColors.darkBorder,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primaryNeon,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          Text(
            // "No data" rather than a zero. A participant who has never
            // weighed in has not gained nothing — nothing is known, and
            // printing 0.0 would rank them above everyone who has lost weight.
            standing.hasData && standing.gainedKg != null
                ? 'challenge_gained'.tr(namedArgs: {
                    'amount': _formatGain(standing.gainedKg!),
                    'unit': unitKey.tr(),
                  })
                : 'challenge_no_data'.tr(),
            style: GoogleFonts.inter(
              color: standing.hasData ? Colors.white : AppColors.textGray,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Signed, so a loss reads as a loss rather than as a smaller gain.
  static String _formatGain(double amount) {
    final String sign = amount > 0 ? '+' : '';
    if (amount == amount.roundToDouble()) return '$sign${amount.round()}';
    return '$sign${amount.toStringAsFixed(1)}';
  }
}
