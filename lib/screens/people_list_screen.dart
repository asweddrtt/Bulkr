import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../data/follow_repository.dart';
import '../models/person.dart';
import '../styles/app_color.dart';
import '../widgets/person_row.dart';
import 'author_profile_screen.dart';

/// Which side of the follow graph a list is showing.
enum FollowSide {
  followers('follow_list_followers', 'follow_list_followers_empty'),
  following('follow_list_following', 'follow_list_following_empty');

  const FollowSide(this.titleKey, this.emptyKey);

  final String titleKey;
  final String emptyKey;
}

/// Followers, or people followed.
///
/// One screen for both sides, because the only thing that differs is which
/// query runs — the rows, the follow buttons and the taps through to a profile
/// are identical, and two screens would be two places to fix anything about
/// them.
///
/// [FollowRepository.fetchFollowers] and `fetchFollowing` have existed since
/// slice 3 and were called by nothing. The counts on a profile were the only
/// thing the follow graph ever surfaced, and a number you cannot tap is a
/// number you have to take on trust.
class PeopleListScreen extends StatefulWidget {
  const PeopleListScreen({
    super.key,
    required this.personId,
    required this.side,
  });

  final String personId;
  final FollowSide side;

  /// Opens the list, and refreshes For You on the way out.
  ///
  /// Following somebody from here changes what the feed contains, the same way
  /// following them from search does — and coming back to a feed that has not
  /// noticed is the moment it looks broken.
  static Future<void> open(
    BuildContext context, {
    required String personId,
    required FollowSide side,
  }) async {
    final FollowRepository follows = context.read<FollowRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: follows,
          child: PeopleListScreen(personId: personId, side: side),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  State<PeopleListScreen> createState() => _PeopleListScreenState();
}

class _PeopleListScreenState extends State<PeopleListScreen> {
  List<Person>? _people;
  String? _error;

  /// Ids with a follow write in flight, so one row's spinner does not stop the
  /// others being tapped.
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final FollowRepository follows = context.read<FollowRepository>();

    try {
      final List<Person> people = widget.side == FollowSide.followers
          ? await follows.fetchFollowers(widget.personId)
          : await follows.fetchFollowing(widget.personId);

      if (!mounted) return;
      setState(() {
        _people = people;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _people = const [];
        _error = '$error';
      });
    }
  }

  /// Follows or unfollows, and leaves the row where it is.
  ///
  /// Deliberately does not remove someone from the list when they are
  /// unfollowed, even on the "following" side. A row vanishing under the
  /// finger that tapped it makes an accidental tap unrecoverable — the list is
  /// what it was when it loaded, and the next load is where it changes.
  Future<void> _toggleFollow(Person person) async {
    if (_busy.contains(person.id)) return;

    final FollowRepository follows = context.read<FollowRepository>();
    final bool next = !person.isFollowedByMe;

    setState(() => _busy.add(person.id));

    try {
      await follows.setFollowing(personId: person.id, isFollowing: next);
      if (!mounted) return;

      setState(() {
        _people = _people
            ?.map((other) => other.id == person.id
                ? other.copyWith(isFollowedByMe: next)
                : other)
            .toList();
      });
    } catch (_) {
      // Left as it was. The next load is the correction, and a snack bar for
      // a follow that did not take is more noise than the failure is worth.
    } finally {
      if (mounted) setState(() => _busy.remove(person.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Person>? people = _people;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.side.titleKey.tr().toUpperCase(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 17.sp,
            letterSpacing: 1,
          ),
        ),
      ),
      body: people == null
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            )
          : people.isEmpty
              ? _Notice(
                  text: _error == null
                      ? widget.side.emptyKey.tr()
                      : ['follow_list_failed'.tr(), _error!].join('\n\n'),
                  onRetry: _error == null ? null : _load,
                )
              : RefreshIndicator(
                  color: AppColors.primaryNeon,
                  backgroundColor: const Color(0xFF1A1A1A),
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
                    itemCount: people.length,
                    itemBuilder: (_, index) {
                      final Person person = people[index];
                      return PersonRow(
                        key: ValueKey('person-${person.id}'),
                        person: person,
                        isBusy: _busy.contains(person.id),
                        onToggleFollow: () => _toggleFollow(person),
                        onOpen: () =>
                            AuthorProfileScreen.open(context, person.id),
                      );
                    },
                  ),
                ),
    );
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
