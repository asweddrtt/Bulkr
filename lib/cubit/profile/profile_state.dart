part of 'profile_cubit.dart';

enum ProfileStatus {
  initial,
  loading,

  /// The row loaded.
  ready,

  /// Authenticated, but no `users` row — onboarding was never finished.
  missing,

  failure,
}

class ProfileState extends Equatable {
  const ProfileState({
    this.status = ProfileStatus.initial,
    this.profile,
    this.weightHistory = const [],
    this.errorMessage,
  });

  final ProfileStatus status;
  final UserProfile? profile;
  final List<WeightEntry> weightHistory;
  final String? errorMessage;

  bool get isLoading => status == ProfileStatus.loading;

  /// A line needs two points. One weigh-in is a dot, not a trend.
  bool get hasChartData => weightHistory.length >= 2;

  ProfileState copyWith({
    ProfileStatus? status,
    UserProfile? profile,
    List<WeightEntry>? weightHistory,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      weightHistory: weightHistory ?? this.weightHistory,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, profile, weightHistory, errorMessage];
}
