import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/app_preferences.dart';
import '../../data/follow_repository.dart';
import '../../data/group_repository.dart';
import '../../models/group.dart';
import '../../models/person.dart';

part 'search_state.dart';

/// Drives one search field over both people and groups.
///
/// One cubit and one query rather than a screen per kind, because "find the
/// thing I am thinking of" is a single intention. Someone who remembers the
/// word "shoulders" does not know or care whether it belongs to an account or
/// to a group, and making them pick a tab first is making them answer a
/// question about the app's schema.
///
/// Empty query is not an empty screen: it shows people worth following and the
/// groups the user is already in, which is what the two screens this replaces
/// were for.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit({
    required FollowRepository followRepository,
    required GroupRepository groupRepository,
    AppPreferences? preferences,
  })  : _follows = followRepository,
        _groups = groupRepository,
        _preferences = preferences ?? AppPreferences(),
        super(const SearchState());

  final FollowRepository _follows;
  final GroupRepository _groups;
  final AppPreferences _preferences;

  static const String _actionFailedKey = 'search_action_failed';

  /// Same debounce as the food search, for the same reason: a query per
  /// character is a query per character, and now it is two.
  static const Duration _debounce = Duration(milliseconds: 350);

  Timer? _searchTimer;

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    return super.close();
  }

  /// Loads what to show before anything is typed.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: SearchStatus.loading, clearError: true));
    }

    try {
      final results = await Future.wait([
        _follows.fetchSuggested(),
        _groups.fetchMyGroups(),
      ]);

      // Local, so it cannot fail the load and does not need its own error
      // channel — the worst case is an empty list of recent searches.
      final List<String> history = await _preferences.searchHistory();

      if (isClosed) return;

      emit(state.copyWith(
        status: SearchStatus.ready,
        suggestedPeople: results[0] as List<Person>,
        myGroups: results[1] as List<Group>,
        history: history,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: search suggestions failed — $detail');

      if (silent && state.status == SearchStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(state.copyWith(
        status: SearchStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Records what has been typed and schedules the search.
  void search(String query) {
    if (state.query == query) return;

    _searchTimer?.cancel();

    final String trimmed = query.trim();

    emit(state.copyWith(
      query: query,
      // Cleared now rather than when the new results land, so the screen never
      // shows matches for a term no longer in the field.
      people: const [],
      groups: const [],
      isSearching: trimmed.isNotEmpty,
    ));

    if (trimmed.isEmpty) return;

    _searchTimer = Timer(_debounce, () => _runSearch(trimmed));
  }

  void clearSearch() => search('');

  // --- History ------------------------------------------------------------

  /// Records a term the user actually meant.
  ///
  /// Called when a result is opened, not on every keystroke and not when the
  /// debounce fires: "sar" is a stage on the way to "sara", and a history full
  /// of prefixes is a history nobody wants to look at. Acting on a result is
  /// the signal that the term was the right one.
  Future<void> rememberSearch(String term) async {
    final List<String> history = await _preferences.rememberSearch(term);
    if (isClosed) return;
    emit(state.copyWith(history: history));
  }

  /// Re-runs a term from the history, immediately rather than debounced —
  /// it was tapped, not typed, so there is nothing to wait for.
  void repeatSearch(String term) {
    _searchTimer?.cancel();

    emit(state.copyWith(
      query: term,
      people: const [],
      groups: const [],
      isSearching: true,
    ));

    _runSearch(term.trim());
  }

  Future<void> forgetSearch(String term) async {
    final List<String> history = await _preferences.forgetSearch(term);
    if (isClosed) return;
    emit(state.copyWith(history: history));
  }

  Future<void> clearHistory() async {
    await _preferences.clearSearchHistory();
    if (isClosed) return;
    emit(state.copyWith(history: const []));
  }

  /// Runs both searches together.
  ///
  /// `Future.wait`, so one round trip's latency rather than two — and if
  /// either side fails the whole search reports it, because half a result set
  /// silently presented as the whole thing is worse than an error.
  Future<void> _runSearch(String term) async {
    try {
      final results = await Future.wait([
        _follows.searchPeople(term),
        _groups.searchGroups(term),
      ]);

      if (isClosed) return;

      // Dropped if the field moved on while this was in flight. Without the
      // check, a slow request for "sh" can land after a fast one for
      // "shoulders" and replace the right answer with a stale one.
      if (state.query.trim() != term) return;

      emit(state.copyWith(
        people: results[0] as List<Person>,
        groups: results[1] as List<Group>,
        isSearching: false,
      ));
    } catch (error) {
      if (isClosed) return;
      if (state.query.trim() != term) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: search failed — $detail');

      emit(state.copyWith(
        isSearching: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Follows someone, or stops.
  ///
  /// Optimistic. The row stays where it is rather than disappearing once
  /// followed: suggestions filter out existing follows when they load, but
  /// removing a row under the thumb that tapped it takes away the only way to
  /// undo a mis-tap.
  Future<void> toggleFollow(Person person) async {
    if (!person.isFollowable) return;

    final bool next = !person.isFollowedByMe;

    _replacePerson(person.copyWith(
      isFollowedByMe: next,
      followerCount: (person.followerCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _follows.setFollowing(personId: person.id, isFollowing: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: follow failed — $detail');

      _replacePerson(person);
      emit(state.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Joins a group, or leaves it.
  Future<void> toggleMembership(Group group) async {
    if (group.isOwner) return;

    final bool next = !group.isMember;

    _replaceGroup(group.copyWith(
      isMember: next,
      memberCount: (group.memberCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _groups.setMembership(groupId: group.id, isMember: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: group membership failed — $detail');

      _replaceGroup(group);
      emit(state.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  void clearNotice() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearError: true));
  }

  /// Puts an updated person into both lists.
  ///
  /// The same account can be in the suggestions and in the results at once,
  /// and both copies have to move together or clearing the search shows a
  /// button that disagrees with the one just tapped.
  void _replacePerson(Person person) {
    emit(state.copyWith(
      suggestedPeople: _replaced(state.suggestedPeople, person, (p) => p.id),
      people: _replaced(state.people, person, (p) => p.id),
    ));
  }

  void _replaceGroup(Group group) {
    emit(state.copyWith(
      myGroups: _replaced(state.myGroups, group, (g) => g.id),
      groups: _replaced(state.groups, group, (g) => g.id),
    ));
  }

  static List<T> _replaced<T>(
    List<T> items,
    T updated,
    String Function(T) idOf,
  ) {
    final String id = idOf(updated);
    if (!items.any((item) => idOf(item) == id)) return items;

    return items
        .map((item) => idOf(item) == id ? updated : item)
        .toList(growable: false);
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.message, if (error.code != null) '(${error.code})']
          .join(' ');
    }
    return '$error';
  }
}
