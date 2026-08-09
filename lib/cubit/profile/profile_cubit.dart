import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/user_repository.dart';
import '../../models/user_profile.dart';
import '../../models/weight_entry.dart';

part 'profile_state.dart';

/// Loads the signed-in user's row and weigh-in history for the post-onboarding
/// screens.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({required UserRepository userRepository})
      : _userRepository = userRepository,
        super(const ProfileState());

  final UserRepository _userRepository;

  /// Fetches profile and weight history together.
  ///
  /// [silent] keeps the current data on screen while refetching, so a
  /// pull-to-refresh doesn't blank the page out and reflow everything.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: ProfileStatus.loading, clearError: true));
    }

    try {
      final profile = await _userRepository.fetchProfile();

      if (profile == null) {
        emit(state.copyWith(status: ProfileStatus.missing, clearError: true));
        return;
      }

      // The chart is secondary: a failure to read weight_logs — most likely a
      // missing GRANT on that table — shouldn't take the whole profile down
      // with it.
      List<WeightEntry> history;
      try {
        history = await _userRepository.fetchWeightHistory();
      } catch (_) {
        history = state.weightHistory;
      }

      if (isClosed) return;
      emit(state.copyWith(
        status: ProfileStatus.ready,
        profile: profile,
        weightHistory: history,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(
        status: ProfileStatus.failure,
        errorMessage: error.toString(),
      ));
    }
  }

  Future<void> refresh() => load(silent: true);
}
