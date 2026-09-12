import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../core/deep_link.dart';

/// Links arriving from outside the app.
///
/// Two sources, and both are needed for the feature to work at all:
///
///   - a link tapped while Bulkr is already running, which arrives on
///     [AppLinks.uriLinkStream]
///   - a link that *launched* Bulkr, which is not on the stream at all and has
///     to be asked for once with [AppLinks.getInitialLink]
///
/// Missing the second is the classic version of this bug: the feature works
/// perfectly for whoever built it, because their app was already open, and
/// does nothing for the person receiving a link for the first time — who by
/// definition does not have it open.
///
/// Shaped like [PushService]'s tap handling on purpose. That solved the same
/// problem for notifications, down to answering the cold-start case exactly
/// once, and two things that behave identically should look identical.
class DeepLinkListener {
  DeepLinkListener({AppLinks? appLinks}) : _injected = appLinks;

  final AppLinks? _injected;

  /// Resolved on first use rather than in the constructor.
  ///
  /// Same reasoning as `PushService._messaging`: constructing a class must not
  /// be able to throw, because it happens inside `initState` and a throw there
  /// produces no frame at all — a white screen with no error, which this app
  /// has shipped once already.
  late final AppLinks _links = _injected ?? AppLinks();

  StreamSubscription<Uri>? _subscription;

  /// Whether the launch link has been claimed.
  ///
  /// `getInitialLink` answers with the same URI every time it is asked, so a
  /// second ask opens a second copy of the same screen — one identical screen
  /// stacked on another, with a back gesture that appears not to work.
  bool _initialTaken = false;

  /// Starts listening, and hands back anything that arrives.
  ///
  /// Never throws. A device that cannot report links is a device where sharing
  /// does not work, not one where the app does not start.
  void start(void Function(DeepLink link) onLink) {
    _subscription ??= _links.uriLinkStream.listen(
      (Uri uri) => _dispatch(uri, onLink),
      onError: (Object error) {
        debugPrint('Bulkr deep link: stream failed — $error');
      },
    );
  }

  /// The link that launched the app, if one did. Answers once.
  Future<DeepLink?> takeInitialLink() async {
    if (_initialTaken) return null;
    _initialTaken = true;

    try {
      final Uri? uri = await _links.getInitialLink();
      if (uri == null) return null;

      final DeepLink? link = DeepLink.parse(uri);
      // Logged either way: "I tapped the link and nothing happened" has
      // several causes, and whether the URI arrived at all separates the
      // native ones from the Dart ones.
      debugPrint(
        'Bulkr deep link: launched with $uri, '
        '${link == null ? 'which is not a link this app handles' : 'opening $link'}',
      );
      return link;
    } catch (error) {
      debugPrint('Bulkr deep link: launch link unavailable — $error');
      return null;
    }
  }

  void _dispatch(Uri uri, void Function(DeepLink link) onLink) {
    final DeepLink? link = DeepLink.parse(uri);
    if (link == null) {
      // Expected, routinely: the OAuth callback comes down this same stream
      // and belongs to Supabase's listener. Not a warning.
      debugPrint('Bulkr deep link: ignoring $uri');
      return;
    }

    debugPrint('Bulkr deep link: opening $link');
    onLink(link);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
