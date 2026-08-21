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
    this.isSaving = false,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  final ProfileStatus status;
  final UserProfile? profile;
  final List<WeightEntry> weightHistory;
  final String? errorMessage;

  /// A write (weigh-in, target, plan) is in flight. Kept separate from
  /// [status] so saving never blanks the loaded screen.
  final bool isSaving;

  /// Translation key for a write that failed, cleared once shown.
  final String? actionErrorKey;

  /// The underlying failure, verbatim — a Postgres error code and message says
  /// "row-level security policy" where a friendly string just says "try again".
  final String? actionErrorDetail;

  bool get isLoading => status == ProfileStatus.loading;

  /// A line needs two points. One weigh-in is a dot, not a trend.
  bool get hasChartData => weightHistory.length >= 2;

  ProfileState copyWith({
    ProfileStatus? status,
    UserProfile? profile,
    List<WeightEntry>? weightHistory,
    String? errorMessage,
    bool clearError = false,
    bool? isSaving,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearActionError = false,
  }) {
    return ProfileState(
      status: status ?? this.status,
      profile: profile ?? this.profile,
      weightHistory: weightHistory ?? this.weightHistory,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSaving: isSaving ?? this.isSaving,
      actionErrorKey:
          clearActionError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail: clearActionError
          ? null
          : (actionErrorDetail ?? this.actionErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        status,
        profile,
        weightHistory,
        errorMessage,
        isSaving,
        actionErrorKey,
        actionErrorDetail,
      ];
}
