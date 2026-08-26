/// A sliding-window cap on how often something may run.
///
/// Open Food Facts allows ten search requests a minute per IP, and answers the
/// eleventh with a 429. A debounced field can still reach that during sustained
/// typing, and once it does, every search fails until the minute rolls over —
/// so the limit is enforced here, before the call, rather than discovered from
/// the response.
///
/// Deliberately not a token bucket: what matters is the same rule the server
/// applies, which is a count over a window, and matching it exactly is easier
/// to reason about than approximating it with a refill rate.
///
/// Time is injected so the behaviour at the window boundary can be tested
/// without waiting a minute for it.
class RateLimiter {
  RateLimiter({
    required this.maxCalls,
    required this.window,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How many calls the window allows.
  final int maxCalls;

  final Duration window;
  final DateTime Function() _clock;

  final List<DateTime> _calls = [];

  /// Records a call and reports whether it was allowed.
  ///
  /// One method rather than a separate check and record, because anything that
  /// asks permission and then forgets to say it went ahead silently stops
  /// limiting anything.
  bool tryCall() {
    final DateTime now = _clock();
    _prune(now);

    if (_calls.length >= maxCalls) return false;

    _calls.add(now);
    return true;
  }

  /// How many calls remain in the current window.
  int get remaining {
    _prune(_clock());
    final int left = maxCalls - _calls.length;
    return left < 0 ? 0 : left;
  }

  /// How long until the next call would be allowed. Zero when one is allowed
  /// right now.
  Duration get retryAfter {
    final DateTime now = _clock();
    _prune(now);

    if (_calls.length < maxCalls) return Duration.zero;
    return window - now.difference(_calls.first);
  }

  /// Drops the calls that have aged out of the window.
  void _prune(DateTime now) {
    final DateTime cutoff = now.subtract(window);
    _calls.removeWhere((at) => !at.isAfter(cutoff));
  }

  /// Forgets every recorded call.
  void reset() => _calls.clear();
}
