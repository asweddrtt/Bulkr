import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/meal.dart';
import '../models/post.dart';
import '../models/post_comment.dart';
import '../models/post_draft.dart';
import '../models/post_label.dart';
import 'feed_cursor.dart';

/// A photo waiting to go up with a post.
///
/// The bytes are read by the screen that picked the file — the only part of
/// posting that needs the filesystem — and carried here so the repository can
/// stay testable against a fake client.
@immutable
class PostImageUpload {
  const PostImageUpload({
    required this.path,
    required this.bytes,
    this.extension = 'jpg',
  });

  /// Local path the user picked it from. Identity only: it is how the draft
  /// refers to this image, and it is never stored.
  final String path;

  final Uint8List bytes;
  final String extension;
}

/// Reads and writes the feed.
///
/// Two feeds over one table. **For You** is people the user chose — the
/// accounts they follow and the groups they're in — ordered by recency, because
/// a followed author's post is interesting for being theirs and new rather than
/// for being popular. **Discover** is everything public, ordered by
/// `posts.hot_score`, which is engagement decayed by age.
///
/// Both page by keyset rather than OFFSET. See [FeedCursor] for why that is not
/// a micro-optimisation.
class PostRepository {
  PostRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Storage bucket holding post photos. Public-read, because a post has to
  /// render for everyone who can see it.
  ///
  /// Separate from `meal-images` on purpose: the two have different lifetimes,
  /// and deleting a post must not be able to strip the photo off a meal that is
  /// still sitting in someone's library.
  static const String imageBucket = 'post-images';

  /// How many posts a page holds.
  ///
  /// Small, because every row drags an author, its images and possibly a whole
  /// meal along with it, and because nobody reads twenty posts before
  /// scrolling.
  static const int pageSize = 15;

  /// How many comments one post's thread will load.
  ///
  /// The whole conversation, not a page of it — a thread is read top to bottom
  /// and half of one is a reply with no parent. High enough that hitting it
  /// means something unusual is going on under that post.
  static const int commentLimit = 300;

  /// Columns of `posts`, with everything a card needs to render already joined.
  ///
  /// Every foreign key is named explicitly, and it is now load-bearing rather
  /// than defensive. `post_likes` and `post_saves` hold foreign keys to both
  /// `posts` and `users` and nothing else of their own, which is exactly what
  /// PostgREST reads as a junction table — so a bare `users(...)` here is
  /// ambiguous between "the author" and "everyone who liked it" and answers
  /// PGRST201. The same goes for the nested meal: `meals` points at `users`
  /// twice now, through `creator_id` and `source_creator_id`.
  ///
  /// The attached meal is embedded with its own author nested inside it, so a
  /// meal saved off a post keeps its credit. It comes back null when the meal
  /// is neither public nor the reader's own — the meals RLS policy sees to
  /// that — which is correct: a post can mention a meal the reader is not
  /// allowed to look at, and the card simply shows no attachment.
  static const String _postColumns = '*, '
      'users!posts_user_id_fkey(username, display_name, avatar_url), '
      'post_images(url, position), '
      'meals!posts_attached_meal_id_fkey(*, '
      'users!meals_creator_id_fkey(username), '
      'source_author:users!meals_source_creator_id_fkey(username))';

  String? get _userId => _client.auth.currentUser?.id;

  /// Everything public, hottest first.
  ///
  /// Ordered by the stored `hot_score` column, not by a score computed here.
  /// Computing it at query time would mean no index could serve the sort, and
  /// every pull would scan every public post that has ever existed.
  Future<FeedPage> fetchDiscover({
    PostLabel? label,
    FeedCursor? cursor,
  }) async {
    // Reading the feed signed out is not a state the app can reach — the router
    // guards it — but the id decides `isMine`, and a null one would quietly
    // render every post as somebody else's.
    final String? userId = _userId;

    PostgrestFilterBuilder<List<Map<String, dynamic>>> query =
        _client.from('posts').select(_postColumns).eq('is_hidden', false);

    if (label != null) {
      query = query.eq('label', label.column);
    }

    if (cursor != null) {
      query = query.or(_keysetFilter(
        column: 'hot_score',
        value: '${cursor.sortValue}',
        id: cursor.id,
      ));
    }

    final List<Map<String, dynamic>> rows = await query
        .order('hot_score', ascending: false)
        .order('id', ascending: false)
        .limit(pageSize);

    return await _page(rows,
        userId: userId, cursorBuilder: FeedCursor.byHotScore);
  }

