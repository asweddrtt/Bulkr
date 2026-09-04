import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../cubit/search/search_cubit.dart';
import '../data/follow_repository.dart';
import '../data/group_repository.dart';
import '../models/group.dart';
import '../models/person.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/group_row.dart';
import '../widgets/person_row.dart';
import 'author_profile_screen.dart';
import 'group_screen.dart';
import 'groups_screen.dart';

/// One field, both kinds of thing.
///
/// Replaces the two icons the feed header used to carry — one for people, one
/// for groups — because "find the thing I am thinking of" is a single
/// intention, and making someone choose a tab before they can type is making
/// them answer a question about the app's data model.
///
/// Before anything is typed it shows accounts worth following and the groups
/// the user is in, so the screen is useful on arrival rather than being a
/// blank field.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  /// Opens the screen, and refreshes For You on the way out.
  ///
  /// Following someone or joining a group changes what the feed contains, so
  /// coming back to a feed that has not noticed is exactly when a feature
  /// looks broken. One cheap query is a fair price for that never happening.
  static Future<void> open(BuildContext context) async {
    final FollowRepository follows = context.read<FollowRepository>();
    final GroupRepository groups = context.read<GroupRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => SearchCubit(
            followRepository: follows,
            groupRepository: groups,
          )..load(),
          child: BlocProvider.value(
            value: feed,
            child: const SearchScreen(),
          ),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SearchCubit, SearchState>(
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
        context.read<SearchCubit>().clearNotice();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Column(
            children: [
              const _Header(),
              SizedBox(height: 10.h),
              const Expanded(child: _Body()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The back arrow and the field, on one line.
///
/// No title. The field is the title — a screen whose entire purpose is one
/// text input does not also need a word above it saying "Search".
class _Header extends StatefulWidget {
  const _Header();

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 20.w, 0),
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
          SizedBox(width: 4.w),
          Expanded(
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
                          context.read<SearchCubit>().search(value),
                      // Opens focused. The user tapped a search icon; they came
                      // here to type.
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13.sp,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: 'search_hint'.tr(),
                        hintStyle: GoogleFonts.inter(
                          color: AppColors.textGray,
                          fontSize: 13.sp,
                        ),
                      ),
                    ),
                  ),
                  BlocBuilder<SearchCubit, SearchState>(
                    buildWhen: (previous, current) =>
                        previous.hasQuery != current.hasQuery,
                    builder: (context, state) => state.hasQuery
                        ? GestureDetector(
                            onTap: () {
                              _controller.clear();
                              context.read<SearchCubit>().clearSearch();
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
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        if (state.isSearching && !state.hasPeople && !state.hasGroups) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryNeon),
          );
        }

        switch (state.status) {
          case SearchStatus.initial:
          case SearchStatus.loading:
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            );

          case SearchStatus.failure:
            return _Message(
              icon: Icons.cloud_off_outlined,
              title: 'search_failed'.tr(),
              body: state.errorMessage,
              actionLabel: 'retry'.tr(),
              onAction: () => context.read<SearchCubit>().load(),
            );

          case SearchStatus.ready:
            if (state.isNoResults) {
              return _Message(
                icon: Icons.search_off,
                title: 'search_no_results'.tr(),
                body: 'search_no_results_body'.tr(),
              );
            }

            return RefreshIndicator(
              color: AppColors.primaryNeon,
              backgroundColor: const Color(0xFF1A1A1A),
              onRefresh: () => context.read<SearchCubit>().refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 30.h),
                children: [
                  if (state.hasPeople) ...[
                    _SectionHeader(
                      label: state.hasQuery
                          ? 'search_people'.tr()
                          : 'search_suggested_people'.tr(),
                    ),
                    for (final Person person in state.visiblePeople)
                      PersonRow(
                        key: ValueKey('person-${person.id}'),
                        person: person,
                        onToggleFollow: () =>
                            context.read<SearchCubit>().toggleFollow(person),
                        onOpen: () =>
                            AuthorProfileScreen.open(context, person.id),
                      ),
                  ],
                  if (state.hasGroups) ...[
                    if (state.hasPeople) SizedBox(height: 10.h),
                    _SectionHeader(
                      label: state.hasQuery
                          ? 'search_groups'.tr()
                          : 'search_your_groups'.tr(),
                    ),
                    for (final Group group in state.visibleGroups)
                      GroupRow(
                        key: ValueKey('group-${group.id}'),
                        group: group,
                        onToggleMembership: () => context
                            .read<SearchCubit>()
                            .toggleMembership(group),
                        onOpen: () => GroupScreen.open(context, group.id),
                      ),
                  ],
                  // Always last, and always there: browsing and creating
                  // groups is not something a search field can offer, and this
                  // is the only route to it now that the header icon is gone.
                  SizedBox(height: state.isEmptyStart ? 30.h : 20.h),
                  if (state.isEmptyStart) ...[
                    _Message(
                      icon: Icons.search,
                      title: 'search_empty_start'.tr(),
                      body: 'search_empty_start_body'.tr(),
                    ),
                    SizedBox(height: 20.h),
                  ],
                  _AllGroupsRow(onTap: () => GroupsScreen.open(context)),
                ],
              ),
            );
        }
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 8.h, bottom: 4.h),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.inter(
          color: AppColors.textGray,
          fontSize: 10.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _AllGroupsRow extends StatelessWidget {
  const _AllGroupsRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.groups, color: AppColors.primaryNeon, size: 18.sp),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'search_all_groups'.tr(),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'search_all_groups_helper'.tr(),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 10.sp,
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
        padding: EdgeInsets.symmetric(horizontal: 30.w, vertical: 20.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textGray, size: 30.sp),
            SizedBox(height: 14.h),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 15.sp,
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
