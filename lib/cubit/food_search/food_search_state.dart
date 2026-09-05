part of 'food_search_cubit.dart';

enum FoodSearchStatus {
  /// Nothing asked for yet, or too few characters to ask with.
  idle,
  searching,
  results,

  /// Asked, answered, nothing found. Also what a failed search reports: from
  /// the user's side "the search broke" and "no such food" both mean there is
  /// nothing to tap, and the detail is in the log rather than on top of the
  /// keyboard.
  empty,
}

class FoodSearchState extends Equatable {
  const FoodSearchState({
    this.query = '',
    this.status = FoodSearchStatus.idle,
    this.results = const [],
  });

  /// What is in the field. Kept in state because it is what the stale-response
  /// guard compares against, not because anything renders it — the text field
  /// owns its own controller.
  final String query;

  final FoodSearchStatus status;
  final List<FoodItem> results;

  /// Where to return after a one-off request finishes — showing the results
  /// again if there are any, and the prompt if there are not.
  ///
  /// A barcode lookup interrupts whatever the list was showing, and going
  /// straight back to [FoodSearchStatus.idle] would blank a perfectly good set
  /// of results behind it.
  FoodSearchStatus get restingStatus =>
      results.isEmpty ? FoodSearchStatus.idle : FoodSearchStatus.results;

  FoodSearchState copyWith({
    String? query,
    FoodSearchStatus? status,
    List<FoodItem>? results,
  }) {
    return FoodSearchState(
      query: query ?? this.query,
      status: status ?? this.status,
      results: results ?? this.results,
    );
  }

  @override
  List<Object?> get props => [query, status, results];
}
