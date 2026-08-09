

import 'package:bulkr/core/config/supabase_config.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Screen 1's only job: get a Supabase Auth session.
///
/// Per the onboarding brief this deliberately does *not* create the public
/// `users` row — that happens once, at the end of the flow, in
/// [UserRepository.completeOnboarding].
class AuthRepository {
  AuthRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;

  bool get hasSession => _client.auth.currentSession != null;

  /// Emits on sign-in, sign-out, and token refresh.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> signInWithGoogle() async {
    const webClientId = '482455223938-1lgs1ncqktbfsnfc9c4onmoespt5h94j.apps.googleusercontent.com';

    // 1. Ensure initialization using the singleton (Required in v7.0.0+)
    final googleSignIn = GoogleSignIn.instance;
    await googleSignIn.initialize(
      serverClientId: webClientId,
    );

    try {
      // 2. Authentication (Identity) - Triggers the native bottom sheet
      final googleUser = await googleSignIn.authenticate();

      // 3. Extract the ID Token (Authentication)
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw const AuthException('Missing Google ID Token');
      }

      // 4. Extract the Access Token (Authorization)
      final clientAuth = await googleUser.authorizationClient?.authorizeScopes(['email', 'profile']);
      final accessToken = clientAuth?.accessToken;

      // 5. Pass the tokens to Supabase invisibly
      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

    } catch (error) {
      throw AuthException('Sign in failed: $error');
    }
  }

  /// Apple is currently still using the Web Flow.
  Future<void> signInWithApple() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
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