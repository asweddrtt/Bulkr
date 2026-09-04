import 'package:flutter/material.dart';

/// What a post is about.
///
/// Mirrors the CHECK constraint on `posts.label`. The database is the authority
/// on which values are legal; this enum is the authority on what they look
/// like, and the two only have to agree on the wire strings in [column].
///
/// Six is a deliberate ceiling. The filter bar shows all of them at once, and a
/// row of chips that scrolls is a row nobody reads to the end of.
enum PostLabel {
  /// Something they cooked. The one label that can carry a meal the reader can
  /// put in their own library.
  meal,

  /// A session, a lift, a programme.
  workout,

  /// Where they've got to. Usually more than one photo — a before and an
  /// after — which is why posts have an image *table* rather than a column.
  progress,

  /// Advice, offered.
  tip,

  /// Advice, wanted.
  question,

  /// A challenge. Today this is only a label: it tags a post about one rather
  /// than driving one, because participants, an end date and a leaderboard are
  /// their own slice of work. Kept in the set from the start so the posts
  /// written under it don't need relabelling when that lands.
  challenge;

  /// The string stored in `posts.label`.
  ///
  /// Equal to [name] for every member, and written out anyway: an enum renamed
  /// in Dart would otherwise silently start writing a value the CHECK
  /// constraint rejects, and the failure would land on the user at post time.
  String get column => switch (this) {
        PostLabel.meal => 'meal',
        PostLabel.workout => 'workout',
        PostLabel.progress => 'progress',
        PostLabel.tip => 'tip',
        PostLabel.question => 'question',
        PostLabel.challenge => 'challenge',
      };

  /// Translation key for the label's name.
  String get labelKey => 'post_label_$column';

  /// Translation key for the composer's hint under this label.
  String get promptKey => 'post_prompt_$column';

  IconData get icon => switch (this) {
        PostLabel.meal => Icons.restaurant_sharp,
        PostLabel.workout => Icons.fitness_center_sharp,
        PostLabel.progress => Icons.trending_up_sharp,
        PostLabel.tip => Icons.lightbulb_sharp,
        PostLabel.question => Icons.help_sharp,
        PostLabel.challenge => Icons.local_fire_department_sharp,
      };

  /// The chip's colour. Distinct enough to tell apart at a glance on a dark
  /// card, and all of them legible against black text when the chip is filled.
  Color get accent => switch (this) {
        PostLabel.meal => const Color(0xFFC3F400),
        PostLabel.workout => const Color(0xFF7DD3FC),
        PostLabel.progress => const Color(0xFFA78BFA),
        PostLabel.tip => const Color(0xFFFDE047),
        PostLabel.question => const Color(0xFFFDA4AF),
        PostLabel.challenge => const Color(0xFFFB923C),
      };

  /// Whether a post under this label is expected to carry photos.
  ///
  /// Only ever used to decide how loudly the composer asks for one. It never
  /// blocks a post: a progress update with no photo is still a progress update.
  bool get wantsImages => this == PostLabel.progress || this == PostLabel.meal;

  /// Whether attaching a meal makes sense here.
  ///
  /// The composer offers the attachment on any label rather than only on
  /// [meal] — a tip about hitting protein is exactly the kind of post that
  /// wants a recipe hanging off it — so this only decides what gets offered
  /// first, not what is allowed.
  bool get suggestsMeal => this == PostLabel.meal;

  /// Parses a stored value.
  ///
  /// Forgiving on purpose, in the same spirit as UserProfile.fromMap: an
  /// unrecognised label means this client is older than the database, and a
  /// post that renders under the wrong chip beats a feed that throws halfway
  /// down. [PostLabel.tip] is the fallback for the same reason it is the
  /// column default — it's the label that claims the least.
  static PostLabel parse(Object? value) {
    final String raw = '${value ?? ''}'.trim().toLowerCase();

    for (final PostLabel label in PostLabel.values) {
      if (label.column == raw) return label;
    }

    return PostLabel.tip;
  }
}
