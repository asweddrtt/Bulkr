import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/plan_limit_error.dart';
import '../core/plan_limits.dart';
import '../cubit/entitlement/entitlement_cubit.dart';
import '../cubit/meals/meals_cubit.dart';
import '../models/meal.dart';
import '../models/meal_slot.dart';
import '../styles/app_color.dart';
import '../widgets/bulkr_nav_bar.dart';
import '../widgets/bulkr_snack_bar.dart';
import '../widgets/animations/entrance.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/meal_actions_sheet.dart';
import '../widgets/meal_card.dart';
import '../widgets/premium_sheet.dart';
import '../widgets/slot_picker_sheet.dart';
import 'meal_editor_screen.dart';

/// The user's meal library.
///
/// Two views over one list: everything they own or saved, and the subset they
/// starred. Search filters whichever is showing, in memory — a curated library
/// is small, and matching locally means results land on the keystroke.
class MealsScreen extends StatelessWidget {
  const MealsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<MealsCubit, MealsState>(
      listenWhen: (previous, current) =>
          current.actionErrorKey != null &&
          previous.actionErrorKey != current.actionErrorKey,
      listener: (context, state) => _showError(context, state),
      child: Scaffold(
        // Transparent so the shell's background shows through: this screen
        // lives inside MainScreen's IndexedStack, and its own Scaffold exists
        // only to host the floating action button.
        backgroundColor: Colors.transparent,
        // Same lift as the feed's compose button — see BulkrNavBar.fabInset.
        floatingActionButton: Padding(
          padding: EdgeInsets.only(bottom: BulkrNavBar.fabInsetFor(context)),
          child: const _CreateMealButton(),
        ),
        body: Column(
          children: [
            const _MealsHeader(),
            Expanded(
              child: BlocBuilder<MealsCubit, MealsState>(
                builder: (context, state) => _buildBody(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MealsState state) {
    switch (state.status) {
      case MealsStatus.initial:
      case MealsStatus.loading:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryNeon),
        );

      case MealsStatus.failure:
        return _MealsMessage(
          icon: Icons.cloud_off_outlined,
          title: 'meals_load_failed'.tr(),
          body: state.errorMessage,
          actionLabel: 'retry'.tr(),
          onAction: () => context.read<MealsCubit>().load(),
        );

      case MealsStatus.ready:
        return _MealsSwipeView(state: state);
    }
  }

  static void _showError(BuildContext context, MealsState state) {
    BulkrSnackBar.show(
      context,
      state.actionErrorDetail ?? state.actionErrorKey!.tr(),
      tone: SnackTone.danger,
    );
    context.read<MealsCubit>().clearActionError();
  }
}

/// Title, search field and the two tabs. Always visible: the list scrolls under
/// it, so switching tabs never needs a scroll back to the top first.
class _MealsHeader extends StatelessWidget {
  const _MealsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'meals_title'.tr().toUpperCase(),
                  style: GoogleFonts.anton(
                    fontSize: 26.sp,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const _LibraryCount(),
            ],
          ),
          const _LibraryAllowance(),
          SizedBox(height: 14.h),
          const _MealsSearchField(),
          SizedBox(height: 12.h),
          const _MealsTabs(),
        ],
      ),
    );
  }
}

/// How big the library is, and — on a free account — how big it may get.
///
/// "12 total" is a fact about a library nobody is running out of. "4 / 5" is
/// the same fact for somebody who is, and it is the version that stops the
/// cap being a surprise at the moment they tap Create. Premium keeps the plain
/// count: a ceiling of infinity is not a number worth drawing.
class _LibraryCount extends StatelessWidget {
  const _LibraryCount();

  @override
  Widget build(BuildContext context) {
    final int? cap = context.watch<EntitlementCubit>().state.limits.savedMeals;

    return BlocBuilder<MealsCubit, MealsState>(
      buildWhen: (MealsState previous, MealsState current) =>
          previous.library.length != current.library.length,
      builder: (BuildContext context, MealsState state) {
        final int used = state.library.length;
        final bool full = cap != null && used >= cap;

        return Text(
          cap == null
              ? 'meals_count'.tr(namedArgs: <String, String>{'count': '$used'})
              : 'meals_count_capped'.tr(
                  namedArgs: <String, String>{'count': '$used', 'cap': '$cap'},
                ),
          style: GoogleFonts.inter(
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            // Red at the cap, because by then it is not a count any more — it
            // is the reason the next Create is going to stop.
            color: full ? const Color(0xFFFF6B6B) : AppColors.textGray,
            letterSpacing: 1,
          ),
        );
      },
    );
  }
}

