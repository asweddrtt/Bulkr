import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/group_repository.dart';
import '../../models/group.dart';

part 'groups_state.dart';

/// Drives the list of groups: the ones you're in, the ones you could join, and
/// starting a new one.
class GroupsCubit extends Cubit<GroupsState> {
  GroupsCubit({required GroupRepository groupRepository})
      : _groups = groupRepository,
        super(const GroupsState());

  final GroupRepository _groups;

  static const String _actionFailedKey = 'groups_action_failed';

  /// Same debounce as the people search, for the same reason: a query per
  /// character is a query per character.
  static const Duration _debounce = Duration(milliseconds: 350);

  Timer? _searchTimer;

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    return super.close();
  }

  /// Loads both lists at once.
  ///
  /// Together rather than on tab switch: there are two short lists, the screen
  /// opens on one and the other is a tap away, and fetching on switch would
  /// make that tap feel slow for no saving worth having.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: GroupsStatus.loading, clearError: true));
    }

    try {
      final results = await Future.wait([
        _groups.fetchMyGroups(),
        _groups.fetchDiscoverable(),
      ]);

      if (isClosed) return;

      emit(state.copyWith(
        status: GroupsStatus.ready,
        mine: results[0],
        discoverable: results[1],
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: groups failed to load — $detail');

      if (silent && state.status == GroupsStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(state.copyWith(
        status: GroupsStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  void selectTab(GroupsTab tab) {
    if (state.tab == tab) return;
    emit(state.copyWith(tab: tab));
  }

  /// Records what has been typed and schedules the search.
  void search(String query) {
    if (state.query == query) return;

    _searchTimer?.cancel();

    final String trimmed = query.trim();

    emit(state.copyWith(
      query: query,
      results: const [],
      isSearching: trimmed.isNotEmpty,
    ));

    if (trimmed.isEmpty) return;

    _searchTimer = Timer(_debounce, () => _runSearch(trimmed));
  }

  void clearSearch() => search('');

  Future<void> _runSearch(String term) async {
    try {
      final List<Group> results = await _groups.searchGroups(term);
      if (isClosed) return;

      // Dropped if the field moved on while this was in flight.
      if (state.query.trim() != term) return;

      emit(state.copyWith(results: results, isSearching: false));
    } catch (error) {
      if (isClosed) return;
      if (state.query.trim() != term) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: group search failed — $detail');

      emit(state.copyWith(
        isSearching: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Joins a group, or leaves it.
  ///
  /// Optimistic, member count included. Joining moves the group into "my
  /// groups" on the next load rather than immediately: a row that jumps
  /// between two tabs under the thumb that tapped it is disorienting, and the
  /// button already says what happened.
  Future<void> toggleMembership(Group group) async {
    if (group.isOwner) return;

    final bool next = !group.isMember;

    _replace(group.copyWith(
      isMember: next,
      memberCount: (group.memberCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _groups.setMembership(groupId: group.id, isMember: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: group membership failed — $detail');

      _replace(group);
      emit(state.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Puts a just-created group at the top of "my groups" and shows that tab.
  void groupCreated(Group group) {
    emit(state.copyWith(
      tab: GroupsTab.mine,
      mine: [group, ...state.mine],
      // A new public group belongs in the discoverable list too, but its
      // position there is by creation date — which is the top — so prepending
      // is honest rather than a white lie.
      discoverable:
          group.isPrivate ? state.discoverable : [group, ...state.discoverable],
    ));
  }

  /// Deletes a group the user owns, taking it off both lists first.
  Future<void> deleteGroup(Group group) async {
    if (!group.isOwner) return;

    final GroupsState before = state;

    emit(state.copyWith(
      mine: state.mine.where((g) => g.id != group.id).toList(),
      discoverable: state.discoverable.where((g) => g.id != group.id).toList(),
      results: state.results.where((g) => g.id != group.id).toList(),
      clearError: true,
    ));

    try {
      await _groups.deleteGroup(group.id);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: group delete failed — $detail');

      emit(before.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  void clearNotice() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearError: true));
  }

  /// Puts an updated group into all three lists.
  ///
  /// The same group can be in "mine", in "discoverable" and in the search
  /// results at once, and all copies have to move together or the button
  /// disagrees with itself depending on which list you tapped it from.
  void _replace(Group group) {
    emit(state.copyWith(
      mine: _replaced(state.mine, group),
      discoverable: _replaced(state.discoverable, group),
      results: _replaced(state.results, group),
    ));
  }

  static List<Group> _replaced(List<Group> groups, Group updated) {
    if (!groups.any((group) => group.id == updated.id)) return groups;

    return groups
        .map((group) => group.id == updated.id ? updated : group)
        .toList(growable: false);
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.message, if (error.code != null) '(${error.code})']
          .join(' ');
    }
    if (error is StorageException) return error.message;
    return '$error';
  }
}