  /// Posts from the people the user follows, newest first.
  ///
  /// Today "the people the user follows" is only themselves: there is no
  /// `follows` table yet, so [_followedAuthorIds] returns just the signed-in
  /// id. That is deliberately not a stub that returns everything — a For You
  /// tab that quietly shows the whole site is indistinguishable from Discover,
  /// and the empty state is the honest answer until following exists.
  ///
  /// Ordered by recency rather than by score. Someone the user chose to follow
  /// does not have to earn a place in their feed twice.
  Future<FeedPage> fetchForYou({
    PostLabel? label,
    FeedCursor? cursor,
  }) async {
    final String? userId = _userId;
    if (userId == null) return const FeedPage.empty();

    final List<String> authorIds = await _followedAuthorIds(userId);
    if (authorIds.isEmpty) return const FeedPage.empty();

    PostgrestFilterBuilder<List<Map<String, dynamic>>> query = _client
        .from('posts')
        .select(_postColumns)
        .eq('is_hidden', false)
        .inFilter('user_id', authorIds);

    if (label != null) {
      query = query.eq('label', label.column);
    }

    if (cursor != null) {
      // Quoted, unlike the hot score: an ISO timestamp contains colons and a
      // `+` in some offsets, and PostgREST treats those as filter syntax
      // unless the value is quoted.
      query = query.or(_keysetFilter(
        column: 'created_at',
        value: '"${cursor.asTimestamp}"',
        id: cursor.id,
      ));
    }

    final List<Map<String, dynamic>> rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(pageSize);

    return await _page(rows,
        userId: userId, cursorBuilder: FeedCursor.byRecency);
  }

  /// Whose posts belong in this user's For You.
  ///
  /// The signed-in user for now, so the tab has something true to show and the
  /// composer can be tested end to end. Slice 3 replaces the body with a read
  /// of `follows` plus `group_members`; the signature does not change, and
  /// neither does anything above it.
  Future<List<String>> _followedAuthorIds(String userId) async {
    return [userId];
  }

  /// A single post, for a deep link or a share target.
  ///
  /// Returns null rather than throwing when the row is gone or hidden. A link
  /// to a deleted post is a normal thing to be sent, and it wants "this post is
  /// no longer here", not an error screen.
  Future<Post?> fetchPost(String postId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('posts')
        .select(_postColumns)
        .eq('id', postId)
        .limit(1);

    if (rows.isEmpty) return null;
    return Post.fromRow(rows.first, currentUserId: _userId);
  }

  /// Writes [draft] as a new post owned by the signed-in user.
  ///
  /// Order matters, and it is the same order [MealRepository.createMeal] uses
  /// and for the same reason: the photos go up first, because a failed upload
  /// should not leave a postless row behind, and the image rows land last
  /// because they need the post's id.
  ///
  /// The image rows are the only part allowed to fail without taking the post
  /// with it. A caption and an attached meal that saved correctly are worth
  /// keeping even if the pictures did not make it — the alternative is throwing
  /// away something the user typed because a storage write was refused.
  Future<Post> createPost({
    required PostDraft draft,
    List<PostImageUpload> images = const [],
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot create a post without a signed-in user');
    }

    if (!draft.isPostable) {
      throw StateError('Cannot create an empty post');
    }

    // Re-checked here rather than trusted from the composer. Attaching someone
    // else's meal would put this user's name over their work, and the UI is not
    // the only way into this method.
    final Meal? meal = draft.attachedMeal;
    if (meal != null && meal.creatorId != userId) {
      throw StateError(
        'Cannot attach a meal owned by someone else — post your own copy of it',
      );
    }

    // A private meal on a public post is an attachment nobody can open. The
    // meals policy shows a meal to its creator or to everyone, so the author
    // would see their own card and every other reader would see the post with
    // no meal on it at all — which reads as a bug rather than as a permission.
    //
    // Attaching your own meal to a post is an unambiguous decision to share
    // the recipe, so the flag follows the intent. Done before the insert so
    // the row read back below already carries the published meal, and scoped
    // to `creator_id` so it can only ever publish something this user wrote.
    //
    // The composer says so in as many words before this point is reached; this
    // is the invariant, not the notice.
    if (meal != null && !meal.isPublic) {
      await _client
          .from('meals')
          .update({'is_public': true})
          .eq('id', meal.id)
          .eq('creator_id', userId);
    }

    final List<String> urls = await _uploadImages(
      userId: userId,
      images: images.take(PostDraft.maxImages).toList(),
    );

    final Map<String, dynamic> row = await _client
        .from('posts')
        .insert(draft.toRowValues(authorId: userId))
        .select(_postColumns)
        .single();

    final Post post = Post.fromRow(row, currentUserId: userId);

    if (urls.isEmpty) return post;

    try {
      await _client.from('post_images').insert([
        for (int i = 0; i < urls.length; i++)
          {'post_id': post.id, 'url': urls[i], 'position': i},
      ]);
    } catch (error) {
      debugPrint('Bulkr: post saved but its images failed — $error');
      return post;
    }

    // The insert above is not reflected in the row already read back, so the
    // URLs are carried over by hand rather than by a second round trip.
    return post.copyWith(imageUrls: urls);
  }

