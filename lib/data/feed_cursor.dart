import 'package:equatable/equatable.dart';

import '../models/post.dart';

/// Where a feed page left off.
///
/// The feed pages by keyset, not by OFFSET, and this is the key. It names one
/// exact row — its sort value and its id — and the next page asks for what
/// sorts after it.
///
/// ## Why not `.range(from, to)`
///
/// A feed takes inserts at the top while someone is reading it. Under OFFSET,
/// every insert above the cursor shifts the whole window down: page 2 re-serves
/// a row the reader already saw on page 1, and skips one of page 2's own to
/// make room. The duplicate is the part users notice, and the skipped post is
/// the part that matters — it is simply never shown to them.
///
/// Keyset asks a question no insert can change the answer to: "what comes after
/// this row". A post added above the cursor is not below it, so it is not in
/// the answer, and the reader meets it on the next refresh where it belongs.
///
/// ## Why the id is part of it
///
/// Neither sort key is unique. Two posts can share a `hot_score` — a brand-new
/// pair with no engagement at all will — and `created_at` collides whenever two
/// posts land in the same microsecond. A cursor on the sort key alone would
/// either drop every tied row after the first or serve them forever, depending
/// on which way the comparison leaned. Pairing it with the primary key makes
/// the ordering total, so `(score, id)` is a position and not just a value.
class FeedCursor extends Equatable {
  const FeedCursor({required this.sortValue, required this.id});

  /// The last row's value in whatever the feed is ordered by: `hot_score` for
  /// Discover, `created_at` (as microseconds since the epoch, UTC) for For You.
  ///
  /// One field for both rather than a subclass per feed, because the comparison
  /// is identical — descending, tie-broken by id — and only the column name
  /// differs. That name belongs to the query, not to the cursor.
  final double sortValue;

  /// The last row's primary key, breaking ties on [sortValue].
  final String id;

  /// A cursor pointing at [post], for ordering by hot score.
  factory FeedCursor.byHotScore(Post post) =>
      FeedCursor(sortValue: post.hotScore, id: post.id);

  /// A cursor pointing at [post], for ordering by recency.
  ///
  /// Microseconds because that is the resolution `timestamptz` keeps, so
  /// anything coarser could put two distinct posts at the same instant and lean
  /// on the id tiebreak more than it has to.
  factory FeedCursor.byRecency(Post post) => FeedCursor(
        sortValue: post.createdAt.toUtc().microsecondsSinceEpoch.toDouble(),
        id: post.id,
      );

  /// [sortValue] rendered for a PostgREST filter on a `timestamptz` column.
  String get asTimestamp => DateTime.fromMicrosecondsSinceEpoch(
        sortValue.round(),
        isUtc: true,
      ).toIso8601String();

  @override
  List<Object?> get props => [sortValue, id];
}

/// One page of a feed, and where the next one starts.
///
/// The cursor comes back with the rows rather than being worked out by the
/// caller, because only the query knows which column it ordered by — and a
/// cursor built against the wrong column silently pages through the feed in an
/// order nothing sorted by.
class FeedPage extends Equatable {
  const FeedPage({
    required this.posts,
    this.nextCursor,
    this.hasMore = false,
  });

  const FeedPage.empty()
      : posts = const [],
        nextCursor = null,
        hasMore = false;

  final List<Post> posts;

  /// Where to resume. Null when there is nothing after this page.
  final FeedCursor? nextCursor;

  /// Whether another page is worth asking for.
  ///
  /// Derived from "the page came back full", which is the usual one-off: a feed
  /// whose last page happens to be exactly the page size reports more, and the
  /// next request returns nothing. That costs one wasted round trip at the very
  /// end of an infinite scroll, and the alternative — fetching one extra row
  /// every page to peek — costs a row on every page instead. The rare waste is
  /// the cheaper of the two.
  final bool hasMore;

  @override
  List<Object?> get props => [posts, nextCursor, hasMore];
}
