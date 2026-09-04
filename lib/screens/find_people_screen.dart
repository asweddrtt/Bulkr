import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../cubit/people/people_cubit.dart';
import '../data/follow_repository.dart';
import '../models/person.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/person_row.dart';
import 'author_profile_screen.dart';

/// Who to follow.
///
/// The screen For You's empty state points at, and the answer to the cold-start
/// problem: a new account follows nobody, so the tab it lands on is empty, and
/// "follow some people" is only useful advice if there is somewhere to do it.
class FindPeopleScreen extends StatelessWidget {
  const FindPeopleScreen({super.key});

  /// Opens the screen, and refreshes For You on the way out.
  ///
  /// The refresh is unconditional rather than tracking whether anything
  /// changed. Following someone changes what the feed contains, and getting
  /// back to a feed that has not noticed is the exact moment the feature looks
  /// broken — one cheap query is a fair price for that never happening.
  static Future<void> open(BuildContext context) async {
    final FollowRepository follows = context.read<FollowRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => PeopleCubit(followRepository: follows)..load(),
          child: BlocProvider.value(
            value: feed,
            child: const FindPeopleScreen(),
          ),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PeopleCubit, PeopleState>(
      listenWhen: (previous, current) =>
          current.actionErrorKey != null &&
          previous.actionErrorKey != current.actionErrorKey,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2A2A2A),
              content: Text(
                state.actionErrorDetail ?? state.actionErrorKey!.tr(),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
              ),
            ),
          );
        context.read<PeopleCubit>().clearNotice();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Column(
            children: [
              const _Header(),
              const _SearchField(),
              SizedBox(height: 8.h),
              const Expanded(child: _Body()),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 20.w, 8.h),
      child: Row(
        children: [
          PressScale(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: Icon(Icons.arrow_back, color: Colors.white, size: 20.sp),
              ),
            ),
          ),
          Expanded(
            child: Text(
              'find_people_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 18.sp,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField();

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: AppColors.textGray, size: 18.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (value) =>
                    context.read<PeopleCubit>().search(value),
                textInputAction: TextInputAction.search,
                // Handles are lower case and the field should not fight that.
                textCapitalization: TextCapitalization.none,
                autocorrect: false,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'find_people_hint'.tr(),
                  hintStyle: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ),
            BlocBuilder<PeopleCubit, PeopleState>(
              buildWhen: (previous, current) =>
                  previous.hasQuery != current.hasQuery,
              builder: (context, state) => state.hasQuery
                  ? GestureDetector(
                      onTap: () {
                        _controller.clear();
                        context.read<PeopleCubit>().clearSearch();
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(6.w),
                        child: Icon(
                          Icons.close,
                          color: AppColors.textGray,
                          size: 15.sp,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PeopleCubit, PeopleState>(
      builder: (context, state) {
        if (state.isSearching && state.results.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryNeon),
          );
        }

        switch (state.status) {
          case PeopleStatus.initial:
          case PeopleStatus.loading:
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            );

          case PeopleStatus.failure:
            return _Message(
              icon: Icons.cloud_off_outlined,
              title: 'find_people_failed'.tr(),
              body: state.errorMessage,
              actionLabel: 'retry'.tr(),
              onAction: () => context.read<PeopleCubit>().load(),
            );

          case PeopleStatus.ready:
            if (state.isNoResults) {
              return _Message(
                icon: Icons.person_search_outlined,
                title: 'find_people_no_results'.tr(),
                body: 'find_people_no_results_body'.tr(),
              );
            }

            if (state.hasNoSuggestions) {
              return _Message(
                icon: Icons.groups_outlined,
                title: 'find_people_none'.tr(),
                body: 'find_people_none_body'.tr(),
              );
            }

            return RefreshIndicator(
              color: AppColors.primaryNeon,
              backgroundColor: const Color(0xFF1A1A1A),
              onRefresh: () => context.read<PeopleCubit>().refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 30.h),
                itemCount: state.visiblePeople.length,
                separatorBuilder: (_, __) => Divider(
                  color: AppColors.darkBorder,
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  final Person person = state.visiblePeople[index];

                  return PersonRow(
                    key: ValueKey(person.id),
                    person: person,
                    onToggleFollow: () =>
                        context.read<PeopleCubit>().toggleFollow(person),
                    onOpen: () => AuthorProfileScreen.open(context, person.id),
                  );
                },
              ),
            );
        }
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textGray, size: 32.sp),
            SizedBox(height: 14.h),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 16.sp,
                letterSpacing: 1.1,
              ),
            ),
            if (body != null) ...[
              SizedBox(height: 10.h),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 12.sp,
                  height: 1.5,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: 18.h),
              PressScale(
                child: GestureDetector(
                  onTap: onAction,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 11.h),
                    decoration: BoxDecoration(
                      color: AppColors.buttonNeon,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      actionLabel!.toUpperCase(),
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
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
