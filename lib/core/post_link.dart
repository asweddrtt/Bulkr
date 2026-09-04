import '../models/post.dart';

/// Sharing a post.
///
/// ## Why this copies a link instead of opening the OS share sheet
///
/// The native sheet means a plugin with platform code on both sides —
/// `share_plus` or equivalent. This project's Android build is documented as
/// fragile for exactly that reason: the README has a whole section on
/// `app_links` declaring an AGP version this Gradle cannot configure, and the
/// fix is a version pin that is still in `pubspec.yaml`. Adding another native
/// plugin is a real risk to a build that already needs a pin to work, taken on
/// behalf of a feature that copying to the clipboard delivers most of.
///
/// So: the clipboard, zero new dependencies, and a link that resolves in the
/// app. Swapping in the native sheet later changes this one file.
///
/// ## Why the link is not a URL
///
/// A tappable https link needs a domain that serves something, an
/// Apple App Site Association file and an Android Digital Asset Links file to
/// claim it, and a web page for whoever taps it without the app. None of that
/// is code — it is infrastructure this project does not have yet.
///
/// The custom scheme is what does exist: `com.alimahmoud.bulkr://` is already
/// registered on both platforms for the OAuth callback, so a link under it
/// opens the app on a device that has it. On a device that does not, it opens
/// nothing — which is why the copied text carries the post itself alongside
/// the link, so what gets pasted is readable either way.
class PostLink {
  const PostLink._();

  /// The app's URL scheme.
  ///
  /// Matches `SupabaseConfig.oauthRedirectUrl`, `AndroidManifest.xml` and
  /// `Info.plist` — the same reverse-DNS scheme, per RFC 8252, which is what
  /// stops another app on the device claiming it.
  static const String scheme = 'com.alimahmoud.bulkr';

  /// A deep link to one post.
  static String forPost(String postId) => '$scheme://post/$postId';

  /// What goes on the clipboard: the post, then the link.
  ///
  /// The words first, because that is what the recipient will actually read,
  /// and because a message that opens with a URL scheme nobody recognises
  /// looks like spam. Truncated, since a two-thousand-character post pasted
  /// into a chat is not a share, it is a wall.
  static String shareText(Post post) {
    final String? content = post.content?.trim();
    final String link = forPost(post.id);

    if (content == null || content.isEmpty) {
      return '${post.authorName} on Bulkr\n$link';
    }

    return '${_truncate(content)}\n\n— ${post.authorName} on Bulkr\n$link';
  }

  /// How much of a post's text the shared blob carries.
  static const int excerptLength = 280;

  static String _truncate(String text) {
    if (text.length <= excerptLength) return text;

    // Cut at the last space before the limit, so the excerpt does not end
    // mid-word. Falls back to a hard cut when there is no space to find —
    // which is one very long word, and rare enough not to be worth more care.
    final String clipped = text.substring(0, excerptLength);
    final int lastSpace = clipped.lastIndexOf(' ');

    return '${lastSpace > excerptLength ~/ 2 ? clipped.substring(0, lastSpace) : clipped}…';
  }
}
