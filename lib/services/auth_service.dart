import '../models/auth_user.dart';

/// Sign-in seam. [LocalAuthService] keeps a device-local identity so the rest
/// of the app can be built against a signed-in user.
abstract class AuthService {
  Future<AuthUser> signIn(AuthProvider provider);

  Future<void> signOut();
}

/// TODO: replace with the real providers (Apple / Google OAuth). Doing so needs
/// the client IDs and native config, and only this class has to change — the
/// controller and screens already work against [AuthUser].
class LocalAuthService implements AuthService {
  const LocalAuthService();

  @override
  Future<AuthUser> signIn(AuthProvider provider) async {
    return AuthUser(
      id: 'local-${provider.name}',
      displayName: '',
      provider: provider,
    );
  }

  @override
  Future<void> signOut() async {}
}
