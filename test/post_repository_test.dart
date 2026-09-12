import 'dart:convert';

import 'package:bulkr/data/feed_cursor.dart';
import 'package:bulkr/data/post_repository.dart';
import 'package:bulkr/models/post.dart';
import 'package:bulkr/models/post_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The feed's paging, against a real PostgREST request.
///
/// `PostRepository` is the largest file in the app and had no tests at all,
/// despite every repository taking `SupabaseClient? client` specifically so it
/// could have some — the seam was built and never used.
///
/// These drive the real `SupabaseClient` with a stubbed HTTP client, so what
/// is asserted is the URL PostgREST would actually receive: the columns, the
/// filters, the ordering and the keyset cursor. That matters more than it
/// sounds. Keyset paging is the kind of thing that looks right, works on page
/// one, and quietly re-serves or skips rows on page two — which is precisely
/// the bug `FeedCursor` exists to prevent and precisely the bug nothing was
/// checking for.
void main() {
  late List<Uri> requests;

  /// A client that answers every request with [rows] and records the URL.
  SupabaseClient clientReturning(List<Map<String, dynamic>> rows) {
    requests = <Uri>[];

    return SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((http.Request request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode(rows),
          200,
          // Both of these are load-bearing: postgrest dereferences
          // `response.request` and reads `content-range`, and omitting either
          // fails inside the package rather than in the assertion.
          request: request,
          headers: const <String, String>{
            'content-type': 'application/json',
            'content-range': '0-0/*',
          },
        );
      }),
    );
  }

  Map<String, dynamic> row({
    required String id,
    double hotScore = 1,
    String createdAt = '2026-09-01T12:00:00Z',
    String label = 'meal',
  }) =>
      <String, dynamic>{
        'id': id,
        'user_id': 'author-1',
        'group_id': null,
        'label': label,
        'content': 'body',
        'visibility': 'public',
        'is_hidden': false,
        'likes_count': 3,
        'comments_count': 2,
        'saves_count': 1,
        'hot_score': hotScore,
        'created_at': createdAt,
        'users': <String, dynamic>{
          'username': 'someone',
          'display_name': 'Some One',
          'avatar_url': null,
        },
        'post_images': <Map<String, dynamic>>[],
        'groups': null,
        'meals': null,
      };

  group('Discover', () {
    test('asks only for public, ungrouped, unhidden posts', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      await repo.fetchDiscover();

      final String url = Uri.decodeFull(requests.single.toString());
      expect(url, contains('/rest/v1/posts'));
      // A hidden post is hidden from everyone.
      expect(url, contains('is_hidden=eq.false'));
      // Not just RLS: a post written into a group belongs to that group, and
      // a public group's posts being readable is not the same as their
      // belonging on the front page.
      expect(url, contains('group_id=is.null'));
    });

    test('orders by the stored hot score, tie-broken by id', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      await repo.fetchDiscover();

      final String url = Uri.decodeFull(requests.single.toString());
      // Descending on both. The id tiebreak is what makes the ordering total —
      // two brand-new posts share a hot_score of zero, and without it the
      // page boundary is undefined.
      expect(url, contains('order=hot_score.desc'));
      expect(url, contains('id.desc'));
    });

    test('asks for exactly one page', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      await repo.fetchDiscover();

      expect(
        Uri.decodeFull(requests.single.toString()),
        contains('limit=${PostRepository.pageSize}'),
      );
    });

    test('narrows to one label when asked', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      await repo.fetchDiscover(label: PostLabel.progress);

      expect(
        Uri.decodeFull(requests.single.toString()),
        contains('label=eq.${PostLabel.progress.column}'),
      );
    });

    test('does not filter by label when none is given', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      await repo.fetchDiscover();

      expect(Uri.decodeFull(requests.single.toString()),
          isNot(contains('label=eq.')));
    });
  });

  group('the keyset cursor', () {
    test('is absent on the first page', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      await repo.fetchDiscover();

      expect(Uri.decodeFull(requests.single.toString()), isNot(contains('or=')));
    });

    test('asks for what sorts after the last row, not an offset', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      await repo.fetchDiscover(
        cursor: const FeedCursor(sortValue: 12.5, id: 'post-9'),
      );

      final String url = Uri.decodeFull(requests.single.toString());

      // "strictly below the score, OR level with it and below on id". The
      // second half is what stops tied rows being dropped or served forever.
      expect(url, contains('hot_score.lt.12.5'));
      expect(url, contains('and(hot_score.eq.12.5,id.lt.post-9)'));

      // The thing this whole design exists to avoid. An inserted post shifts
      // every OFFSET window down, which re-serves one row and silently skips
      // another.
      expect(url, isNot(contains('offset=')));
    });
  });

  group('what comes back', () {
    test('maps a row into a Post', () async {
      final repo = PostRepository(
        client: clientReturning(<Map<String, dynamic>>[
          row(id: 'post-1', hotScore: 9.5),
        ]),
      );

      final FeedPage page = await repo.fetchDiscover();

      expect(page.posts, hasLength(1));
      final Post post = page.posts.single;
      expect(post.id, 'post-1');
      expect(post.authorId, 'author-1');
      expect(post.authorUsername, 'someone');
      expect(post.likeCount, 3);
      expect(post.hotScore, 9.5);
      expect(post.label, PostLabel.meal);
    });

    test('a short page is the last page', () async {
      // One row against a page size of fifteen: there is nothing after it, and
      // asking again would be a wasted request on every feed that fits on one
      // screen.
      final repo = PostRepository(
        client: clientReturning(<Map<String, dynamic>>[row(id: 'post-1')]),
      );

      final FeedPage page = await repo.fetchDiscover();

      expect(page.hasMore, isFalse);
    });

    test('a short page still carries a cursor, and hasMore is what gates it',
        () async {
      // Worth pinning, because the obvious guess is that the last page has no
      // cursor. It has one: the cursor is a *position* — where this page
      // ended — and is built the same way whether or not anything follows.
      // `hasMore` is the separate question, and `FeedCubit.loadMore` checks it
      // before touching the cursor.
      //
      // A caller that paged on `nextCursor != null` alone would re-request the
      // tail of the feed forever, which is why the two are not collapsed into
      // one nullable field.
      final repo = PostRepository(
        client: clientReturning(<Map<String, dynamic>>[
          row(id: 'post-1', hotScore: 4.5),
        ]),
      );

      final FeedPage page = await repo.fetchDiscover();

      expect(page.nextCursor, isNotNull);
      expect(page.nextCursor?.id, 'post-1');
      expect(page.nextCursor?.sortValue, 4.5);
      expect(page.hasMore, isFalse);
    });

    test('a full page reports more, and points at its last row', () async {
      final repo = PostRepository(
        client: clientReturning(<Map<String, dynamic>>[
          for (int i = 0; i < PostRepository.pageSize; i++)
            row(id: 'post-$i', hotScore: (PostRepository.pageSize - i) * 1.0),
        ]),
      );

      final FeedPage page = await repo.fetchDiscover();

      expect(page.posts, hasLength(PostRepository.pageSize));
      expect(page.hasMore, isTrue);
      // The cursor names the last row of this page, which is where the next
      // one resumes from.
      expect(page.nextCursor?.id, 'post-${PostRepository.pageSize - 1}');
      expect(page.nextCursor?.sortValue, 1.0);
    });

    test('an empty feed is an empty page, not an error', () async {
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      final FeedPage page = await repo.fetchDiscover();

      expect(page.posts, isEmpty);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });
  });

  group('a single post, for a deep link', () {
    test('asks for exactly one row by id', () async {
      final repo = PostRepository(
        client: clientReturning(<Map<String, dynamic>>[row(id: 'post-7')]),
      );

      final Post? post = await repo.fetchPost('post-7');

      expect(post?.id, 'post-7');
      expect(
        Uri.decodeFull(requests.first.toString()),
        contains('id=eq.post-7'),
      );
    });

    test('answers null for a post that is gone or not visible', () async {
      // A link outlives what it points at. Deleted, made private, or written
      // by somebody who has since blocked the reader all arrive as no rows,
      // and all three are the same answer to give.
      final repo = PostRepository(client: clientReturning(<Map<String, dynamic>>[]));

      expect(await repo.fetchPost('missing'), isNull);
    });
  });
}
