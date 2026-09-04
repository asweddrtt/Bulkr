import 'package:equatable/equatable.dart';

import 'meal.dart';
import 'post_label.dart';

/// A `public.posts` row plus this user's relationship to it.
///
/// Same shape of object as [Meal], and for the same reason: the flags a feed
/// card needs — did I like this, did I save it, is it mine — do not live on the
/// post row. They come from `post_likes` and `post_saves`, and the repository
/// resolves them once so a card never has to join anything in its head.
///
/// Those two tables are a later slice, so [isLiked] and [isSaved] are false for
/// now. The field is here rather than added later because the card is built
/// around it: the button has an on state from the first commit, it just has
/// nothing turning it on yet.
class Post extends Equatable {
  const Post({
    required this.id,
    required this.authorId,
    required this.label,
    this.content,
    this.imageUrls = const [],
    this.attachedMeal,
    this.likeCount = 0,
    this.commentCount = 0,
    this.saveCount = 0,
    required this.createdAt,
    this.hotScore = 0,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.isMine = false,
    this.isLiked = false,
    this.isSaved = false,
    this.isHidden = false,
  });

  final String id;
  final String authorId;

  /// Which of the six kinds of post this is. Never null — the column is
  /// `not null default 'tip'`, and [PostLabel.parse] falls back to the same
  /// value for anything it does not recognise.
  final PostLabel label;

  /// `posts.content` — what they wrote. Nullable, because a progress post can
  /// be two photos and nothing else.
  final String? content;

  /// Public URLs from the `post-images` bucket, in the order the author chose.
  ///
  /// Read from `post_images`, not from the legacy `posts.image_url` column.
  /// That column still holds the single image of any post written before the
  /// feed existed; the migration copied those into `post_images` at position 0,
  /// so this list is the whole truth either way.
  final List<String> imageUrls;

  /// The meal hanging off this post, when it was read with the meal joined.
  ///
  /// Null means either "no meal attached" or "not asked for" — the feed asks
  /// for it, so in the feed null means no meal. It carries only the meal's own
  /// columns: the reader's relationship to it (saved, logged today) is resolved
  /// against their own library, not against the post.
  final Meal? attachedMeal;

  /// The denormalised counters off the post row.
  ///
  /// Stored on the row rather than counted per card, the same way `meals`
  /// carries `total_calories`. Correct only insofar as the triggers that own
  /// them are, which is why the triggers ship in the same slice as the tables
  /// they count.
  final int likeCount;
  final int commentCount;
  final int saveCount;

  final DateTime createdAt;

  /// `posts.hot_score` — what Discover sorts on, and what it pages by.
  ///
  /// Carried on the model because it is half of the Discover cursor: paging
  /// asks for what comes after *this* row, which means the client has to know
  /// the last row's score. It is never displayed.
  final double hotScore;

  /// The author, when the post was read with `users` joined. The feed always
  /// joins them — a card with no name on it is not a social post.
  final String? authorUsername;
  final String? authorDisplayName;
  final String? authorAvatarUrl;

  /// This session wrote it. Decides whether the overflow menu offers delete or
  /// report, since reporting your own post is not a thing anyone wants to do.
  final bool isMine;

  final bool isLiked;
  final bool isSaved;

  /// Pulled from the feed, by its author or by reports.
  ///
  /// Only ever true on a post the reader owns — the RLS policy hides everyone
  /// else's — so it exists to put a "this is hidden" marker on the author's own
  /// copy rather than letting it vanish without explanation.
  final bool isHidden;

  /// What to print above the post. Falls through display name to handle, the
  /// same order [UserProfile.preferredName] uses, so one person reads the same
  /// everywhere in the app.
  String get authorName {
    final String? display = authorDisplayName?.trim();
    if (display != null && display.isNotEmpty) return display;

    final String? handle = authorUsername?.trim();
    if (handle != null && handle.isNotEmpty) return handle;

    // A post whose author row could not be read. Rare, and not worth an empty
    // gap where a name should be.
    return 'someone';
  }

  bool get hasImages => imageUrls.isNotEmpty;

  /// Whether the reader can put this post's meal in their own library.
  ///
  /// Their own meal is already there, which is why this is not just
  /// "attachedMeal != null".
  bool get canSaveMeal => attachedMeal != null && !attachedMeal!.isMine;

  /// Total engagement, for the "N reactions" line and nothing else. Not the
  /// ranking — that is [hotScore], and it weights these three differently and
  /// decays them, which cannot be done client-side.
  int get engagementCount => likeCount + commentCount + saveCount;

