/// Who can see one post or one meal — `posts.visibility` and
/// `meals.visibility`.
///
/// Three levels rather than the boolean `meals.is_public` used to be, because
/// the middle one is the one people actually want: shared with the people who
/// follow you, and not with Discover. A boolean cannot express it, and the
/// workaround — posting nothing — is what people do instead.
///
/// The database has the same three values and a CHECK constraint holding it to
/// them, so [dbValue] is not a convention but a contract.
enum ContentVisibility {
  /// Anyone signed in. What everything written before this existed already was,
  /// which is why it is the default at both ends.
  public('public', 'visibility_public', 'visibility_public_helper'),

  /// People who follow the author. Checked in the row-level security policy by
  /// `public.follows_me`, not in the client — a filter the app applies is a
  /// filter another client can decline to apply.
  followers('followers', 'visibility_followers', 'visibility_followers_helper'),

  /// The author alone. A meal kept private is still yours to log and to eat;
  /// it just never appears to anybody else.
  private('private', 'visibility_private', 'visibility_private_helper');

  const ContentVisibility(this.dbValue, this.labelKey, this.helperKey);

  /// Exact value the CHECK constraint accepts.
  final String dbValue;

  final String labelKey;
  final String helperKey;

  bool get isPublic => this == ContentVisibility.public;
  bool get isPrivate => this == ContentVisibility.private;

  /// What a row says, defaulting to [public] for anything unrecognised.
  ///
  /// Forgiving on purpose, and in the safe direction only in one sense: a row
  /// this build does not understand renders as public because that is what
  /// every row written before the column existed *is*. The database is what
  /// actually decides who may read it — this is a label, not a gate.
  static ContentVisibility fromDbValue(Object? value) {
    final String raw = '${value ?? ''}'.trim().toLowerCase();
    for (final ContentVisibility level in values) {
      if (level.dbValue == raw) return level;
    }
    return ContentVisibility.public;
  }

  /// Reads the boolean `meals.is_public` this replaces, for a row written
  /// before the migration ran.
  static ContentVisibility fromIsPublic(Object? value) =>
      value == true ? ContentVisibility.public : ContentVisibility.private;
}
