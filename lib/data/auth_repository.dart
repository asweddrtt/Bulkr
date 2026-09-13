import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/supabase_config.dart';
import '../core/oauth_nonce.dart';

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

  /// The nonce behind this app run's Google sign-ins.
  ///
  /// Per run rather than per attempt, and not by choice: `initialize()` is the
  /// only place google_sign_in accepts a nonce — `authenticate()` takes a
  /// scope hint and nothing else — and initialising more than once is
  /// documented as undefined. So the nonce is fixed for as long as the process
  /// lives, which still ties a token to this install rather than to nothing at
  /// all.
  late final String _googleRawNonce = OAuthNonce.generate();
  late final String _googleHashedNonce = OAuthNonce.hash(_googleRawNonce);

  User? get currentUser => _client.auth.currentUser;

  bool get hasSession => _client.auth.currentSession != null;

  /// Emits on sign-in, sign-out, and token refresh.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<void> _ensureGoogleInitialized() {
    return _googleInitialization ??= GoogleSignIn.instance.initialize(
      nonce: _googleHashedNonce,
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
      // Read back out of the token rather than assumed. iOS was returning a
      // token with a nonce claim while this passed none, and Supabase rejects
      // that mismatch outright: "Passed nonce and nonce in id_token should
      // either both exist or not".
      nonce: OAuthNonce.forSupabase(
        claim: OAuthNonce.claimOf(idToken),
        raw: _googleRawNonce,
        hashed: _googleHashedNonce,
      ),
    );
  }

  /// Apple's own sheet on iOS and macOS; the browser flow elsewhere.
  ///
  /// The browser flow was never right here. It needs a redirect back into the
  /// app, which is one more thing to get wrong, and on iOS it got it wrong —
  /// `PlatformException(Error, Error while launching …/authorize?provider=apple)`
  /// on every tap. Apple's guidelines expect the native sheet on their
  /// platforms anyway, so the fallback exists for Android alone.
  Future<void> signInWithApple() async {
    if (!_isApplePlatform) return _signInWithAppleViaBrowser();

    final String raw = OAuthNonce.generate();
    final String hashed = OAuthNonce.hash(raw);

    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        // Apple stamps this into the identity token, so the token cannot be
        // replayed into a different sign-in attempt.
        nonce: hashed,
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      if (error.code == AuthorizationErrorCode.canceled) {
        throw const SignInCancelled();
      }
      rethrow;
    }

    final String? idToken = credential.identityToken;
    if (idToken == null) {
      throw const AuthException(
        'Apple did not return an identity token. Check that Sign in with Apple '
        'is enabled for this App ID and included in the provisioning profile.',
      );
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.apple,
      idToken: idToken,
      nonce: OAuthNonce.forSupabase(
        claim: OAuthNonce.claimOf(idToken),
        raw: raw,
        hashed: hashed,
      ),
    );
  }

  Future<void> _signInWithAppleViaBrowser() async {
    final launched = await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
      // A Chrome Custom Tab. It overlays the app instead of throwing the user
      // out into a full browser window, and unlike an embedded WebView it
      // isn't blocked by providers as a disallowed user agent.
      authScreenLaunchMode: LaunchMode.inAppBrowserView,
    );

    // The session itself arrives asynchronously via onAuthStateChange once the
    // provider redirects back. A false here means the browser never opened, so
    // nothing is coming — without this the UI would spin forever.
    if (!launched) throw const SignInCancelled();
  }

  // --- Email and password -------------------------------------------------

  /// Creates an account and asks Supabase to send the confirmation email.
  ///
  /// Returns whether a confirmation is still outstanding. With email
  /// confirmation on — which it is — `signUp` returns a user but **no
  /// session**, and the account cannot be used until the link is tapped. The
  /// screen needs to know which of those happened to say the right thing.
  ///
  /// [emailRedirectTo] is the same custom scheme the OAuth callback uses, so
  /// the link opens the app rather than a browser page saying "you may now
  /// close this tab". `supabase_flutter` is already listening for it.
  ///
  /// ## On an address that already has an account
  ///
  /// Supabase deliberately does not always say so — depending on project
  /// settings it answers as though the sign-up worked, to stop this endpoint
  /// being used to discover which addresses are registered. So a `true` here
  /// means "we have asked for an email to be sent", not "a new account
  /// exists", and the screen's wording has to survive both.
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: SupabaseConfig.oauthRedirectUrl,
    );

    return response.session == null;
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Sends the "set a new password" email.
  ///
  /// Never reports whether the address had an account, and Supabase does not
  /// either — the screen says "if that address has an account" for the same
  /// reason the sign-in failure does not name which half was wrong.
  Future<void> sendPasswordReset(String email) async {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
    );
  }

  /// Sends the confirmation email again.
  ///
  /// The common case is not a lost email — it is an address typed wrong, or an
  /// email sitting in spam an hour after somebody gave up. Either way the
  /// button is cheap and the alternative is an account they cannot use.
  Future<void> resendConfirmation(String email) async {
    await _client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: SupabaseConfig.oauthRedirectUrl,
    );
  }

  /// Sets a new password for the signed-in user.
  ///
  /// Called after a recovery link has been followed, at which point there is a
  /// real session — which is what makes this a normal update rather than
  /// anything special.
  Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
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
