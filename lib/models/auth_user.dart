/// Identity provider the athlete signed in with.
enum AuthProvider { apple, google, email }

/// The signed-in identity, independent of the training data attached to it.
class AuthUser {
  final String id;
  final String displayName;
  final AuthProvider provider;

  const AuthUser({
    required this.id,
    required this.displayName,
    required this.provider,
  });
}
