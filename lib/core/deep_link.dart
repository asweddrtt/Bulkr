import 'package:flutter/foundation.dart';

import 'post_link.dart';

/// Somewhere in the app a link can point to.
///
/// A sealed type rather than a nullable id, because there will be more of
/// these — a profile, a group, a challenge all have the same shape — and the
/// point of doing this once is that adding the second one is a case rather
/// than a second parser.
@immutable
sealed class DeepLink {
  const DeepLink();

  /// What [uri] points at, or null when it points at nothing this app knows.
  ///
  /// Deliberately strict. This runs on *every* URI the OS hands the app, which
  /// includes the OAuth callback `com.alimahmoud.bulkr://login-callback` that
  /// `supabase_flutter` is also listening for. Matching loosely — on the
  /// scheme alone, or on "contains an id" — would mean a sign-in redirect
  /// opening a post screen over the top of the sign-in it was completing.
  static DeepLink? parse(Uri uri) {
    // The scheme is the app's bundle id, per RFC 8252, which is what stops
    // another app on the device claiming it. Compared case-insensitively
    // because a URI scheme is case-insensitive by definition and iOS has been
    // known to hand one back lowercased.
    if (uri.scheme.toLowerCase() != PostLink.scheme.toLowerCase()) return null;

    return switch (uri.host.toLowerCase()) {
      PostLink.postHost => _post(uri),
      // `login-callback` lands here and is deliberately unhandled: it belongs
      // to Supabase's own listener, and answering it here would be two things
      // reacting to one redirect.
      _ => null,
    };
  }

  static DeepLink? _post(Uri uri) {
    // `bulkr://post/<id>` — one segment, and it has to be there. An empty or
    // multi-segment path is a link this version does not understand, and
    // guessing at it is how a bad link becomes a crash.
    final List<String> segments =
        uri.pathSegments.where((String s) => s.isNotEmpty).toList();
    if (segments.length != 1) return null;

    final String id = segments.single;
    if (id.isEmpty || id.length > _maxIdLength) return null;

    return PostDeepLink(id);
  }

  /// A UUID is 36 characters. The cap is not validation — the server decides
  /// whether an id is real — it is a bound on what gets put in a request and
  /// an event, so a hostile link cannot make either arbitrarily large.
  static const int _maxIdLength = 64;
}

/// A link to one post.
@immutable
final class PostDeepLink extends DeepLink {
  const PostDeepLink(this.postId);

  final String postId;

  @override
  bool operator ==(Object other) =>
      other is PostDeepLink && other.postId == postId;

  @override
  int get hashCode => postId.hashCode;

  @override
  String toString() => 'PostDeepLink($postId)';
}
