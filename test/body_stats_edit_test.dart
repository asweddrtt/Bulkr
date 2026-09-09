import 'package:bulkr/models/activity_level.dart';
import 'package:bulkr/widgets/body_stats_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sheet writes three inputs the calorie engine derives a target from, so
/// "did anything actually change" is not cosmetic — it decides whether a write
/// happens and whether the user is then asked to move their calorie target.
/// Getting it wrong in the lenient direction offers to recalculate a plan whose
/// inputs are identical, which reads as the app being confused.
void main() {
  final DateTime dob = DateTime(1996, 3, 2);

  BodyStatsEdit base() => BodyStatsEdit(
        dateOfBirth: dob,
        heightCm: 180,
        activityLevel: ActivityLevel.moderatelyActive,
      );

  test('identical values are not a change', () {
    expect(base().differsFrom(base()), isFalse);
    // A different DateTime instance for the same day still is not a change:
    // the picker hands back a fresh object every time it is opened.
    expect(
      BodyStatsEdit(
        dateOfBirth: DateTime(1996, 3, 2),
        heightCm: 180,
        activityLevel: ActivityLevel.moderatelyActive,
      ).differsFrom(base()),
      isFalse,
    );
  });

  test('each field on its own counts', () {
    expect(
      BodyStatsEdit(
        dateOfBirth: DateTime(1996, 3, 3),
        heightCm: 180,
        activityLevel: ActivityLevel.moderatelyActive,
      ).differsFrom(base()),
      isTrue,
    );
    expect(
      BodyStatsEdit(
        dateOfBirth: dob,
        heightCm: 181,
        activityLevel: ActivityLevel.moderatelyActive,
      ).differsFrom(base()),
      isTrue,
    );
    expect(
      BodyStatsEdit(
        dateOfBirth: dob,
        heightCm: 180,
        activityLevel: ActivityLevel.veryActive,
      ).differsFrom(base()),
      isTrue,
    );
  });

  test('filling in a date of birth that was missing counts', () {
    // The state an account is in when it never finished onboarding, and the
    // one `recalculate_needs_biometrics` exists for. Supplying it is the whole
    // point of the sheet, so it must register as a change.
    final BodyStatsEdit missing = BodyStatsEdit(
      dateOfBirth: null,
      heightCm: 180,
      activityLevel: ActivityLevel.moderatelyActive,
    );

    expect(base().differsFrom(missing), isTrue);
    expect(missing.differsFrom(base()), isTrue);
  });
}
