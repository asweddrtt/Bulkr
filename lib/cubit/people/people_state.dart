part of 'people_cubit.dart';

enum PeopleStatus { initial, loading, ready, failure }

class PeopleState extends Equatable {
  const PeopleState({
    this.status = PeopleStatus.initial,
    this.suggested = const [],
    this.results = const [],
    this.query = '',
    this.isSearching = false,
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  final PeopleStatus status;

  /// Accounts worth following: trainers first, then whoever is active.
  ///
  /// Filtered to people the user does not already follow at load time, and
  /// deliberately not re-filtered as they follow them — a row that vanishes
  /// under the thumb that tapped it takes away the only way to undo a mis-tap.
  final List<Person> suggested;

  /// Matches for [query]. Unlike [suggested], these include people the user
  /// already follows: someone searching a handle is looking for that person,
  /// not for strangers.
  final List<Person> results;

  final String query;

  /// A search is in flight, or debouncing. Both, on purpose — from the user's
  /// side "I typed and nothing has come back yet" is one state.
  final bool isSearching;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  bool get hasQuery => query.trim().isNotEmpty;

  /// What the list should show.
  List<Person> get visiblePeople => hasQuery ? results : suggested;

  /// A search that came back with nothing, as opposed to one still running.
  bool get isNoResults => hasQuery && !isSearching && results.isEmpty;

  /// Nobody to suggest, and not because it is still loading.
  ///
  /// The honest reason is almost always that the app has one account in it, so
  /// the empty state says so rather than implying something failed.
  bool get hasNoSuggestions =>
      !hasQuery && status == PeopleStatus.ready && suggested.isEmpty;

  PeopleState copyWith({
    PeopleStatus? status,
    List<Person>? suggested,
    List<Person>? results,
    String? query,
    bool? isSearching,
    String? errorMessage,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearError = false,
  }) {
    return PeopleState(
      status: status ?? this.status,
      suggested: suggested ?? this.suggested,
      results: results ?? this.results,
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorKey:
          clearError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail:
          clearError ? null : (actionErrorDetail ?? this.actionErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        status,
        suggested,
        results,
        query,
        isSearching,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
      ];
}
