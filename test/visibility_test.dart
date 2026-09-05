import 'package:bulkr/models/visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromDbValue', () {
    test('reads the three values the CHECK constraint allows', () {
      expect(ContentVisibility.fromDbValue('public'), ContentVisibility.public);
      expect(
        ContentVisibility.fromDbValue('followers'),
        ContentVisibility.followers,
      );
      expect(
        ContentVisibility.fromDbValue('private'),
        ContentVisibility.private,
      );
    });

    test('tolerates casing and padding', () {
      expect(
        ContentVisibility.fromDbValue('  Followers '),
        ContentVisibility.followers,
      );
    });

    test('falls back to public for anything it does not know', () {
      // Including null, which is what a row read before the column existed
      // looks like — and those rows really are public, because public was the
      // only thing a post could be when they were written.
      expect(ContentVisibility.fromDbValue(null), ContentVisibility.public);
      expect(ContentVisibility.fromDbValue(''), ContentVisibility.public);
      expect(ContentVisibility.fromDbValue('friends'), ContentVisibility.public);
    });
  });

  group('fromIsPublic', () {
    test('carries the boolean this replaces across', () {
      expect(ContentVisibility.fromIsPublic(true), ContentVisibility.public);
      expect(ContentVisibility.fromIsPublic(false), ContentVisibility.private);
    });

    test('treats an absent flag as private, matching the old default', () {
      // `MealDraft.isPublic` defaulted to false, so a meal with nothing stored
      // was one nobody else could see. That has to stay true through the
      // migration or meals would be published by upgrading.
      expect(ContentVisibility.fromIsPublic(null), ContentVisibility.private);
    });
  });

  test('dbValue matches what the database will accept', () {
    // If one of these ever drifts, the write fails with a check violation at
    // runtime rather than here.
    expect(
      ContentVisibility.values.map((level) => level.dbValue),
      ['public', 'followers', 'private'],
    );
  });

  test('every level has both a label and a helper to render', () {
    for (final ContentVisibility level in ContentVisibility.values) {
      expect(level.labelKey, isNotEmpty);
      expect(level.helperKey, isNotEmpty);
      expect(level.labelKey, isNot(level.helperKey));
    }
  });

  test('isPublic and isPrivate agree with the level', () {
    expect(ContentVisibility.public.isPublic, isTrue);
    expect(ContentVisibility.followers.isPublic, isFalse);
    expect(ContentVisibility.private.isPublic, isFalse);
    expect(ContentVisibility.private.isPrivate, isTrue);
    expect(ContentVisibility.followers.isPrivate, isFalse);
  });
}
