import 'package:equatable/equatable.dart';

import 'challenge.dart';
import 'meal.dart';
import 'post_label.dart';

/// A post being written, before it becomes a `posts` row.
///
/// Pure and immutable for the same reason [MealDraft] is: the composer's rules
/// — when Post is allowed, how many photos are left — become arithmetic that
/// can be tested without a widget or a network, and the cubit's only job is to
/// swap one draft for the next.
class PostDraft extends Equatable {
  const PostDraft({
    this.label = PostLabel.tip,
    this.content = '',
    this.imagePaths = const [],
    this.attachedMeal,
    this.groupId,
    this.challenge,
  });

  /// Which of the six kinds of post this is.
  ///
  /// Defaults to [PostLabel.tip] to match the column default, so a post that
  /// somehow reaches the database without the composer having asked lands under
  /// the same label either way.
  final PostLabel label;

  /// What they've written. Trimmed at the edge, on save, not as they type —
  /// trimming mid-typing eats the space before the next word.
  final String content;

  /// Local file paths of the photos picked, in the order they were picked.
  ///
  /// A list rather than a single path because `progress` is a before and an
  /// after, and one field could never hold both. The order is the order they
  /// will be stored at and shown in, which is why reordering is a real
  /// operation rather than a display concern.
  final List<String> imagePaths;

  /// A meal from the author's own library, hung off the post.
  ///
  /// Only ever their own: attaching someone else's meal would credit them for
  /// it. The picker only offers meals where [Meal.isMine] is true, and the
  /// repository re-checks — the UI is not the place that rule can live alone.
  final Meal? attachedMeal;

  /// The group to post into, or null to post to the feed.
  ///
  /// A group post is scoped to that group. The insert policy checks membership
  /// independently, so a draft aimed at a group the user has left fails at the
  /// database rather than posting somewhere unexpected.
  final String? groupId;

  /// The challenge to attach, when the label is `challenge`.
  ///
  /// Written as a second row after the post exists, because a challenge needs
  /// the post's id. Held on the draft so the composer's rules — a challenge
  /// post needs a title and a goal — are testable arithmetic like the rest.
  final ChallengeDraft? challenge;

  bool get isGroupPost => groupId != null;

  bool get hasChallenge => challenge != null;

  /// Whether the challenge attached to this post is complete enough to save.
  ///
  /// True when there is no challenge: a post with nothing attached has nothing
  /// to be invalid about.
  bool get isChallengeValid => challenge?.canSubmit ?? true;

  /// How many photos one post may carry.
  ///
  /// Enough for a before, an after and a detail shot. The ceiling is not about
  /// storage: it is that a card with nine photos is a gallery, and the feed
  /// scrolls past it rather than through it.
  static const int maxImages = 4;

  /// How long a post may be.
  ///
  /// Generous — long enough for a real recipe method or a considered answer to
  /// a question — and bounded so one post cannot be a wall that pushes every
  /// other card off the screen.
  static const int maxContentLength = 2000;

  int get remainingImageSlots => maxImages - imagePaths.length;

  bool get canAddImage => remainingImageSlots > 0;

  bool get hasImages => imagePaths.isNotEmpty;

  bool get hasMeal => attachedMeal != null;

  String get trimmedContent => content.trim();

  /// Whether there is anything here worth posting.
  ///
  /// A post needs *something* — words, a photo, or a meal — and any one of the
  /// three is enough. A progress post can be two photos and no caption; a meal
  /// post can be the meal and nothing else. What it cannot be is empty.
  bool get isPostable =>
      trimmedContent.isNotEmpty || hasImages || hasMeal;

  /// Whether the content is over the limit.
  ///
  /// Measured on the trimmed text, since trailing whitespace is not something
  /// to refuse a post over. Separate from [isPostable] because the two want
  /// different things said about them: one disables the button quietly, the
  /// other has to explain itself.
  bool get isTooLong => trimmedContent.length > maxContentLength;

  bool get canSubmit => isPostable && !isTooLong && isChallengeValid;

  /// How much room is left, for the counter under the field.
  ///
  /// Goes negative once over, which is what lets the counter turn red and show
  /// how far over rather than sitting at zero.
  int get remainingCharacters => maxContentLength - trimmedContent.length;

  /// Whether the counter is worth showing at all.
  ///
  /// Hidden until the post is long enough for the limit to be plausibly
  /// relevant. A character counter on a two-word tip is noise.
  bool get showsCharacterCount =>
      trimmedContent.length > maxContentLength - 200;

  PostDraft copyWith({
    PostLabel? label,
    String? content,
    List<String>? imagePaths,
    Meal? attachedMeal,
    bool clearAttachedMeal = false,
    String? groupId,
    bool clearGroup = false,
    ChallengeDraft? challenge,
    bool clearChallenge = false,
  }) {
    return PostDraft(
      label: label ?? this.label,
      content: content ?? this.content,
      imagePaths: imagePaths ?? this.imagePaths,
      attachedMeal:
          clearAttachedMeal ? null : (attachedMeal ?? this.attachedMeal),
      groupId: clearGroup ? null : (groupId ?? this.groupId),
      challenge: clearChallenge ? null : (challenge ?? this.challenge),
    );
  }

  /// Adds a photo, ignoring one that would exceed [maxImages].
  ///
  /// Silently rather than throwing: the picker is already supposed to be
  /// disabled at the ceiling, so reaching here means two taps raced, and the
  /// right answer to that is nothing happening.
  PostDraft withImage(String path) {
    if (!canAddImage) return this;
    return copyWith(imagePaths: [...imagePaths, path]);
  }

  PostDraft withoutImage(String path) {
    return copyWith(
      imagePaths: imagePaths.where((existing) => existing != path).toList(),
    );
  }

  /// The `posts` column values for this draft.
  ///
  /// Images are not here — they are rows in `post_images`, written after the
  /// post has an id. Neither is `image_url`: the legacy single-image column is
  /// left null on every new post, so there is exactly one place a post's
  /// photos live.
  Map<String, dynamic> toRowValues({required String authorId}) {
    return {
      'user_id': authorId,
      'label': label.column,
      // Empty text stores as null rather than '', so "has no caption" is one
      // value in the database instead of two.
      'content': trimmedContent.isEmpty ? null : trimmedContent,
      'attached_meal_id': attachedMeal?.id,
      'group_id': groupId,
    };
  }

  @override
  List<Object?> get props =>
      [label, content, imagePaths, attachedMeal, groupId, challenge];
}
