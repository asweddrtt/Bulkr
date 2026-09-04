import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/follow_repository.dart';
import '../../models/person.dart';

part 'people_state.dart';

/// Drives finding people to follow.
///
/// Two modes over one list: suggestions when the search field is empty, results
/// when it is not. Kept as one cubit rather than two, because they are the same
/// screen and the follow buttons behave identically in both.
class PeopleCubit extends Cubit<PeopleState> {
  PeopleCubit({required FollowRepository followRepository})
      : _follows = followRepository,
        super(const PeopleState());

  final FollowRepository _follows;

  static const String _actionFailedKey = 'people_action_failed';

  /// How long to wait after the last keystroke before searching.
  ///
  /// The same reasoning as the food search: a query per character is a query
  /// per character, and nobody finishes typing a handle in under a third of a
  /// second.
  static const Duration _debounce = Duration(milliseconds: 350);

  Timer? _searchTimer;

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    return super.close();
  }

  /// Loads the suggestions.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: PeopleStatus.loading, clearError: true));
    }

    try {
      final List<Person> suggested = await _follows.fetchSuggested();
      if (isClosed) return;

      emit(state.copyWith(
        status: PeopleStatus.ready,
        suggested: suggested,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: suggested people failed to load — $detail');

      if (silent && state.status == PeopleStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(state.copyWith(
        status: PeopleStatus.failure,
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
      // Cleared immediately rather than when the new results land, so the
      // screen never shows results for a term that is no longer in the field.
      results: const [],
      isSearching: trimmed.isNotEmpty,
    ));

    if (trimmed.isEmpty) return;

    _searchTimer = Timer(_debounce, () => _runSearch(trimmed));
  }

  void clearSearch() => search('');

  Future<void> _runSearch(String term) async {
    try {
      final List<Person> results = await _follows.searchPeople(term);
      if (isClosed) return;

      // Dropped if the field moved on while this was in flight. Without the
      // check, a slow request for "al" can land after a fast one for "alice"
      // and replace the right answer with a stale one.
      if (state.query.trim() != term) return;

      emit(state.copyWith(results: results, isSearching: false));
    } catch (error) {
      if (isClosed) return;
      if (state.query.trim() != term) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: people search failed — $detail');

      emit(state.copyWith(
        isSearching: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Follows someone, or stops.
  ///
  /// Optimistic, and the person stays in the list rather than disappearing the
  /// moment they are followed. Suggestions filter out people you already
  /// follow when they load, but removing a row under the thumb that just
  /// tapped it makes the next row jump up into the tap — and takes away the
  /// only way to undo a mis-tap.
  Future<void> toggleFollow(Person person) async {
    if (!person.isFollowable) return;

    final bool next = !person.isFollowedByMe;

    _replace(person.copyWith(
      isFollowedByMe: next,
      followerCount: (person.followerCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _follows.setFollowing(personId: person.id, isFollowing: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: follow failed — $detail');

      _replace(person);
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
  /// The same account can be in the suggestions and in the search results at
  /// once, and both copies have to move together or clearing the search shows
  /// a button that disagrees with the one just tapped.
  void _replace(Person person) {
    emit(state.copyWith(
      suggested: _replaced(state.suggested, person),
      results: _replaced(state.results, person),
    ));
  }

  static List<Person> _replaced(List<Person> people, Person updated) {
    if (!people.any((person) => person.id == updated.id)) return people;

    return people
        .map((person) => person.id == updated.id ? updated : person)
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