/// The one line that says what free gets, on the screen the number applies to.
///
/// Free accounts kept hitting the meal cap at the moment they tried to exceed
/// it and not before, which makes a limit read as a fault: the app took four
/// meals without complaint and refused the fifth. So the allowance is stated
/// while there is still room in it, and it turns into the way out once there
/// is not.
///
/// Drawn for free accounts only, and never while a search is filtering the
/// list — a bar about the whole library under a list that is showing three of
/// it is answering a question nobody asked.
class _LibraryAllowance extends StatelessWidget {
  const _LibraryAllowance();

  @override
  Widget build(BuildContext context) {
    final int? cap = context.watch<EntitlementCubit>().state.limits.savedMeals;
    if (cap == null) return const SizedBox.shrink();

    return BlocBuilder<MealsCubit, MealsState>(
      buildWhen: (MealsState previous, MealsState current) =>
          previous.library.length != current.library.length ||
          previous.status != current.status ||
          previous.isSearching != current.isSearching,
      builder: (BuildContext context, MealsState state) {
        if (state.status != MealsStatus.ready || state.isSearching) {
          return const SizedBox.shrink();
        }

        final int used = state.library.length;
        final int left = PlanLimits.remaining(cap, used) ?? 0;
        final bool full = left == 0;

        return Padding(
          padding: EdgeInsets.only(top: 12.h),
          child: PressScale(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => PremiumSheet.show(
                context,
                limit: PlanLimit.savedMeals,
                source: 'meals_allowance',
              ),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.w,
                  vertical: 10.h,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF16190A),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: AppColors.primaryNeon.withValues(
                      alpha: full ? 0.45 : 0.20,
                    ),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.primaryNeon,
                      size: 16.sp,
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        full
                            ? 'meals_allowance_full'.tr(
                                namedArgs: <String, String>{'cap': '$cap'},
                              )
                            : 'meals_allowance_left'.tr(
                                namedArgs: <String, String>{
                                  'left': '$left',
                                  'cap': '$cap',
                                },
                              ),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11.sp,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'limit_upgrade'.tr().toUpperCase(),
                      style: GoogleFonts.inter(
                        color: AppColors.primaryNeon,
                        fontSize: 9.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MealsSearchField extends StatefulWidget {
  const _MealsSearchField();

  @override
  State<_MealsSearchField> createState() => _MealsSearchFieldState();
}

class _MealsSearchFieldState extends State<_MealsSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.search,
      onChanged: context.read<MealsCubit>().search,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
      decoration: InputDecoration(
        hintText: 'meals_search_hint'.tr(),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textGray,
          fontSize: 12.sp,
          letterSpacing: 1,
        ),
        prefixIcon: Icon(Icons.search, color: AppColors.textGray, size: 20.sp),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: Icon(Icons.close, size: 18.sp),
                  color: AppColors.textGray,
                  onPressed: () {
                    _controller.clear();
                    context.read<MealsCubit>().clearSearch();
                  },
                ),
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 12.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5.r),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5.r),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5.r),
          borderSide: const BorderSide(color: AppColors.primaryNeon),
        ),
      ),
    );
  }
}

