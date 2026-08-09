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

  /// Where Supabase sends the user once the provider has authenticated them.
  ///
  /// Note this is the *second* hop, and is not the same URL as the one
  /// configured in Google Cloud or the Apple Developer portal. Those point at
  /// `<project>.supabase.co/auth/v1/callback` — the provider-to-Supabase hop.
  /// This one is the Supabase-to-app hop, and it must be allow-listed
  /// separately under Authentication -> URL Configuration -> Redirect URLs.
  ///
  /// The scheme is the app's bundle ID (reverse-DNS, per RFC 8252) and must
  /// match AndroidManifest.xml and ios/Runner/Info.plist.
  static const String oauthRedirectUrl = 'com.alimahmoud.bulkr://login-callback';
}
