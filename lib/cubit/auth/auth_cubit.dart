import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics_events.dart';
import '../../core/error_text.dart';
import '../../core/telemetry.dart';
import '../../data/app_preferences.dart';
import '../../data/auth_repository.dart';

part 'auth_state.dart';

/// Screen 1 only. Establishes the Supabase Auth session and nothing else —
/// the public `users` row is deferred to the end of onboarding by design.
class AuthCubit extends Cubit<AuthenticationState> {
  AuthCubit({
    required AuthRepository authRepository,
    AppPreferences? preferences,
  })  : _authRepository = authRepository,
        _preferences = preferences ?? AppPreferences(),
        super(const AuthenticationState()) {
    _bootstrap();
  }

  final AuthRepository _authRepository;
  final AppPreferences _preferences;
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
          // Here rather than in `_signIn`, because this is the line every
          // route to a session passes through: the native sheets, the OAuth
          // redirect, and a session restored from disk on cold start.
          //
          // The id and nothing else — never the email this `user` also
          // carries. See `Telemetry.identify`.
          unawaited(Telemetry.identify(user.id));
          unawaited(Telemetry.send(AnalyticsEvent.signInSucceeded(
            provider: state.pendingProvider.name,
            // Supabase reports these equal on the row it creates, and apart
            // from then on, which is as close to "first ever sign-in" as the
            // client can get without asking the database.
            isNewUser: user.createdAt == user.lastSignInAt,
          )));

          emit(state.copyWith(
            status: AuthStatus.authenticated,
            user: user,
            pendingProvider: AuthProviderKind.none,
            clearError: true,
          ));
        } else if (data.event == AuthChangeEvent.signedOut) {
          unawaited(Telemetry.identify(null));
          emit(const AuthenticationState(status: AuthStatus.unauthenticated));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // A failure on the auth *stream* rather than on a button, so there is
        // no call site to attribute it to and nothing the user did to cause
        // it. Worth a report for that reason.
        unawaited(Telemetry.recordError(error, stackTrace,
            reason: 'auth state stream'));
        emit(state.copyWith(
          status: AuthStatus.failure,
          pendingProvider: AuthProviderKind.none,
          errorMessage: describeError(error),
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
      Future<void> Function() action, // Changed to Future<void> since native flow doesn't return a 'launched' boolean
      ) async {
    unawaited(Telemetry.send(AnalyticsEvent.signInStarted(provider: kind.name)));

    emit(state.copyWith(
      status: AuthStatus.loading,
      pendingProvider: kind,
      clearError: true,
    ));

    try {
      // With native sign-in, this awaits the actual dialog and token exchange.
      await action();

      // On success, the `onAuthStateChange` listener in _bootstrap()
      // will still automatically catch the new session and emit AuthStatus.authenticated.
    } on SignInCancelled {
      // Backing out of the account picker is a choice, not a failure. Drop the
      // spinner and leave the buttons ready, with no error snackbar. Still
      // counted: a high cancel rate on one provider is a broken provider.
      unawaited(Telemetry.send(AnalyticsEvent.signInFailed(
        provider: kind.name,
        reason: 'cancelled',
      )));
      emit(state.copyWith(
        status: AuthStatus.initial,
        pendingProvider: AuthProviderKind.none,
        clearError: true,
      ));
    } on AuthException catch (error, stackTrace) {
      // The provider's own message can carry an email address, so the event
      // gets a category and Crashlytics gets the exception.
      unawaited(Telemetry.send(AnalyticsEvent.signInFailed(
        provider: kind.name,
        reason: describeFailure(error).kind.name,
      )));
      unawaited(Telemetry.recordError(error, stackTrace,
          reason: 'sign-in with ${kind.name}'));
      emit(state.copyWith(
        status: AuthStatus.failure,
        pendingProvider: AuthProviderKind.none,
        errorMessage: describeError(error),
      ));
    } catch (error, stackTrace) {
      unawaited(Telemetry.send(AnalyticsEvent.signInFailed(
        provider: kind.name,
        reason: describeFailure(error).kind.name,
      )));
      unawaited(Telemetry.recordError(error, stackTrace,
          reason: 'sign-in with ${kind.name}'));
      emit(state.copyWith(
        status: AuthStatus.failure,
        pendingProvider: AuthProviderKind.none,
        errorMessage: describeError(error),
      ));
    }
  }

  Future<void> signOut() async {
    unawaited(Telemetry.send(AnalyticsEvent.signedOut()));
    await _authRepository.signOut();
    // Cleared before the state changes: the remembered "this user finished
    // onboarding" is what launch routes on, and leaving it behind would send
    // the next account straight past a flow it has not been through.
    await _preferences.clear();
    emit(const AuthenticationState(status: AuthStatus.unauthenticated));
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}
