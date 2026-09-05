import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../cubit/groups/groups_cubit.dart';
import '../data/group_repository.dart';
import '../models/group.dart';
import '../styles/app_color.dart';
import '../widgets/animations/motion.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/group_row.dart';
import 'group_screen.dart';

/// Groups: the ones you're in, the ones you could join, and starting one.
class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  /// Opens the screen, and refreshes For You on the way out.
  ///
  /// Joining a group changes what the feed contains, the same way following
  /// someone does — and getting back to a feed that has not noticed is when a
  /// feature looks broken.
  static Future<void> open(BuildContext context) async {
    final GroupRepository groups = context.read<GroupRepository>();
    final FeedCubit feed = context.read<FeedCubit>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => GroupsCubit(groupRepository: groups)..load(),
          child: BlocProvider.value(
            value: feed,
            child: const GroupsScreen(),
          ),
        ),
      ),
    );

    await feed.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<GroupsCubit, GroupsState>(
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
        context.read<GroupsCubit>().clearNotice();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        floatingActionButton: const _CreateButton(),
        body: SafeArea(
          child: Column(
            children: [
              const _Header(),
              const _SearchField(),
              SizedBox(height: 10.h),
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
              'groups_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 18.sp,
                letterSpacing: 1.2,
              ),
            ),
          ),
          BlocBuilder<GroupsCubit, GroupsState>(
            buildWhen: (previous, current) =>
                previous.tab != current.tab ||
                previous.hasQuery != current.hasQuery,
            // The tabs are hidden while searching: results cut across both, so
            // a highlighted tab would be claiming to filter something it is
            // not.
            builder: (context, state) =>
                state.hasQuery ? const SizedBox.shrink() : const _Tabs(),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GroupsCubit, GroupsState>(
      buildWhen: (previous, current) => previous.tab != current.tab,
      builder: (context, state) => Container(
        padding: EdgeInsets.all(3.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            _Tab(
              label: 'groups_mine'.tr(),
              isSelected: state.tab == GroupsTab.mine,
              onTap: () => context.read<GroupsCubit>().selectTab(GroupsTab.mine),
            ),
            _Tab(
              label: 'groups_discover'.tr(),
              isSelected: state.tab == GroupsTab.discover,
              onTap: () =>
                  context.read<GroupsCubit>().selectTab(GroupsTab.discover),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.enter,
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNeon : Colors.transparent,
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: isSelected ? Colors.black : AppColors.textGray,
              fontSize: 9.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ),
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
                onChanged: (value) => context.read<GroupsCubit>().search(value),
                textInputAction: TextInputAction.search,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'groups_search_hint'.tr(),
                  hintStyle: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ),
            BlocBuilder<GroupsCubit, GroupsState>(
              buildWhen: (previous, current) =>
                  previous.hasQuery != current.hasQuery,
              builder: (context, state) => state.hasQuery
                  ? GestureDetector(
                      onTap: () {
                        _controller.clear();
                        context.read<GroupsCubit>().clearSearch();
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
    return BlocBuilder<GroupsCubit, GroupsState>(
      builder: (context, state) {
        if (state.isSearching && state.results.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primaryNeon),
          );
        }

        switch (state.status) {
          case GroupsStatus.initial:
          case GroupsStatus.loading:
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            );

          case GroupsStatus.failure:
            return _Message(
              icon: Icons.cloud_off_outlined,
              title: 'groups_load_failed'.tr(),
              body: state.errorMessage,
              actionLabel: 'retry'.tr(),
              onAction: () => context.read<GroupsCubit>().load(),
            );

          case GroupsStatus.ready:
            if (state.isNoResults) {
              return _Message(
                icon: Icons.search_off,
                title: 'groups_no_results'.tr(),
                body: 'groups_no_results_body'.tr(),
              );
            }

            if (state.isTabEmpty) {
              return _Message(
                icon: Icons.groups_outlined,
                title: state.tab == GroupsTab.mine
                    ? 'groups_empty_mine'.tr()
                    : 'groups_empty_discover'.tr(),
                body: state.tab == GroupsTab.mine
                    ? 'groups_empty_mine_body'.tr()
                    : 'groups_empty_discover_body'.tr(),
                actionLabel: state.tab == GroupsTab.mine
                    ? 'groups_browse'.tr()
                    : 'groups_create'.tr(),
                onAction: state.tab == GroupsTab.mine
                    ? () => context
                        .read<GroupsCubit>()
                        .selectTab(GroupsTab.discover)
                    : () => GroupEditorSheet.open(context),
              );
            }

            return RefreshIndicator(
              color: AppColors.primaryNeon,
              backgroundColor: const Color(0xFF1A1A1A),
              onRefresh: () => context.read<GroupsCubit>().refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 90.h),
                itemCount: state.visibleGroups.length,
                separatorBuilder: (_, __) =>
                    Divider(color: AppColors.darkBorder, height: 1),
                itemBuilder: (context, index) {
                  final Group group = state.visibleGroups[index];

                  return GroupRow(
                    key: ValueKey(group.id),
                    group: group,
                    onToggleMembership: () =>
                        context.read<GroupsCubit>().toggleMembership(group),
                    onOpen: () => GroupScreen.open(context, group.id),
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

class _CreateButton extends StatelessWidget {
  const _CreateButton();

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: () => GroupEditorSheet.open(context),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 13.h),
          decoration: BoxDecoration(
            color: AppColors.buttonNeon,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: Colors.black, size: 18.sp),
              SizedBox(width: 8.w),
              Text(
                'groups_create'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  color: Colors.black,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starting a group: a name, an optional description, and public or private.
///
/// A sheet rather than a screen. There are three fields, and a full screen for
/// three fields makes creating a group feel like a bigger commitment than it
/// is — which is the opposite of what an app with no groups in it needs.
class GroupEditorSheet extends StatefulWidget {
  const GroupEditorSheet({super.key});

  /// Shows the sheet and hands back whatever was created.
  ///
  /// Split from [open] because the search screen offers this too and has no
  /// [GroupsCubit] to tell about it — the sheet itself only needs
  /// [GroupRepository], and requiring a cubit it never uses is what would keep
  /// creating a group locked to one screen.
  static Future<Group?> create(BuildContext context) {
    return showModalBottomSheet<Group>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const GroupEditorSheet(),
    );
  }

  /// Creates a group and tells the surrounding [GroupsCubit] about it, so the
  /// list it came from shows it without a refetch.
  static Future<void> open(BuildContext context) async {
    final GroupsCubit cubit = context.read<GroupsCubit>();

    final Group? created = await create(context);

    if (created != null) cubit.groupCreated(created);
  }

  @override
  State<GroupEditorSheet> createState() => _GroupEditorSheetState();
}

class _GroupEditorSheetState extends State<GroupEditorSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  GroupDraft _draft = const GroupDraft();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_draft.canSubmit || _isSaving) return;

    final GroupRepository repository = context.read<GroupRepository>();
    final NavigatorState navigator = Navigator.of(context);

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final Group created = await repository.createGroup(draft: _draft);
      if (!navigator.mounted) return;
      navigator.pop(created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(18.w),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'groups_create_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 16.sp,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 16.h),
            _Field(
              controller: _name,
              hint: 'groups_name_hint'.tr(),
              maxLength: GroupDraft.maxNameLength,
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(name: value)),
            ),
            SizedBox(height: 10.h),
            _Field(
              controller: _description,
              hint: 'groups_description_hint'.tr(),
              maxLength: GroupDraft.maxDescriptionLength,
              minLines: 2,
              maxLines: 4,
              onChanged: (value) =>
                  setState(() => _draft = _draft.copyWith(description: value)),
            ),
            SizedBox(height: 14.h),
            GestureDetector(
              onTap: () => setState(
                () => _draft = _draft.copyWith(isPrivate: !_draft.isPrivate),
              ),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Icon(
                    _draft.isPrivate ? Icons.lock : Icons.public,
                    color: AppColors.primaryNeon,
                    size: 16.sp,
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (_draft.isPrivate
                                  ? 'groups_private'
                                  : 'groups_public')
                              .tr(),
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          (_draft.isPrivate
                                  ? 'groups_private_helper'
                                  : 'groups_public_helper')
                              .tr(),
                          style: GoogleFonts.inter(
                            color: AppColors.textGray,
                            fontSize: 10.sp,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _draft.isPrivate,
                    activeThumbColor: AppColors.primaryNeon,
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(isPrivate: value),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              SizedBox(height: 10.h),
              Text(
                _error!,
                style: GoogleFonts.inter(
                  color: const Color(0xFFFF5722),
                  fontSize: 11.sp,
                ),
              ),
            ],
            SizedBox(height: 18.h),
            SizedBox(
              width: double.infinity,
              child: PressScale(
                child: GestureDetector(
                  onTap: _save,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(vertical: 13.h),
                    decoration: BoxDecoration(
                      color: _draft.canSubmit
                          ? AppColors.buttonNeon
                          : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 14.sp,
                            height: 14.sp,
                            child: const CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'groups_create_action'.tr().toUpperCase(),
                            style: GoogleFonts.inter(
                              color: _draft.canSubmit
                                  ? Colors.black
                                  : AppColors.textGray,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.maxLength,
    required this.onChanged,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: minLines,
        maxLines: maxLines,
        // Enforced here as well as by the CHECK constraint, so the field
        // refuses what the database would rather than failing on save.
        maxLength: maxLength,
        textCapitalization: TextCapitalization.sentences,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          counterText: '',
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 13.sp,
          ),
        ),
      ),
    );
  }
}