  /// Removes a post the user wrote.
  ///
  /// `post_images` rows cascade with it. The files in storage do not — they are
  /// left behind on purpose, because a delete that half-fails is better than one
  /// that removes the pictures and then cannot remove the post, leaving a card
  /// with broken images on everyone's feed.
  Future<void> deletePost(String postId) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot delete a post without a signed-in user');
    }

    await _client.from('posts').delete().eq('id', postId).eq('user_id', userId);
  }

  /// Takes a post out of the feed without deleting it.
  ///
  /// The author's own copy stays visible to them — the RLS policy makes an
  /// exception for `auth.uid() = user_id` — so this reads as "unpublished"
  /// rather than as data loss.
  Future<void> setHidden({required String postId, required bool isHidden}) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot hide a post without a signed-in user');
    }

    await _client
        .from('posts')
        .update({'is_hidden': isHidden})
        .eq('id', postId)
        .eq('user_id', userId);
  }

  /// Likes a post, or takes the like back.
  ///
  /// An insert and a delete, with nothing to reconcile: `post_likes` is keyed
  /// on `(post_id, user_id)`, so liking twice is refused by the primary key
  /// rather than counted twice, and unliking something never liked deletes
  /// nothing. The counter on the post row is the trigger's job.
  ///
  /// Returns nothing. The caller already moved its own UI — a heart that waits
  /// on a round trip feels broken — and the authority on the count is the next
  /// read, not an answer computed here from a number that may already be stale.
  Future<void> setLiked({required String postId, required bool isLiked}) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot like a post without a signed-in user');
    }

    if (isLiked) {
      // Upsert rather than insert: two taps racing would otherwise make the
      // second one a 23505 the user has to see, for the outcome they wanted.
      await _client.from('post_likes').upsert(
            {'post_id': postId, 'user_id': userId},
            onConflict: 'post_id,user_id',
            ignoreDuplicates: true,
          );
    } else {
      await _client
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    }
  }

  /// Bookmarks a post, or removes the bookmark.
  ///
  /// Saving a *post* is not saving the meal on it. This is a reading list —
  /// come back to this — and it leaves the user's meal library untouched.
  /// Taking the recipe is [MealRepository.copyFromPost], a different action
  /// with a different button.
  Future<void> setSaved({required String postId, required bool isSaved}) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot save a post without a signed-in user');
    }

    if (isSaved) {
      await _client.from('post_saves').upsert(
            {'post_id': postId, 'user_id': userId},
            onConflict: 'post_id,user_id',
            ignoreDuplicates: true,
          );
    } else {
      await _client
          .from('post_saves')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', userId);
    }
  }

  /// The posts this user has bookmarked, most recently saved first.
  ///
  /// Ordered by when they saved it rather than when it was written, which is
  /// how a reading list is read.
  Future<List<Post>> fetchSavedPosts() async {
    final String? userId = _userId;
    if (userId == null) return const [];

    final List<Map<String, dynamic>> rows = await _client
        .from('post_saves')
        .select('post_id, created_at, posts($_postColumns)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(200);

    final List<Post> posts = [];
    for (final Map<String, dynamic> row in rows) {
      final Object? embedded = row['posts'];
      final Map<String, dynamic>? postRow = embedded is Map<String, dynamic>
          ? embedded
          : (embedded is List &&
                  embedded.isNotEmpty &&
                  embedded.first is Map<String, dynamic>
              ? embedded.first as Map<String, dynamic>
              : null);

      // A save whose post has since been deleted or hidden. Skipped rather
      // than rendered as a blank card.
      if (postRow == null) continue;

      posts.add(Post.fromRow(postRow, currentUserId: userId, isSaved: true));
    }

    return _withMyEngagement(posts, userId: userId);
  }

  /// A post's comments, oldest first, arranged into threads.
  ///
  /// The whole conversation in one read rather than a page of it. A thread is
  /// read top to bottom and a partial one makes no sense — a reply without its
  /// parent is a non-sequitur — and the cap is high enough that reaching it
  /// means something unusual is happening on that post.
  Future<List<PostComment>> fetchComments(
    String postId, {
    String? postAuthorId,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('post_comments')
        .select(
          '*, users!post_comments_user_id_fkey(username, display_name, avatar_url)',
        )
        .eq('post_id', postId)
        .order('created_at', ascending: true)
        .limit(commentLimit);

    final List<PostComment> flat = rows
        .map((row) => PostComment.fromRow(
              row,
              currentUserId: _userId,
              postAuthorId: postAuthorId,
            ))
        .toList(growable: false);

    return PostComment.thread(flat);
  }

  /// Writes a comment, or a reply to one.
  ///
  /// The trigger on `post_comments` refuses a reply to a reply, so passing a
  /// [parentId] that is itself a reply fails at the database rather than
  /// quietly creating a third level the UI cannot draw.
  Future<PostComment> addComment({
    required String postId,
    required String content,
    String? parentId,
    String? postAuthorId,
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot comment without a signed-in user');
    }

    final String trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw StateError('Cannot post an empty comment');
    }

    final Map<String, dynamic> row = await _client
        .from('post_comments')
        .insert({
          'post_id': postId,
          'user_id': userId,
          'parent_comment_id': parentId,
          'content': trimmed,
        })
        .select(
          '*, users!post_comments_user_id_fkey(username, display_name, avatar_url)',
        )
        .single();

    return PostComment.fromRow(
      row,
      currentUserId: userId,
      postAuthorId: postAuthorId,
    );
  }

  /// Removes a comment.
  ///
  /// No ownership filter on the query, unlike [deletePost]. Two people are
  /// allowed to delete a comment — whoever wrote it and whoever owns the post
  /// it is on — and expressing that here would mean duplicating the policy in
  /// a place that can drift from it. The policy is the authority; a delete the
  /// user is not entitled to removes nothing.
  Future<void> deleteComment(String commentId) async {
    if (_userId == null) {
      throw StateError('Cannot delete a comment without a signed-in user');
    }

    await _client.from('post_comments').delete().eq('id', commentId);
  }

  /// Turns rows into a page, and works out where the next one starts.
  Future<FeedPage> _page(
    List<Map<String, dynamic>> rows, {
    required String? userId,
    required FeedCursor Function(Post) cursorBuilder,
  }) async {
    final List<Post> posts = rows
        .map((row) => Post.fromRow(row, currentUserId: userId))
        .toList(growable: false);

    if (posts.isEmpty) return const FeedPage.empty();

    final List<Post> marked = await _withMyEngagement(posts, userId: userId);

    return FeedPage(
      posts: marked,
      // Built from the unmarked list on purpose: the cursor is about position
      // in the ordering, and `_withMyEngagement` preserves order but has no
      // business being trusted with it.
      nextCursor: cursorBuilder(posts.last),
      hasMore: rows.length >= pageSize,
    );
  }

  /// Marks what this user has already done to each of [posts]: liked it, saved
  /// it, and taken a copy of the meal on it.
  ///
  /// Three queries for the whole page rather than one per card, and they run
  /// together. The obvious alternative — asking PostgREST to embed
  /// `post_likes` filtered to this user — turns into an inner join that drops
  /// every post the user has *not* liked, which is most of them.
  ///
  /// Non-fatal, all of it. A feed that renders with every heart empty is wrong
  /// in a way the next refresh fixes; a feed that fails to render because a
  /// lookup of who-liked-what timed out is wrong in a way the reader can do
  /// nothing about.
  Future<List<Post>> _withMyEngagement(
    List<Post> posts, {
    required String? userId,
  }) async {
    if (userId == null || posts.isEmpty) return posts;

    final List<String> ids = posts.map((post) => post.id).toList();

    // Only posts carrying someone else's meal can be asked about — the user's
    // own needs no lookup, and a page with no attachments should not spend a
    // round trip discovering that.
    final List<String> attachedMealIds = [
      for (final Post post in posts)
        if (post.attachedMeal != null && !post.attachedMeal!.isMine)
          post.attachedMeal!.id,
    ];

    try {
      final results = await Future.wait([
        _client
            .from('post_likes')
            .select('post_id')
            .eq('user_id', userId)
            .inFilter('post_id', ids),
        _client
            .from('post_saves')
            .select('post_id')
            .eq('user_id', userId)
            .inFilter('post_id', ids),
        // Matched on `source_meal_id`, which is how a copy remembers what it
        // was copied from. Empty in, empty out — no query worth making.
        if (attachedMealIds.isEmpty)
          Future<List<Map<String, dynamic>>>.value(const [])
        else
          _client
              .from('meals')
              .select('source_meal_id')
              .eq('creator_id', userId)
              .inFilter('source_meal_id', attachedMealIds),
      ]);

      final Set<String> liked = {
        for (final Map<String, dynamic> row in results[0]) '${row['post_id']}',
      };
      final Set<String> saved = {
        for (final Map<String, dynamic> row in results[1]) '${row['post_id']}',
      };
      final Set<String> copiedMeals = {
        for (final Map<String, dynamic> row in results[2])
          '${row['source_meal_id']}',
      };

      return posts
          .map((post) => post.copyWith(
                isLiked: liked.contains(post.id),
                isSaved: saved.contains(post.id),
                attachedMealSaved: post.attachedMeal != null &&
                    copiedMeals.contains(post.attachedMeal!.id),
              ))
          .toList(growable: false);
    } catch (error) {
      debugPrint('Bulkr: could not resolve this user\'s engagement — $error');
      return posts;
    }
  }

  /// The PostgREST spelling of `(column, id) < (value, id)`.
  ///
  /// There is no tuple comparison in the query language, so the pair is
  /// expanded into the two cases it means: strictly past the sort value, or
  /// level with it and past the id.
  ///
  /// Both halves are needed. Without the second, every row tied on the sort
  /// value after the cursor's is skipped — and ties are not an edge case here,
  /// since two posts with no engagement and the same age have the same score by
  /// construction.
  static String _keysetFilter({
    required String column,
    required String value,
    required String id,
  }) {
    return '$column.lt.$value,and($column.eq.$value,id.lt.$id)';
  }

  /// Uploads photos and returns their public URLs, in the order given.
  ///
  /// Sequential rather than concurrent. The order is the post's order — a
  /// before and an after are not interchangeable — and while a `Future.wait`
  /// would preserve the result order too, one failure mid-flight would leave an
  /// unknown number of orphaned files. Doing them in turn means a failure stops
  /// at a known point.
  Future<List<String>> _uploadImages({
    required String userId,
    required List<PostImageUpload> images,
  }) async {
    if (images.isEmpty) return const [];

    final List<String> urls = [];
    // One timestamp for the whole post, indexed per photo, so a post's files
    // sort together in the bucket and two photos picked in the same
    // microsecond cannot collide on a name.
    final int stamp = DateTime.now().toUtc().microsecondsSinceEpoch;

    for (int i = 0; i < images.length; i++) {
      final PostImageUpload image = images[i];
      final String path = '$userId/$stamp-$i.${image.extension}';

      await _client.storage.from(imageBucket).uploadBinary(
            path,
            image.bytes,
            fileOptions: FileOptions(
              contentType: _contentTypeFor(image.extension),
              upsert: false,
            ),
          );

      urls.add(_client.storage.from(imageBucket).getPublicUrl(path));
    }

    return urls;
  }

  static String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }
}
