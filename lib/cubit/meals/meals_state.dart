part of 'meals_cubit.dart';

enum MealsStatus { initial, loading, ready, failure }

/// The two tabs on the Meals screen.
///
/// `mine` is the whole library — created and saved alike — because from the
/// user's side both are "my meals". `favorites` is the subset they marked.
enum MealsTab { mine, favorites }

class MealsState extends Equatable {
  const MealsState({
    this.status = MealsStatus.initial,
    this.library = const [],
    this.tab = MealsTab.mine,
    this.query = '',
    this.busyMealId,
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  final MealsStatus status;

  /// Every meal the user owns or saved, newest acquisition first.
  final List<Meal> library;

  final MealsTab tab;

  /// What the search field holds. Filtering is local: a hand-curated library is
  /// small, and matching in memory means results land on the keystroke instead
  /// of a round trip later.
  final String query;

  /// Meal currently mid-write, so its own card can show a spinner while the
  /// rest of the list stays interactive.
  ///
  /// Whether a meal is logged today is not held here: it lives on the [Meal]
  /// itself, read from `daily_logs`, so it survives a tab switch and a restart
  /// rather than lasting as long as this screen happens to.
  final String? busyMealId;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  /// The meals the current tab and search term leave visible.
  List<Meal> get visibleMeals {
    final Iterable<Meal> inTab = switch (tab) {
      MealsTab.mine => library,
      MealsTab.favorites => library.where((meal) => meal.isFavorite),
    };

    return inTab.where((meal) => meal.matches(query)).toList();
  }

  bool get isSearching => query.trim().isNotEmpty;

  int get favoriteCount => library.where((meal) => meal.isFavorite).length;

  /// True when the tab is genuinely empty, as opposed to filtered empty — the
  /// two want different things said about them.
  bool get isTabEmpty => switch (tab) {
        MealsTab.mine => library.isEmpty,
        MealsTab.favorites => favoriteCount == 0,
      };

  MealsState copyWith({
    MealsStatus? status,
    List<Meal>? library,
    MealsTab? tab,
    String? query,
    String? busyMealId,
    bool clearBusy = false,
    String? errorMessage,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearActionError = false,
  }) {
    return MealsState(
      status: status ?? this.status,
      library: library ?? this.library,
      tab: tab ?? this.tab,
      query: query ?? this.query,
      busyMealId: clearBusy ? null : (busyMealId ?? this.busyMealId),
      errorMessage: errorMessage ?? this.errorMessage,
      actionErrorKey: clearActionError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail:
          clearActionError ? null : (actionErrorDetail ?? this.actionErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        status,
        library,
        tab,
        query,
        busyMealId,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
      ];
}
