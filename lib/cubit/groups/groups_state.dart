part of 'groups_cubit.dart';

enum GroupsStatus { initial, loading, ready, failure }

/// The two lists.
///
/// `mine` is the groups you are in; `discover` is public groups you are not.
/// Search cuts across both — someone looking for a group by name does not care
/// which list it is in.
enum GroupsTab { mine, discover }

class GroupsState extends Equatable {
  const GroupsState({
    this.status = GroupsStatus.initial,
    this.tab = GroupsTab.mine,
    this.mine = const [],
    this.discoverable = const [],
    this.results = const [],
    this.query = '',
    this.isSearching = false,
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  final GroupsStatus status;
  final GroupsTab tab;

  /// Groups this user is in, most recently joined first.
  final List<Group> mine;

  /// Public groups, newest first.
  ///
  /// Includes ones the user is already in. Filtering them out would make the
  /// list shuffle as they join things, and a group they are in appearing in
  /// "discover" with a "joined" button is information rather than noise.
  final List<Group> discoverable;

  final List<Group> results;
  final String query;
  final bool isSearching;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  bool get hasQuery => query.trim().isNotEmpty;

  /// What the list should show: search results when searching, otherwise
  /// whichever tab is up.
  List<Group> get visibleGroups {
    if (hasQuery) return results;

    return switch (tab) {
      GroupsTab.mine => mine,
      GroupsTab.discover => discoverable,
    };
  }

  bool get isNoResults => hasQuery && !isSearching && results.isEmpty;

  /// The visible tab is genuinely empty, as opposed to filtered empty — the
  /// two want different things said about them.
  bool get isTabEmpty =>
      !hasQuery && status == GroupsStatus.ready && visibleGroups.isEmpty;

  GroupsState copyWith({
    GroupsStatus? status,
    GroupsTab? tab,
    List<Group>? mine,
    List<Group>? discoverable,
    List<Group>? results,
    String? query,
    bool? isSearching,
    String? errorMessage,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearError = false,
  }) {
    return GroupsState(
      status: status ?? this.status,
      tab: tab ?? this.tab,
      mine: mine ?? this.mine,
      discoverable: discoverable ?? this.discoverable,
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
        tab,
        mine,
        discoverable,
        results,
        query,
        isSearching,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
      ];
}
