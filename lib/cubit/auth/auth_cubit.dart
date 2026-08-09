import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth_repository.dart';

part 'auth_state.dart';

/// Screen 1 only. Establishes the Supabase Auth session and nothing else —
/// the public `users` row is deferred to the end of onboarding by design.
class AuthCubit extends Cubit<AuthenticationState> {
  AuthCubit({required AuthRepository authRepository})
      : _authRepository = authRepository,
        super(const AuthenticationState()) {
    _bootstrap();
  }

  final AuthRepository _authRepository;
  StreamSubscription<AuthState>? _authSubscription;

  void _bootstrap() {
    // A session restored from disk on cold start.
    final existing = _authRepository.currentUser;
    if (existing != null) {
      emit(state.copyWith(status: AuthStatus.authenticated, user: existing));
    }

    // OAuth completes out-of-process: the provider redirects back into the app
    // via the deep link, and the session surfaces here rather than as the
    // return value of the sign-in call.
    _authSubscription = _authRepository.onAuthStateChange.listen(
      (data) {
        final user = data.session?.user;
        if (user != null) {
          emit(state.copyWith(
            status: AuthStatus.authenticated,
            user: user,
            pendingProvider: AuthProviderKind.none,
            clearError: true,
          ));
        } else if (data.event == AuthChangeEvent.signedOut) {
          emit(const AuthenticationState(status: AuthStatus.unauthenticated));
        }
      },
      onError: (Object error) {
        emit(state.copyWith(
          status: AuthStatus.failure,
          pendingProvider: AuthProviderKind.none,
          errorMessage: error.toString(),
        ));
      },
    );
  }

  Future<void> signInWithGoogle() => _signIn(
        AuthProviderKind.google,
        _authRepository.signInWithGoogle,
      );

  Future<void> signInWithApple() => _signIn(
        AuthProviderKind.apple,
        _authRepository.signInWithApple,
      );

  Future<void> _signIn(
    AuthProviderKind kind,
    Future<bool> Function() action,
  ) async {
    emit(state.copyWith(
      status: AuthStatus.loading,
      pendingProvider: kind,
      clearError: true,
    ));

    try {
      final launched = await action();
      if (!launched) {
        emit(state.copyWith(
          status: AuthStatus.failure,
          pendingProvider: AuthProviderKind.none,
          errorMessage: 'auth_error_cancelled',
        ));
      }
      // On success we stay in `loading` on purpose: the session only exists
      // once the provider redirects back and the listener above fires.
    } on AuthException catch (error) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        pendingProvider: AuthProviderKind.none,
        errorMessage: error.message,
      ));
    } catch (error) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        pendingProvider: AuthProviderKind.none,
        errorMessage: error.toString(),
      ));
    }
  }

  Future<void> signOut() async {
    await _authRepository.signOut();
    emit(const AuthenticationState(status: AuthStatus.unauthenticated));
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
