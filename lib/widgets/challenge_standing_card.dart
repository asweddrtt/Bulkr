import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/challenge_repository.dart';
import '../models/challenge.dart';
import '../screens/challenge_leaderboard_sheet.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';
import 'bulkr_snack_bar.dart';

/// Where you stand, on the screen you already open.
///
/// ## Why the dashboard
///
/// A challenge you had joined lived in two places: its announcement post,
/// while it happened to be on screen, and a list three taps inside the account
/// sheet. Neither is somewhere anybody looks. So a challenge was a thing you
/// entered and then forgot about, which is indistinguishable from a thing you
/// did not enter.
///
/// The dashboard is the first screen after launch for most sessions. Putting
/// the standing here is the difference between a leaderboard you have to
/// remember to check and one that checks in with you.
///
/// ## The line that matters is the last one
///
/// "You are third" is a fact. "Sara is 0.6 kg ahead of you" is a reason to
/// come back tomorrow, and it is the whole reason `my_challenge_standings()`
/// returns the row above yours rather than this card fetching a leaderboard it
/// would draw one line of.
///
/// ## It draws nothing when there is nothing
///
/// No empty state, no "join a challenge!" prompt. Most accounts are in nothing
/// most of the time, and a home screen that advertises an unused feature on
/// every single visit is a home screen with an advert on it. The card exists
/// when there is a standing to report and does not exist otherwise.
class ChallengeStandingCard extends StatefulWidget {
  const ChallengeStandingCard({super.key, this.reloadOn});

  /// Reloads whenever this emits.
  ///
  /// The dashboard passes its own cubit's stream, so pull-to-refresh refreshes
  /// the standings along with everything else on the screen — without this
  /// card needing to be wired into the refresh handler, and without the
  /// dashboard needing to know that challenges exist.
  ///
  /// Throttled, because that stream emits on far more than a reload: see
  /// [_minimumBetweenLoads].
  final Stream<Object?>? reloadOn;

  @override
  State<ChallengeStandingCard> createState() => _ChallengeStandingCardState();
}

class _ChallengeStandingCardState extends State<ChallengeStandingCard> {
  /// The floor between two reads driven by [ChallengeStandingCard.reloadOn].
  ///
  /// A cubit emits for reasons that are not new data — a save starting, a save
  /// finishing — and a standing changes when somebody weighs in, which is once
  /// a day at most. Half a minute is far below anything a person would notice
  /// and far above the churn.
  static const Duration _minimumBetweenLoads = Duration(seconds: 30);

  List<MyChallengeStanding> _standings = const <MyChallengeStanding>[];
  StreamSubscription<Object?>? _reloads;
  DateTime? _lastLoad;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _reloads = widget.reloadOn?.listen((_) => _maybeReload());
  }

  @override
  void dispose() {
    _reloads?.cancel();
    super.dispose();
  }

  void _maybeReload() {
    final DateTime? last = _lastLoad;
    if (last != null &&
        DateTime.now().difference(last) < _minimumBetweenLoads) {
      return;
    }
    _load();
  }

  /// Silent in both directions.
  ///
  /// No spinner, because a card that is not there yet cannot be waited for —
  /// there is nothing on screen for a spinner to sit inside, and reserving
  /// space for a card that may not appear puts a hole in the dashboard on
  /// every launch. And no error either: a standing that could not be read is
  /// not something the reader can act on, and it is not worth a red box on the
  /// home screen of a food app. It comes back on the next refresh.
  Future<void> _load() async {
    if (_busy) return;
    _busy = true;
    _lastLoad = DateTime.now();

    try {
      final List<MyChallengeStanding> standings =
          await context.read<ChallengeRepository>().fetchMyStandings();
      if (!mounted) return;
      setState(() => _standings = standings);
    } catch (error) {
      debugPrint('Bulkr: challenge standings failed — $error');
    } finally {
      _busy = false;
    }
  }

  /// Opens the full leaderboard.
  ///
  /// Re-reads the challenge rather than rebuilding one out of the standing.
  /// The standing carries everything the sheet *draws* — but assembling a
  /// `Challenge` from it would mean inventing the fields it does not carry,
  /// and a model with a made-up `createdBy` in it is a model that will
  /// eventually be passed somewhere that reads it.
  Future<void> _open(MyChallengeStanding standing) async {
    final ChallengeRepository challenges = context.read<ChallengeRepository>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    Challenge? challenge;
    try {
      challenge = await challenges.fetchForPost(standing.postId);
    } catch (error) {
      debugPrint('Bulkr: challenge lookup failed — $error');
    }

    if (!mounted) return;

    if (challenge == null) {
      BulkrSnackBar.showOn(
        messenger,
        'challenge_leaderboard_failed'.tr(),
        tone: SnackTone.danger,
      );
      return;
    }

    await ChallengeLeaderboardSheet.show(context, challenge);
  }

  @override
  Widget build(BuildContext context) {
    if (_standings.isEmpty) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        for (final MyChallengeStanding standing in _standings) ...<Widget>[
          _StandingTile(standing: standing, onTap: () => _open(standing)),
          SizedBox(height: 16.h),
        ],
      ],
    );
  }
}

