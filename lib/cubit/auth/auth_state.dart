part of 'auth_cubit.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, failure }

/// Which button is spinning, so screen 1 can show the loader on the one the
/// user actually tapped rather than on both.
enum AuthProviderKind { none, google, apple, email }

class AuthenticationState extends Equatable {
  const AuthenticationState({
    this.status = AuthStatus.initial,
    this.user,
    this.pendingProvider = AuthProviderKind.none,
    this.errorMessage,
    this.emailNotice,
    this.awaitingConfirmationFor,
  });

  final AuthStatus status;
  final User? user;
  final AuthProviderKind pendingProvider;
  final String? errorMessage;

  /// Translation key for something that went *right* on the email screen — a
  /// confirmation sent, a reset on its way.
  ///
  /// Separate from [errorMessage] rather than reusing it, because these are
  /// the only outcomes in the whole flow that are neither a session nor a
  /// failure: the user has done everything correctly and still has to go and
  /// look in their inbox.
  final String? emailNotice;

  /// The address whose confirmation is outstanding, when one is.
  ///
  /// Kept so the screen can offer to send it again without asking the user to
  /// retype what they just typed — and so "resend" cannot be aimed at an
  /// address they never entered.
  final String? awaitingConfirmationFor;

  bool get isLoading => status == AuthStatus.loading;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthenticationState copyWith({
    AuthStatus? status,
    User? user,
    AuthProviderKind? pendingProvider,
    String? errorMessage,
    bool clearError = false,
    bool clearUser = false,
    String? emailNotice,
    bool clearNotice = false,
    String? awaitingConfirmationFor,
    bool clearAwaitingConfirmation = false,
  }) {
    return AuthenticationState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      pendingProvider: pendingProvider ?? this.pendingProvider,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      emailNotice: clearNotice ? null : (emailNotice ?? this.emailNotice),
      awaitingConfirmationFor: clearAwaitingConfirmation
          ? null
          : (awaitingConfirmationFor ?? this.awaitingConfirmationFor),
    );
  }

  @override
  List<Object?> get props => [
        status,
        user?.id,
        pendingProvider,
        errorMessage,
        emailNotice,
        awaitingConfirmationFor,
      ];
}
