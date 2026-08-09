import 'dart:math';

import 'package:bulkr/data/username_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slugify', () {
    test('lowercases and collapses separators to underscores', () {
      expect(UsernameGenerator.slugify('Ahmed El-Rashidy'), 'ahmed_el_rashidy');
    });

    test('trims surrounding whitespace and separators', () {
      expect(UsernameGenerator.slugify('  Foo  Bar!!  '), 'foo_bar');
    });

    test('collapses a run of separators into a single underscore', () {
      expect(UsernameGenerator.slugify('a...b'), 'a_b');
    });

    test('returns empty when nothing usable survives', () {
      // Non-Latin display names slug to nothing, so callers fall through to
      // the email local-part instead of storing a bare underscore.
      expect(UsernameGenerator.slugify('محمد'), '');
      expect(UsernameGenerator.slugify('!!!'), '');
      expect(UsernameGenerator.slugify(''), '');
    });

    test('truncates to the column width', () {
      final long = 'a' * 120;
      expect(
        UsernameGenerator.slugify(long).length,
        UsernameGenerator.maxLength,
      );
    });
  });

  group('isValid', () {
    test('accepts lowercase letters, digits and underscores', () {
      expect(UsernameGenerator.isValid('valid_user1'), isTrue);
      expect(UsernameGenerator.isValid('abc'), isTrue);
    });

    test('rejects anything the column or the UI should not carry', () {
      expect(UsernameGenerator.isValid('ab'), isFalse); // too short
      expect(UsernameGenerator.isValid('a' * 51), isFalse); // too long
      expect(UsernameGenerator.isValid('Bad'), isFalse); // uppercase
      expect(UsernameGenerator.isValid('has space'), isFalse);
      expect(UsernameGenerator.isValid('dots.not.allowed'), isFalse);
      expect(UsernameGenerator.isValid(''), isFalse);
    });
  });

  group('suggest', () {
    final generator = UsernameGenerator(random: Random(42));

    test('prefers the display name', () {
      expect(
        generator.suggest(
          displayName: 'Ahmed El-Rashidy',
          email: 'other@example.com',
        ),
        'ahmed_el_rashidy',
      );
    });

    test('falls back to the email local-part', () {
      expect(
        generator.suggest(email: 'ahmed.elrashidy@mafi-egypt.com'),
        'ahmed_elrashidy',
      );
    });

    test('falls back again when the display name has nothing usable', () {
      expect(
        generator.suggest(displayName: 'محمد', email: 'lifter@example.com'),
        'lifter',
      );
    });

    test('always produces something valid, even with no identity at all', () {
      final result = generator.suggest();
      expect(UsernameGenerator.isValid(result), isTrue);
      expect(result, startsWith('bulkr_'));
    });
  });

  group('withSuffix', () {
    final generator = UsernameGenerator(random: Random(7));

    test('appends a random suffix', () {
      final result = generator.withSuffix('lifter');
      expect(result, startsWith('lifter_'));
      expect(UsernameGenerator.isValid(result), isTrue);
    });

    test('varies between calls so a collision retry actually changes', () {
      final first = generator.withSuffix('lifter');
      final second = generator.withSuffix('lifter');
      expect(first, isNot(second));
    });

    test('keeps the result inside the column width for a maximal stem', () {
      final result = generator.withSuffix('a' * UsernameGenerator.maxLength);
      expect(result.length, lessThanOrEqualTo(UsernameGenerator.maxLength));
      expect(UsernameGenerator.isValid(result), isTrue);
    });
  });
}
