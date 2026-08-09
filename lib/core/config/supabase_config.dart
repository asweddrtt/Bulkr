/// Supabase connection settings.
///
/// The publishable key is the successor to the old `anon` key: it is designed
/// to ship inside the client bundle and is not a secret. What actually protects
/// the data is Row Level Security on the tables it can reach.
///
/// Both values can be overridden per build without touching source:
///
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hqdfaeiyflbbzkduskaz.supabase.co',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_IqsE_HlYpC5xrSplah-9aw_KneTKqrs',
  );

  /// Where the OAuth provider sends the user once they've authenticated.
  ///
  /// This exact string must be allow-listed under
  /// Authentication -> URL Configuration -> Redirect URLs in the Supabase
  /// dashboard, and it must match the scheme registered in
  /// AndroidManifest.xml and ios/Runner/Info.plist.
  static const String oauthRedirectUrl = 'io.bulkr://login-callback';
}
