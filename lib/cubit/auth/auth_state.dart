part of 'auth_cubit.dart';

enum AuthStatus { initial, loading, authenticated, unauthenticated, failure }

/// Which button is spinning, so screen 1 can show the loader on the one the
/// user actually tapped rather than on both.
enum AuthProviderKind { none, google, apple }

class AuthenticationState extends Equatable {
  const AuthenticationState({
    this.status = AuthStatus.initial,
    this.user,
    this.pendingProvider = AuthProviderKind.none,
    this.errorMessage,
  });

  final AuthStatus status;
  final User? user;
  final AuthProviderKind pendingProvider;
  final String? errorMessage;

  bool get isLoading => status == AuthStatus.loading;

  bool get isAuthenticated => status == AuthStatus.authenticated && user != null;

  AuthenticationState copyWith({
    AuthStatus? status,
    User? user,
    AuthProviderKind? pendingProvider,
    String? errorMessage,
    bool clearError = false,
    bool clearUser = false,
  }) {
    return AuthenticationState(
      status: status ?? this.status,
      user: clearUser ? null : (user ?? this.user),
      pendingProvider: pendingProvider ?? this.pendingProvider,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [status, user?.id, pendingProvider, errorMessage];
}
