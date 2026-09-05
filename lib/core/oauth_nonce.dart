import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The nonce dance, in one place.
///
/// Both native sign-in flows hand Supabase an ID token minted by somebody else,
/// so Supabase needs a way to know the token was minted for *this* attempt
/// rather than replayed from another one. The nonce is that proof: the app
/// invents a random string, gives the provider its SHA-256 hash, and gives
/// Supabase the original. The provider stamps the hash into the token; Supabase
/// hashes what it was given and compares.
///
/// Getting it half-right is worse than not doing it. GoTrue rejects a token
/// whose nonce claim and passed nonce disagree about *existing* —
/// "Passed nonce and nonce in id_token should either both exist or not" — which
/// is the error the iOS build hit, because the Google SDK put a nonce in the
/// token while the app passed none.
abstract final class OAuthNonce {
  static final Random _random = Random.secure();

  /// 32 bytes of entropy, url-safe so it survives every transport.
  static String generate() {
    final List<int> bytes =
        List<int>.generate(32, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// What the provider is given.
  static String hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

  /// The `nonce` claim in an ID token, or null if it has none.
  ///
  /// The token is not verified here and does not need to be — Supabase does
  /// that, against the provider's keys. This only reads one claim in order to
  /// decide what to send, and a token this can't parse is one Supabase will
  /// reject anyway.
  static String? claimOf(String idToken) {
    try {
      final List<String> parts = idToken.split('.');
      if (parts.length != 3) return null;

      final String padded = base64Url.normalize(parts[1]);
      final Object? payload = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (payload is! Map<String, dynamic>) return null;

      final Object? nonce = payload['nonce'];
      return nonce is String && nonce.isNotEmpty ? nonce : null;
    } catch (_) {
      return null;
    }
  }

  /// What to pass to `signInWithIdToken`, given the token that came back.
  ///
  /// Three cases, and the last one is why this is a function rather than a
  /// constant. Normally the provider stamps in the hash we gave it, so Supabase
  /// gets the original and its own hashing lines the two up. If the token has
  /// no nonce at all, Supabase must be told nothing, or the "both exist or not"
  /// check fails. And if the SDK ignored our hash and stamped in a nonce of its
  /// own — which is exactly what iOS appeared to do — the only value that can
  /// possibly match is the claim itself.
  static String? forSupabase({
    required String? claim,
    required String raw,
    required String hashed,
  }) {
    if (claim == null) return null;
    if (claim == hashed) return raw;
    return claim;
  }
}
