import 'package:bulkr/core/rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A clock the test drives, so the window boundary can be checked without
  // waiting a real minute for it.
  late DateTime now;
  RateLimiter limiter({int maxCalls = 3}) => RateLimiter(
        maxCalls: maxCalls,
        window: const Duration(minutes: 1),
        clock: () => now,
      );

  setUp(() => now = DateTime(2026, 8, 26, 12));

  test('allows calls up to the cap and refuses the next', () {
    final subject = limiter();

    expect(subject.tryCall(), isTrue);
    expect(subject.tryCall(), isTrue);
    expect(subject.tryCall(), isTrue);
    expect(subject.tryCall(), isFalse);
  });

  test('reports what is left', () {
    final subject = limiter();

    expect(subject.remaining, 3);
    subject.tryCall();
    expect(subject.remaining, 2);

    subject.tryCall();
    subject.tryCall();
    expect(subject.remaining, 0);

    // Never negative, however many refusals pile up.
    subject.tryCall();
    subject.tryCall();
    expect(subject.remaining, 0);
  });

  test('the window slides — calls are forgiven as they age out', () {
    final subject = limiter();

    subject.tryCall();
    now = now.add(const Duration(seconds: 20));
    subject.tryCall();
    now = now.add(const Duration(seconds: 20));
    subject.tryCall();

    expect(subject.tryCall(), isFalse);

    // 21s more puts the first call 61s in the past, freeing exactly one slot.
    now = now.add(const Duration(seconds: 21));
    expect(subject.remaining, 1);
    expect(subject.tryCall(), isTrue);
    expect(subject.tryCall(), isFalse);
  });

  test('a call exactly on the boundary has aged out', () {
    final subject = limiter(maxCalls: 1);

    expect(subject.tryCall(), isTrue);

    now = now.add(const Duration(seconds: 59));
    expect(subject.tryCall(), isFalse);

    now = now.add(const Duration(seconds: 1));
    expect(subject.tryCall(), isTrue);
  });

  test('retryAfter is zero while a call is allowed', () {
    final subject = limiter();

    expect(subject.retryAfter, Duration.zero);
    subject.tryCall();
    expect(subject.retryAfter, Duration.zero);
  });

  test('retryAfter counts down to the oldest call leaving the window', () {
    final subject = limiter(maxCalls: 2);

    subject.tryCall();
    now = now.add(const Duration(seconds: 10));
    subject.tryCall();

    // The oldest call is 10s old, so 50s until it ages out.
    expect(subject.retryAfter, const Duration(seconds: 50));

    now = now.add(const Duration(seconds: 30));
    expect(subject.retryAfter, const Duration(seconds: 20));
  });

  test('reset forgets everything', () {
    final subject = limiter(maxCalls: 1);

    expect(subject.tryCall(), isTrue);
    expect(subject.tryCall(), isFalse);

    subject.reset();
    expect(subject.tryCall(), isTrue);
  });

  test('a whole quiet window restores the full budget', () {
    final subject = limiter();

    subject.tryCall();
    subject.tryCall();
    subject.tryCall();
    expect(subject.remaining, 0);

    now = now.add(const Duration(minutes: 2));
    expect(subject.remaining, 3);
  });
}