class _StandingTile extends StatelessWidget {
  const _StandingTile({required this.standing, required this.onTap});

  final MyChallengeStanding standing;
  final VoidCallback onTap;

  static const Color _card = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.emoji_events_outlined,
                    color: AppColors.primaryNeon,
                    size: 16.sp,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      standing.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    _deadline(),
                    style: GoogleFonts.inter(
                      // Red on the last day. It is the one day where opening
                      // the app still changes the result.
                      color: standing.daysLeft <= 1
                          ? const Color(0xFFFF6B6B)
                          : AppColors.textGray,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  // Position as a number rather than an ordinal: "2nd" needs a
                  // rule per language, and every language can read "#2".
                  Text(
                    'challenge_rank'.tr(
                      namedArgs: <String, String>{'rank': '${standing.rank}'},
                    ),
                    style: GoogleFonts.anton(
                      color: AppColors.primaryNeon,
                      fontSize: 26.sp,
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Padding(
                    padding: EdgeInsets.only(bottom: 5.h),
                    child: Text(
                      'challenge_rank_of'.tr(
                        namedArgs: <String, String>{
                          'count': '${standing.participantCount}',
                        },
                      ),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 11.sp,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: EdgeInsets.only(bottom: 5.h),
                    child: Text(
                      standing.hasData && standing.score != null
                          ? 'challenge_score_of_goal'.tr(
                              namedArgs: <String, String>{
                                'score': standing.metric.format(
                                  standing.score!,
                                ),
                                'goal': standing.metric.format(
                                  standing.goalAmount,
                                ),
                                'unit': standing.metric.unitKey.tr(),
                              },
                            )
                          : 'challenge_no_data'.tr(),
                      style: GoogleFonts.inter(
                        color: standing.hasData
                            ? Colors.white
                            : AppColors.textGray,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              ClipRRect(
                borderRadius: BorderRadius.circular(3.r),
                child: LinearProgressIndicator(
                  value: standing.progress,
                  minHeight: 5.h,
                  backgroundColor: AppColors.darkBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primaryNeon,
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                _chase(),
                style: GoogleFonts.inter(
                  color: AppColors.offWhiteMuted,
                  fontSize: 11.sp,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _deadline() {
    final int left = standing.daysLeft;
    if (left <= 0) return 'challenge_ends_today'.tr();

    return 'challenge_days_left'.tr(
      namedArgs: <String, String>{'days': '$left'},
    );
  }

  /// The last line: who to catch, or that there is nobody left to catch.
  String _chase() {
    if (standing.isLeading) {
      return standing.participantCount > 1
          ? 'challenge_leading'.tr()
          : 'challenge_only_entrant'.tr();
    }

    final double? gap = standing.gapToAhead;
    final String? name = standing.aheadName;

    // Level with the person above, or their score is unknown. Naming them is
    // still the useful half; inventing a gap of zero is not.
    if (gap == null || name == null) return 'challenge_close_behind'.tr();

    return 'challenge_ahead_of_you'.tr(
      namedArgs: <String, String>{
        'name': name,
        'amount': standing.metric.format(gap),
        'unit': standing.metric.unitKey.tr(),
      },
    );
  }
}
