import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../data/moderation_repository.dart';
import '../models/person.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/person_row.dart';

/// Who this user has blocked, and the way back.
///
/// A block has to be undoable somewhere, and nowhere else in the app can show
/// it: a blocked person does not appear in search, in a feed, or on a post, so
/// the only place their name still exists is this list.
///
/// Reads the repository directly rather than through a cubit. It is one query
/// and one write, the screen is opened rarely, and a cubit for it would be
/// three files that only ever say what these thirty lines say.
class BlockedPeopleScreen extends StatefulWidget {
  const BlockedPeopleScreen({super.key});

  /// Opens the list, and refreshes the feed on the way out.
  ///
  /// Unblocking changes what the feed may contain, the same way following
  /// somebody does, and coming back to a feed that has not noticed is the
  /// moment it looks broken.
  static Future<void> open(BuildContext context) async {
    final ModerationRepository moderation = context.read<ModerationRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RepositoryProvider.value(
          value: moderation,
          child: const BlockedPeopleScreen(),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  State<BlockedPeopleScreen> createState() => _BlockedPeopleScreenState();
}

class _BlockedPeopleScreenState extends State<BlockedPeopleScreen> {
  List<Person>? _people;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Person> people =
          await context.read<ModerationRepository>().blockedPeople();
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

  Future<void> _unblock(Person person) async {
    final ModerationRepository moderation =
        context.read<ModerationRepository>();

    // Optimistic: the row is gone from a list whose whole purpose is to be
    // emptied, and a failure reloads it back.
    setState(() {
      _people = _people?.where((other) => other.id != person.id).toList();
    });

    try {
      await moderation.unblock(person.id);
    } catch (_) {
      await _load();
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
          'blocked_title'.tr().toUpperCase(),
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
              ? _Message(
                  text: _error == null
                      ? 'blocked_empty'.tr()
                      : ['blocked_failed'.tr(), _error!].join('\n\n'),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
                  itemCount: people.length,
                  separatorBuilder: (_, __) => SizedBox(height: 4.h),
                  itemBuilder: (_, index) => _BlockedRow(
                    person: people[index],
                    onUnblock: () => _unblock(people[index]),
                  ),
                ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  const _BlockedRow({required this.person, required this.onUnblock});

  final Person person;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
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
                Text(
                  person.name,
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
                  '@${person.username}',
                  style: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          PressScale(
            child: GestureDetector(
              onTap: onUnblock,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6.r),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Text(
                  'blocked_unblock'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 10.sp,
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
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 12.sp,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
