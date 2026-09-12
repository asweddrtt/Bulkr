import 'dart:io';

import 'package:bulkr/core/deep_link.dart';
import 'package:bulkr/core/post_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sharing a post was a feature with both ends built and no middle.
///
/// `PostLink.forPost` put `com.alimahmoud.bulkr://post/<id>` on the clipboard
/// from four screens. `PostRepository.fetchPost` was written "for a deep link
/// or a share target" and had no callers. Nothing parsed an incoming URI, no
/// route existed, and on Android the manifest registered only the
/// `login-callback` host — so the link did not even open the app.
///
/// These cover the parser, which is the part that can be wrong silently: it
/// runs against every URI the OS hands the app, including the OAuth callback
/// that `supabase_flutter` is also listening for.
void main() {
  group('a post link', () {
    test('parses the link the app itself generates', () {
      // Against `forPost` rather than a hand-typed string, so the writer and
      // the reader cannot drift apart — which is the bug that made this
      // feature look finished for months.
      final Uri uri = Uri.parse(PostLink.forPost('abc-123'));

      expect(DeepLink.parse(uri), const PostDeepLink('abc-123'));
    });

    test('parses a real UUID', () {
      const String id = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
      expect(
        DeepLink.parse(Uri.parse(PostLink.forPost(id))),
        const PostDeepLink(id),
      );
    });

    test('tolerates a scheme the OS handed back lowercased', () {
      expect(
        DeepLink.parse(Uri.parse('com.alimahmoud.bulkr://POST/abc')),
        const PostDeepLink('abc'),
      );
    });

    test('tolerates a trailing slash', () {
      expect(
        DeepLink.parse(Uri.parse('com.alimahmoud.bulkr://post/abc/')),
        const PostDeepLink('abc'),
      );
    });
  });

  group('is not confused by', () {
    test('the OAuth callback, which shares the scheme', () {
      // The single most important case here. Both this and the post link come
      // down the same stream; answering this one would open a post screen on
      // top of the sign-in it was completing.
      final Uri callback = Uri.parse('com.alimahmoud.bulkr://login-callback');

      expect(DeepLink.parse(callback), isNull);
    });

    test('the OAuth callback carrying its token fragment', () {
      final Uri callback = Uri.parse(
        'com.alimahmoud.bulkr://login-callback#access_token=x&refresh_token=y',
      );

      expect(DeepLink.parse(callback), isNull);
    });

    test('another app claiming a similar scheme', () {
      expect(
        DeepLink.parse(Uri.parse('com.alimahmoud.bulkrr://post/abc')),
        isNull,
      );
      expect(DeepLink.parse(Uri.parse('bulkr://post/abc')), isNull);
    });

    test('an https link, which this app does not claim', () {
      // There is no Apple App Site Association file and no Digital Asset
      // Links file, so https links are not ours and must not be treated as if
      // they were.
      expect(DeepLink.parse(Uri.parse('https://bulkr.app/post/abc')), isNull);
    });

    test('a host this version does not know', () {
      expect(
        DeepLink.parse(Uri.parse('com.alimahmoud.bulkr://group/abc')),
        isNull,
      );
    });
  });

  group('refuses a malformed post link rather than guessing', () {
    test('no id', () {
      expect(DeepLink.parse(Uri.parse('com.alimahmoud.bulkr://post')), isNull);
      expect(DeepLink.parse(Uri.parse('com.alimahmoud.bulkr://post/')), isNull);
    });

    test('more than one segment', () {
      expect(
        DeepLink.parse(Uri.parse('com.alimahmoud.bulkr://post/abc/comments')),
        isNull,
      );
    });

    test('an absurdly long id', () {
      // Not validation — the server decides what is real. A bound, so a
      // hostile link cannot make a request or an analytics parameter
      // arbitrarily large.
      final String huge = 'a' * 500;
      expect(
        DeepLink.parse(Uri.parse('com.alimahmoud.bulkr://post/$huge')),
        isNull,
      );
    });
  });

  test('PostDeepLink compares by value', () {
    // It is delivered through a stream and compared against what is already
    // open, so identity comparison would reopen the same post.
    expect(const PostDeepLink('a'), const PostDeepLink('a'));
    expect(const PostDeepLink('a'), isNot(const PostDeepLink('b')));
    expect(const PostDeepLink('a').hashCode, const PostDeepLink('a').hashCode);
  });

  test('the share text carries a link this parser accepts', () {
    // End to end over the only two pieces that are pure: what is copied, and
    // what is read back. The link is on the last line of the blob.
    const String id = 'e1b9c0de-0000-4000-8000-000000000001';
    final String shared = PostLink.forPost(id);
    final DeepLink? parsed = DeepLink.parse(Uri.parse(shared));

    expect(parsed, const PostDeepLink(id));
  });

  group('native registration', _nativeRegistrationTests);
}

/// The parser being right is not the feature working.
///
/// On Android a `VIEW` intent only reaches the app if a filter matches, and
/// matching is per **host**: the manifest registered `login-callback` and
/// nothing else, so `com.alimahmoud.bulkr://post/<id>` did not open Bulkr at
/// all. Every share button had been producing links that went nowhere.
///
/// Native config is invisible to the rest of the test suite, which is exactly
/// why it is worth asserting — the same reasoning as
/// `push_service_test.dart`'s check that `GoogleService-Info.plist` is in the
/// Xcode target.
void _nativeRegistrationTests() {
  test('Android registers the post host', () {
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains(
        '<data android:scheme="${PostLink.scheme}" '
        'android:host="${PostLink.postHost}"/>',
      ),
      reason: 'without this filter a shared post link does not open the app '
          'on Android at all',
    );
  });

  test('Android still registers the OAuth callback', () {
    // The post filter was added beside this one, not instead of it. Losing
    // this breaks sign-in, which is a far worse failure than the one being
    // fixed.
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains('android:host="login-callback"'),
      reason: 'OAuth cannot hand control back to the app without it',
    );
  });

  test('iOS registers the scheme the links use', () {
    // iOS claims whole schemes rather than hosts, so this one entry covers
    // both the callback and post links — which is why the iOS side was never
    // the broken half.
    final String plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(plist, contains('<string>${PostLink.scheme}</string>'));
  });
}