  Post copyWith({
    PostLabel? label,
    String? content,
    List<String>? imageUrls,
    Meal? attachedMeal,
    bool clearAttachedMeal = false,
    int? likeCount,
    int? commentCount,
    int? saveCount,
    double? hotScore,
    bool? isLiked,
    bool? isSaved,
    bool? isHidden,
  }) {
    return Post(
      id: id,
      authorId: authorId,
      label: label ?? this.label,
      content: content ?? this.content,
      imageUrls: imageUrls ?? this.imageUrls,
      attachedMeal:
          clearAttachedMeal ? null : (attachedMeal ?? this.attachedMeal),
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      saveCount: saveCount ?? this.saveCount,
      createdAt: createdAt,
      hotScore: hotScore ?? this.hotScore,
      authorUsername: authorUsername,
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      isMine: isMine,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  /// Reads a `posts` row, optionally with `users` and `meals` embedded.
  ///
  /// Forgiving in the same way the rest of the app's parsing is: a post missing
  /// its author join, its images or its meal still renders. The feed is the one
  /// screen where a single malformed row must not be able to take the whole
  /// list down, because the user did not ask for that row and cannot avoid it.
  factory Post.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
    bool isLiked = false,
    bool isSaved = false,
  }) {
    final String authorId = '${row['user_id']}';

    return Post(
      id: '${row['id']}',
      authorId: authorId,
      label: PostLabel.parse(row['label']),
      content: row['content'] as String?,
      imageUrls: _imageUrls(row),
      attachedMeal: _attachedMeal(row, currentUserId: currentUserId),
      likeCount: _parseInt(row['likes_count']),
      commentCount: _parseInt(row['comments_count']),
      saveCount: _parseInt(row['saves_count']),
      createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      hotScore: _parseDouble(row['hot_score']),
      authorUsername: _author(row)?['username'] as String?,
      authorDisplayName: _author(row)?['display_name'] as String?,
      authorAvatarUrl: _author(row)?['avatar_url'] as String?,
      isMine: currentUserId != null && authorId == currentUserId,
      isLiked: isLiked,
      isSaved: isSaved,
      isHidden: row['is_hidden'] == true,
    );
  }

  /// The embedded `users` row, however PostgREST decided to shape it.
  ///
  /// A to-one embed comes back as an object, but the same query written against
  /// a relationship PostgREST reads as to-many returns a single-element list.
  /// Both are handled rather than depending on which one today's schema cache
  /// produces — the same defensive read [Meal.fromRow] does.
  static Map<String, dynamic>? _author(Map<String, dynamic> row) {
    final Object? author = row['users'];
    if (author is Map<String, dynamic>) return author;
    if (author is List && author.isNotEmpty) {
      final Object? first = author.first;
      if (first is Map<String, dynamic>) return first;
    }
    return null;
  }

  /// Image URLs from the embedded `post_images` rows, ordered by `position`.
  ///
  /// Sorted here rather than trusted from the query. PostgREST honours an
  /// `order` on an embed, but the ordering of a post's photos is the difference
  /// between a before/after and an after/before, so it is enforced where it
  /// cannot be dropped by a later edit to a query string.
  static List<String> _imageUrls(Map<String, dynamic> row) {
    final Object? images = row['post_images'];
    if (images is! List) return const [];

    final List<Map<String, dynamic>> rows = images
        .whereType<Map<String, dynamic>>()
        .where((image) => '${image['url'] ?? ''}'.isNotEmpty)
        .toList()
      ..sort((a, b) => _parseInt(a['position']).compareTo(_parseInt(b['position'])));

    return rows.map((image) => '${image['url']}').toList(growable: false);
  }

  static Meal? _attachedMeal(
    Map<String, dynamic> row, {
    String? currentUserId,
  }) {
    final Object? meal = row['meals'];
    final Map<String, dynamic>? mealRow = meal is Map<String, dynamic>
        ? meal
        : (meal is List && meal.isNotEmpty && meal.first is Map<String, dynamic>
            ? meal.first as Map<String, dynamic>
            : null);

    if (mealRow == null) return null;

    // A meal row with no id is a join that matched nothing. PostgREST does not
    // normally produce one, but an outer embed against a set-null foreign key
    // is exactly the shape that could, and a Meal with an empty id would be
    // saveable — into nothing.
    if ('${mealRow['id'] ?? ''}'.isEmpty) return null;

    return Meal.fromRow(mealRow, currentUserId: currentUserId);
  }

  static int _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static double _parseDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  List<Object?> get props => [
        id,
        authorId,
        label,
        content,
        imageUrls,
        attachedMeal,
        likeCount,
        commentCount,
        saveCount,
        hotScore,
        authorUsername,
        authorDisplayName,
        authorAvatarUrl,
        isMine,
        isLiked,
        isSaved,
        isHidden,
      ];
}
