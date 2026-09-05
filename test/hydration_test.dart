import 'package:bulkr/core/hydration.dart';
import 'package:bulkr/core/insight_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the advice and the goal use the same figure', () {
    // The reason these constants moved out of InsightEngine at all: the
    // insight card telling someone to drink 3.1 L while the ring beside it
    // fills at 3.0 would be a bug nobody could explain.
    expect(InsightEngine.waterMlPerKg, Hydration.mlPerKg);
  });

  test('targetMlFor scales with bodyweight', () {
    expect(Hydration.targetMlFor(80), 2800);
    expect(Hydration.targetMlFor(100), 3500);
    expect(Hydration.targetMlFor(62.5), 2188);
  });

  test('an unknown weight has no goal rather than a goal of zero', () {
    // Zero would render as a full ring on the first sip.
    expect(Hydration.targetMlFor(null), isNull);
    expect(Hydration.targetMlFor(0), isNull);
    expect(Hydration.targetMlFor(-5), isNull);
  });

  test('glassesFor counts 250 ml glasses', () {
    expect(Hydration.glassesFor(2800), 11);
    expect(Hydration.glassesFor(250), 1);
    expect(Hydration.glassesFor(0), 0);
  });

  test('the cap matches what the column will store', () {
    // Mirrors users_water_target_ml_check in tracker_water.sql. If one moves
    // the other has to, or the field accepts what the database rejects.
    expect(Hydration.maxTargetMl, 20000);
  });
}
