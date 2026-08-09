import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';

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

  Future<bool> signInWithGoogle() => _signInWithOAuth(OAuthProvider.google);

  Future<bool> signInWithApple() => _signInWithOAuth(OAuthProvider.apple);

  Future<void> signOut() => _client.auth.signOut();

  /// Opens the provider's consent screen.
  ///
  /// The returned bool only reports that the browser/sheet was launched. The
  /// session itself arrives asynchronously through [onAuthStateChange] once the
  /// provider redirects back to [SupabaseConfig.oauthRedirectUrl], which is why
  /// AuthCubit listens rather than awaiting a user here.
  Future<bool> _signInWithOAuth(OAuthProvider provider) {
    return _client.auth.signInWithOAuth(
      provider,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
  }

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
