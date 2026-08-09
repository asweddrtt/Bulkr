import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

/// The user dismissed the sign-in sheet.
///
/// Deliberately its own type rather than an [AuthException]: backing out is a
/// choice, not a failure, and it should not surface an error to the user.
class SignInCancelled implements Exception {
  const SignInCancelled();

  @override
  String toString() => 'Sign-in was cancelled by the user';
}

/// Screen 1's only job: get a Supabase Auth session.
///
/// Per the onboarding brief this deliberately does *not* create the public
/// `users` row — that happens once, at the end of the flow, in
/// [UserRepository.completeOnboarding].
class AuthRepository {
  AuthRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// google_sign_in requires `initialize()` to be awaited exactly once before
  /// any other call; the package documents calling it more than once as
  /// undefined behaviour. Memoised, because sign-in can be attempted repeatedly
  /// — cancel, retry, cancel again — and each attempt would otherwise
  /// re-initialise the plugin.
  Future<void>? _googleInitialization;

  User? get currentUser => _client.auth.currentUser;

  bool get hasSession => _client.auth.currentSession != null;

  /// Emits on sign-in, sign-out, and token refresh.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> _ensureGoogleInitialized() {
    return _googleInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: SupabaseConfig.googleWebClientId,
      // Android resolves its client from the package name + signing SHA-1, so
      // it must not be given the iOS ID.
      clientId: _isApplePlatform && SupabaseConfig.googleIosClientId.isNotEmpty
          ? SupabaseConfig.googleIosClientId
          : null,
    );
  }

  static bool get _isApplePlatform =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Native account picker — no browser, no redirect.
  Future<void> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const SignInCancelled();
      }
      rethrow;
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google did not return an ID token. Check that the Web client ID is '
        'correct and that the app signing certificate is registered.',
      );
    }

    // Non-prompting on purpose. authorizeScopes() would show a *second* consent
    // dialog stacked on top of the account picker, which defeats the point of
    // going native. Supabase only needs the ID token — the access token is a
    // bonus we pass along when it happens to already be granted.
    final authorization = await account.authorizationClient
        .authorizationForScopes(const ['email', 'profile']);

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization?.accessToken,
    );
  }

  /// Apple still uses the browser flow.
  ///
  /// Native Sign in with Apple needs the `sign_in_with_apple` package and is
  /// what Apple expects for App Store submission — see the README.
  Future<void> signInWithApple() async {
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
      // An in-app browser view: a Chrome Custom Tab on Android, an
      // SFSafariViewController on iOS. It overlays the app instead of throwing
      // the user out into a full browser window, and unlike an embedded
      // WebView it isn't blocked by providers as a disallowed user agent.
      authScreenLaunchMode: LaunchMode.inAppBrowserView,
    );

    // The session itself arrives asynchronously via onAuthStateChange once the
    // provider redirects back. A false here means the browser never opened, so
    // nothing is coming — without this the UI would spin forever.
    if (!launched) throw const SignInCancelled();
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Best-effort display name from the provider's metadata.
  String? displayNameOf(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    for (final key in ['full_name', 'name', 'preferred_username']) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String? avatarUrlOf(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    for (final key in ['avatar_url', 'picture']) {
      final value = metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}
