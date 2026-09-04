/// How long ago something happened, in the compact form feeds use.
///
/// Deliberately not `DateFormat`: a feed wants "3h", not "14:32" or "3 hours
/// ago". The unit is the largest one that still gives a number of at least one,
/// so a post is "2d" rather than "51h".
///
/// Pure and clock-injected so the boundaries can be tested without waiting for
/// them.
class RelativeTime {
  const RelativeTime._();

  /// A short stamp for [moment], relative to [now].
  ///
  /// Returns a translation key and its arguments rather than a string, because
  /// the abbreviations are words in a language — "d" for day is not universal —
  /// and building them here would put English in a file nothing translates.
  ///
  /// The key is always one of `time_now`, `time_minutes`, `time_hours`,
  /// `time_days`, `time_weeks`; every one but the first takes a `count`.
  static ({String key, Map<String, String>? args}) stamp(
    DateTime moment, {
    DateTime? now,
  }) {
    final DateTime reference = now ?? DateTime.now();
    final Duration elapsed = reference.difference(moment);

    // A post dated in the future is a clock disagreement — the device's or the
    // server's — and there is nothing useful to say about it. "Now" is the
    // least wrong answer and the only one that cannot render as "-3h".
    if (elapsed.isNegative) return (key: 'time_now', args: null);

    if (elapsed.inMinutes < 1) return (key: 'time_now', args: null);

    if (elapsed.inHours < 1) {
      return (
        key: 'time_minutes',
        args: {'count': '${elapsed.inMinutes}'},
      );
    }

    if (elapsed.inDays < 1) {
      return (key: 'time_hours', args: {'count': '${elapsed.inHours}'});
    }

    if (elapsed.inDays < 7) {
      return (key: 'time_days', args: {'count': '${elapsed.inDays}'});
    }

    // Weeks is where it stops. Past that the number stops being the useful
    // part — "9w" tells you less than a date would — but a feed rarely reaches
    // back that far, and a date needs a locale-aware formatter and a decision
    // about whether to show the year. Both belong to the screen that needs
    // them, not to a stamp on a card.
    return (key: 'time_weeks', args: {'count': '${elapsed.inDays ~/ 7}'});
  }
}
