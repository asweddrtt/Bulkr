import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/calorie_engine.dart';
import '../../data/user_repository.dart';
import '../../data/username_generator.dart';
import '../../models/activity_level.dart';
import '../../models/gender.dart';
import '../../models/nutrition_plan.dart';
import '../../models/unit_system.dart';

part 'onboarding_state.dart';

/// Accumulates the answers from screens 2-4 and, on the final tap, runs the
/// maths and performs the single insert.
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit({
    required UserRepository userRepository,
    UsernameGenerator? usernameGenerator,
  })  : _userRepository = userRepository,
        _usernames = usernameGenerator ?? UsernameGenerator(),
        super(const OnboardingState());

  final UserRepository _userRepository;
  final UsernameGenerator _usernames;

  /// Keeps the availability lookup off every keystroke.
  Timer? _usernameDebounce;

  static const Duration _usernameDebounceDelay = Duration(milliseconds: 450);

  /// Called once screen 1 has a session. Seeds the identity fields and
  /// proposes a handle, which the user can overwrite on screen 2.
  void adoptIdentity(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName = _firstNonEmpty(metadata, const [
      'full_name',
      'name',
      'preferred_username',
    ]);
    final avatarUrl = _firstNonEmpty(metadata, const ['avatar_url', 'picture']);

    // Don't clobber a handle the user already typed if they navigate back to
    // screen 1 and sign in again.
    final username = state.usernameWasEdited
        ? state.username
        : _usernames.suggest(displayName: displayName, email: user.email);

    emit(state.copyWith(
      userId: user.id,
      displayName: displayName,
      avatarUrl: avatarUrl,
      username: username,
    ));
  }

  static String? _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  // --- Screen 2 -----------------------------------------------------------

  void setUsername(String value) {
    final normalised = value.trim().toLowerCase();
    emit(state.copyWith(
      username: normalised,
      usernameWasEdited: true,
      usernameAvailability: UsernameAvailability.unknown,
      clearError: true,
    ));

    _usernameDebounce?.cancel();
    if (!UsernameGenerator.isValid(normalised)) return;

    _usernameDebounce = Timer(
      _usernameDebounceDelay,
      () => _checkUsername(normalised),
    );
  }

  /// Best-effort hint only. If RLS hides other users' rows this always reports
  /// available, which is why the insert path also handles a collision.
  Future<void> _checkUsername(String username) async {
    if (isClosed) return;
    emit(state.copyWith(usernameAvailability: UsernameAvailability.checking));

    final isFree = await _userRepository.isUsernameAvailable(username);

    // The user may have kept typing while the request was in flight.
    if (isClosed || state.username != username) return;

    emit(state.copyWith(
      usernameAvailability: isFree
          ? UsernameAvailability.available
          : UsernameAvailability.taken,
    ));
  }

  void setUnitSystem(UnitSystem value) =>
      emit(state.copyWith(unitSystem: value));

  void setGender(Gender value) => emit(state.copyWith(gender: value));

  void setDateOfBirth(DateTime value) =>
      emit(state.copyWith(dateOfBirth: value));

  void setHeightCm(double value) => emit(state.copyWith(heightCm: value));

  void setCurrentWeightKg(double value) =>
      emit(state.copyWith(currentWeightKg: value));

  // --- Screen 3 -----------------------------------------------------------

  void setActivityLevel(ActivityLevel value) =>
      emit(state.copyWith(activityLevel: value));

  // --- Screen 4 -----------------------------------------------------------

  void setTargetWeightKg(double value) =>
      emit(state.copyWith(targetWeightKg: value));

  void setWeeklyGainKg(double value) =>
      emit(state.copyWith(weeklyGainKg: value));

  // --- Screen 5 -----------------------------------------------------------

  /// Compiles everything into one insert and flags onboarding complete.
  ///
  /// Returns true when the row landed, so the screen knows whether to navigate.
  Future<bool> submit() async {
    final userId = state.userId;
    final plan = state.nutritionPlan;
    final gender = state.gender;
    final dateOfBirth = state.dateOfBirth;

    if (userId == null ||
        plan == null ||
        gender == null ||
        dateOfBirth == null) {
      emit(state.copyWith(
        submission: SubmissionStatus.failure,
        errorMessage: 'onboarding_error_incomplete',
      ));
      return false;
    }

    emit(state.copyWith(
      submission: SubmissionStatus.submitting,
      clearError: true,
    ));

    try {
      final storedUsername = await _userRepository.completeOnboarding(
        userId: userId,
        username: state.username,
        usernameWasEdited: state.usernameWasEdited,
        displayName: state.displayName,
        avatarUrl: state.avatarUrl,
        gender: gender,
        dateOfBirth: dateOfBirth,
        heightCm: state.heightCm,
        currentWeightKg: state.currentWeightKg,
        targetWeightKg: state.effectiveTargetWeightKg,
        activityLevel: state.activityLevel,
        units: state.unitSystem,
        plan: plan,
      );

      emit(state.copyWith(
        username: storedUsername,
        submission: SubmissionStatus.success,
        clearError: true,
      ));
      return true;
    } on UsernameTakenException {
      emit(state.copyWith(
        submission: SubmissionStatus.failure,
        errorMessage: 'username_taken_error',
      ));
      return false;
    } on PostgrestException catch (error) {
      emit(state.copyWith(
        submission: SubmissionStatus.failure,
        errorMessage: error.message,
      ));
      return false;
    } catch (error) {
      emit(state.copyWith(
        submission: SubmissionStatus.failure,
        errorMessage: error.toString(),
      ));
      return false;
    }
  }

  @override
  Future<void> close() {
    _usernameDebounce?.cancel();
    return super.close();
  }
}