class _MealsTabs extends StatelessWidget {
  const _MealsTabs();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealsCubit, MealsState>(
      buildWhen: (previous, current) =>
          previous.tab != current.tab ||
          previous.favoriteCount != current.favoriteCount,
      builder: (context, state) => Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'meals_tab_mine'.tr(),
              isSelected: state.tab == MealsTab.mine,
              onTap: () => context.read<MealsCubit>().selectTab(MealsTab.mine),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: _TabButton(
              label: 'meals_tab_favorites'.tr(),
              isSelected: state.tab == MealsTab.favorites,
              onTap: () =>
                  context.read<MealsCubit>().selectTab(MealsTab.favorites),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
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
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNeon : const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(5.r),
            border: Border.all(
              color: isSelected ? AppColors.primaryNeon : AppColors.darkBorder,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.anton(
              fontSize: 13.sp,
              color: isSelected ? Colors.black : Colors.white,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _MealsList extends StatelessWidget {
  const _MealsList({required this.state, required this.viewTab});

  final MealsState state;
  final MealsTab viewTab;


  @override
  Widget build(BuildContext context) {
    final List<Meal> meals = state.visibleMeals;

    if (meals.isEmpty) return _buildEmpty(context);

    return RefreshIndicator(
      onRefresh: () => context.read<MealsCubit>().refresh(),
      color: AppColors.primaryNeon,
      backgroundColor: const Color(0xFF1A1A1A),
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, BulkrNavBar.contentInset),
        itemCount: meals.length,
        itemBuilder: (context, index) {
          final Meal meal = meals[index];

          return MealCard(
            meal: meal,
            isLogging: state.busyMealId == meal.id,
            onLog: () => _toggleLog(context, meal),
            onToggleFavorite: () =>
                context.read<MealsCubit>().toggleFavorite(meal),
            onShowActions: () => _showActions(context, meal),
          );
        },
      ),
    );
  }

  Future<void> _toggleLog(BuildContext context, Meal meal) async {
    final MealsCubit cubit = context.read<MealsCubit>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool wasLogged = meal.isLoggedToday;

    // Turning it on asks which part of the day it was, so no entry is written
    // slotless — the tracker groups the day by slot, and an unslotted row
    // lands in the section kept for history from before slots existed.
    // Dismissing the chooser is a cancellation, not a default.
    MealSlot? slot;
    if (!wasLogged) {
      slot = await SlotPickerSheet.show(context);
      if (slot == null) return;
    }

    await cubit.toggleLoggedToday(meal, slot: slot);

    // Only claim it landed if it did — a failure has already put its own
    // message up through the listener.
    Meal? updated;
    for (final Meal candidate in cubit.state.library) {
      if (candidate.id == meal.id) {
        updated = candidate;
        break;
      }
    }
    if (updated == null || updated.isLoggedToday == wasLogged) return;

    final bool nowLogged = updated.isLoggedToday;

    BulkrSnackBar.showOn(
      messenger,
      (nowLogged ? 'meal_added_today' : 'meal_removed_today')
          .tr(namedArgs: {'meal': meal.title}),
      tone: nowLogged ? SnackTone.success : SnackTone.neutral,
      duration: const Duration(seconds: 2),
    );
  }

  /// Overflow menu, then — for a meal the user wrote — a confirmation, because
  /// deleting it also takes it out of the library of everyone who saved it.
  Future<void> _showActions(BuildContext context, Meal meal) async {
    final MealsCubit cubit = context.read<MealsCubit>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final MealAction? action = await MealActionsSheet.show(context, meal);
    if (action == null || !context.mounted) return;

    if (action == MealAction.edit) {
      await _openMealEditor(context, cubit, meal: meal);
      return;
    }

    if (action == MealAction.delete &&
        !await DeleteMealDialog.show(context, meal)) {
      return;
    }

    await cubit.removeMeal(meal);

    // The card is already gone by the time this runs; say which meal left, so
    // an accidental tap is obvious rather than just a list that got shorter.
    if (cubit.state.actionErrorKey != null) return;

    BulkrSnackBar.showOn(
      messenger,
      (action == MealAction.delete ? 'meal_deleted' : 'meal_removed')
          .tr(namedArgs: {'meal': meal.title}),
      duration: const Duration(seconds: 2),
    );
  }

  /// Three different empties, because they call for three different things:
  /// nothing saved yet, nothing starred yet, and nothing matching a search.
  Widget _buildEmpty(BuildContext context) {
    if (state.isSearching) {
      return _MealsMessage(
        icon: Icons.search_off_rounded,
        title: 'meals_no_results'.tr(),
        body: 'meals_no_results_body'.tr(namedArgs: {'query': state.query.trim()}),
      );
    }

    if (state.tab == MealsTab.favorites) {
      return _MealsMessage(
        icon: Icons.star_border_rounded,
        title: 'meals_empty_favorites'.tr(),
        body: 'meals_empty_favorites_body'.tr(),
      );
    }

    return _MealsMessage(
      icon: Icons.restaurant_menu_rounded,
      title: 'meals_empty_mine'.tr(),
      body: 'meals_empty_mine_body'.tr(),
    );
  }
}

class _MealsMessage extends StatelessWidget {
  const _MealsMessage({
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
        padding: EdgeInsets.fromLTRB(40.w, 0, 40.w, 80.h),
        child: Entrance(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40.sp, color: AppColors.darkBorder),
              SizedBox(height: 16.h),
              Text(
                title.toUpperCase(),
                textAlign: TextAlign.center,
                style: GoogleFonts.anton(
                  fontSize: 16.sp,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              if (body != null) ...[
                SizedBox(height: 8.h),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    color: AppColors.textGray,
                    height: 1.5,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: 20.h),
                PressScale(
                  child: GestureDetector(
                    onTap: onAction,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24.w,
                        vertical: 12.h,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.buttonNeon,
                        borderRadius: BorderRadius.circular(4.r),
                      ),
                      child: Text(
                        actionLabel!.toUpperCase(),
                        style: GoogleFonts.anton(
                          fontSize: 13.sp,
                          color: Colors.black,
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
      ),
    );
  }
}

/// Opens the editor and folds whatever comes back into the library.
///
/// Shared by the create button and the edit action, because what happens
/// afterwards is the same either way: a meal came back, show it now and
/// reconcile against the server behind it.
Future<void> _openMealEditor(
  BuildContext context,
  MealsCubit cubit, {
  Meal? meal,
}) async {
  final Meal? saved = await Navigator.of(context).push<Meal>(
    MaterialPageRoute(builder: (_) => MealEditorScreen(meal: meal)),
  );

  if (saved == null) return;

  // Shown immediately from what was just written, then reconciled against the
  // server — so the meal is on screen before the refetch returns.
  cubit.adopt(saved);
  await cubit.refresh();
}

/// Opens the create-meal form and folds whatever comes back into the library.
class _CreateMealButton extends StatelessWidget {
  const _CreateMealButton();

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _openEditor(context),
      backgroundColor: AppColors.buttonNeon,
      foregroundColor: Colors.black,
      icon: const Icon(Icons.add_rounded),
      label: Text(
        'meals_create_btn'.tr().toUpperCase(),
        style: GoogleFonts.anton(
          fontSize: 13.sp,
          color: Colors.black,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  /// Opens the editor, unless the library is already full.
  ///
  /// Stopped here rather than at the save, even though the database stops it
  /// there too. Letting somebody build a meal — name it, add six ingredients,
  /// weigh each one — and refusing it at the last tap is the most expensive
  /// possible place to enforce a cap: the work is done and it is thrown away.
  /// The trigger in `supabase/premium_limits.sql` stays as the real ceiling,
  /// because this check is on somebody else's phone; this one exists so that
  /// nobody reaches it.
  ///
  /// Editing an existing meal is deliberately not gated — see the trigger,
  /// which is on insert only. Somebody who filled a library on premium and
  /// lapsed can still fix a typo.
  Future<void> _openEditor(BuildContext context) async {
    final EntitlementState entitlement = context.read<EntitlementCubit>().state;
    final int used = context.read<MealsCubit>().state.library.length;

    if (!entitlement.limits.canSaveAnotherMeal(used)) {
      await PremiumSheet.show(
        context,
        limit: PlanLimit.savedMeals,
        source: 'meals_create',
      );
      return;
    }

    if (!context.mounted) return;
    await _openMealEditor(context, context.read<MealsCubit>());
  }
}
class _MealsSwipeView extends StatefulWidget {
  final MealsState state;
  const _MealsSwipeView({required this.state});

  @override
  State<_MealsSwipeView> createState() => _MealsSwipeViewState();
}

class _MealsSwipeViewState extends State<_MealsSwipeView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    // Start on the correct page based on current tab
    _pageController = PageController(
      initialPage: widget.state.tab == MealsTab.mine ? 0 : 1,
    );
  }

  @override
  void didUpdateWidget(covariant _MealsSwipeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the user taps a tab button, animate the PageView to match
    final targetPage = widget.state.tab == MealsTab.mine ? 0 : 1;
    if (_pageController.hasClients && _pageController.page?.round() != targetPage) {
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _pageController,
      onPageChanged: (index) {
        // If the user swipes, update the Cubit to switch the active tab
        final targetTab = index == 0 ? MealsTab.mine : MealsTab.favorites;
        if (widget.state.tab != targetTab) {
          context.read<MealsCubit>().selectTab(targetTab);
        }
      },
      children: [
        // Page 0: Mine
        _MealsList(state: widget.state, viewTab: MealsTab.mine),
        // Page 1: Favorites
        _MealsList(state: widget.state, viewTab: MealsTab.favorites),
      ],
    );
  }
}