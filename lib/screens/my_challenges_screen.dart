import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/challenge_repository.dart';
import '../models/challenge.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import 'challenge_leaderboard_sheet.dart';

/// The challenges this user has joined.
///
/// The leaderboard used to be reachable from exactly one place: a challenge
/// post, while it was still on screen. Scroll past it and the thing you had
/// joined was gone — standings, deadline, all of it — until the post happened
/// to come round again. A challenge you are *in* should not be something you
/// have to find.
class MyChallengesScreen extends StatefulWidget {
  const MyChallengesScreen({super.key});

  static Future<void> open(BuildContext context) {
    final ChallengeRepository challenges = context.read<ChallengeRepository>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: challenges,
          child: const MyChallengesScreen(),
        ),
      ),
    );
  }

  @override
  State<MyChallengesScreen> createState() => _MyChallengesScreenState();
}

class _MyChallengesScreenState extends State<MyChallengesScreen> {
  List<Challenge>? _challenges;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ChallengeRepository challenges = context.read<ChallengeRepository>();

    try {
      final List<Challenge> mine = await challenges.fetchMine();
      if (!mounted) return;
      setState(() {
        _challenges = mine;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _challenges = const [];
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Challenge>? challenges = _challenges;

    // Running ones first, then the finished. Someone opening this is almost
    // always looking at something still going.
    final List<Challenge> live =
        challenges?.where((c) => !c.hasEnded).toList() ?? const [];
    final List<Challenge> done =
        challenges?.where((c) => c.hasEnded).toList() ?? const [];

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'my_challenges_title'.tr().toUpperCase(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 17.sp,
            letterSpacing: 1,
          ),
        ),
      ),
      body: challenges == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            )
          : challenges.isEmpty
              ? _Notice(
                  text: _error == null
                      ? 'my_challenges_empty'.tr()
                      : ['my_challenges_failed'.tr(), _error!].join('\n\n'),
                  onRetry: _error == null ? null : _load,
                )
              : RefreshIndicator(
                  color: AppColors.primaryNeon,
                  backgroundColor: const Color(0xFF1A1A1A),
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 30.h),
                    children: [
                      for (final Challenge challenge in live)
                        _ChallengeRow(challenge: challenge),
                      if (done.isNotEmpty) ...[
                        SizedBox(height: 20.h),
                        Text(
                          'my_challenges_finished'.tr().toUpperCase(),
                          style: GoogleFonts.inter(
                            color: AppColors.textGray,
                            fontSize: 10.sp,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        for (final Challenge challenge in done)
                          _ChallengeRow(challenge: challenge),
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({required this.challenge});

  final Challenge challenge;

  @override
  Widget build(BuildContext context) {
    final bool ended = challenge.hasEnded;

    return PressScale(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ChallengeLeaderboardSheet.show(context, challenge),
        child: Container(
          margin: EdgeInsets.only(bottom: 10.h),
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Icon(
                ended ? Icons.emoji_events_outlined : Icons.bolt_rounded,
                color: ended ? AppColors.textGray : AppColors.primaryNeon,
                size: 20.sp,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: ended ? AppColors.offWhiteMuted : Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      _subtitle(),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 11.sp,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.textGray,
                size: 18.sp,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The goal, and how long is left — or that there is none left.
  String _subtitle() {
    final String goal = 'challenge_goal_short'.tr(namedArgs: {
      'amount': challenge.goalAmount.toStringAsFixed(1),
      'unit': challenge.metric.unitKey.tr(),
    });

    if (challenge.hasEnded) {
      return '$goal · ${'challenge_ended'.tr()}';
    }

    if (challenge.hasNotStarted) {
      return '$goal · ${'challenge_not_started'.tr()}';
    }

    final int daysLeft = challenge.endsAt.difference(DateTime.now()).inDays;
    return '$goal · ${'challenge_days_left'.tr(namedArgs: {
          'days': '${daysLeft < 1 ? 1 : daysLeft}',
        })}';
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
