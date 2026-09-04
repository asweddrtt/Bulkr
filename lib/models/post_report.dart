/// Why someone reported a post.
///
/// A fixed set, mirroring the CHECK constraint on `post_reports.reason`. Free
/// text was the alternative and is worse in every direction: it invites abuse
/// of the report form itself, it cannot be counted, and it needs a human to
/// read it — and there is no human whose job that is.
///
/// [other] carries an optional note for the case the list does not cover. The
/// note is stored and shown to nobody but its author.
enum PostReportReason {
  spam,
  harassment,
  misinformation,
  inappropriate,
  other;

  /// The value stored in `post_reports.reason`.
  ///
  /// Written out rather than derived from [name] so that renaming a member in
  /// Dart cannot silently start writing a value the CHECK constraint rejects —
  /// a failure that would land on the user at report time.
  String get column => switch (this) {
        PostReportReason.spam => 'spam',
        PostReportReason.harassment => 'harassment',
        PostReportReason.misinformation => 'misinformation',
        PostReportReason.inappropriate => 'inappropriate',
        PostReportReason.other => 'other',
      };

  /// Translation key for the reason's label.
  String get labelKey => 'report_reason_$column';

  /// Translation key for the line explaining what it covers.
  ///
  /// Worth having: "inappropriate" and "harassment" overlap in most people's
  /// heads, and a report filed under the wrong one is a report that reads as
  /// less serious than it is.
  String get helperKey => 'report_reason_${column}_helper';

  /// Whether choosing this reason should ask for a note.
  ///
  /// Only [other], and only because the enumeration has failed to describe
  /// what they saw. Asking for a note on every reason turns a two-tap action
  /// into a form and gets fewer reports filed.
  bool get wantsNote => this == PostReportReason.other;

  static PostReportReason parse(Object? value) {
    final String raw = '${value ?? ''}'.trim().toLowerCase();

    for (final PostReportReason reason in PostReportReason.values) {
      if (reason.column == raw) return reason;
    }

    return PostReportReason.other;
  }
}
