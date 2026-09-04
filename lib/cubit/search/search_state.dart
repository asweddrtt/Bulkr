part of 'search_cubit.dart';

enum SearchStatus { initial, loading, ready, failure }

class SearchState extends Equatable {
  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.isSearching = false,
    this.people = const [],
    this.groups = const [],
    this.suggestedPeople = const [],
    this.myGroups = const [],
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  final SearchStatus status;
  final String query;

  /// A search is in flight, or still debouncing. Both, on purpose — from the
  /// user's side "I typed and nothing has come back" is one state.
  final bool isSearching;

  /// Matches for [query].
  final List<Person> people;
  final List<Group> groups;

  /// What to show before anything is typed: accounts worth following, and the
  /// groups the user is already in.
  final List<Person> suggestedPeople;
  final List<Group> myGroups;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  bool get hasQuery => query.trim().isNotEmpty;

  /// The people to render: matches while searching, suggestions otherwise.
  List<Person> get visiblePeople => hasQuery ? people : suggestedPeople;

  /// The groups to render, on the same rule.
  List<Group> get visibleGroups => hasQuery ? groups : myGroups;

  bool get hasPeople => visiblePeople.isNotEmpty;
  bool get hasGroups => visibleGroups.isNotEmpty;

  /// A search that came back with nothing on both sides.
  ///
  /// Both, not either: a term that matches three groups and no people is a
  /// successful search, and saying "nothing found" over a list of groups would
  /// be contradicting what is on screen.
  bool get isNoResults =>
      hasQuery && !isSearching && people.isEmpty && groups.isEmpty;

  /// Nothing to suggest and no groups joined, which on a new install is the
  /// normal case rather than a failure.
  bool get isEmptyStart =>
      !hasQuery &&
      status == SearchStatus.ready &&
      suggestedPeople.isEmpty &&
      myGroups.isEmpty;

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    bool? isSearching,
    List<Person>? people,
    List<Group>? groups,
    List<Person>? suggestedPeople,
    List<Group>? myGroups,
    String? errorMessage,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearError = false,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      people: people ?? this.people,
      groups: groups ?? this.groups,
      suggestedPeople: suggestedPeople ?? this.suggestedPeople,
      myGroups: myGroups ?? this.myGroups,
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
        query,
        isSearching,
        people,
        groups,
        suggestedPeople,
        myGroups,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
      ];
}
