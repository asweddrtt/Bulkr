import 'package:bulkr/cubit/tracker/tracker_cubit.dart';
import 'package:bulkr/data/food_repository.dart';
import 'package:bulkr/data/meal_repository.dart';
import 'package:bulkr/data/user_repository.dart';
import 'package:bulkr/models/activity_level.dart';
import 'package:bulkr/models/daily_log_entry.dart';
import 'package:bulkr/models/gender.dart';
import 'package:bulkr/models/meal_slot.dart';
import 'package:bulkr/models/unit_system.dart';
import 'package:bulkr/models/user_profile.dart';
import 'package:bulkr/models/water_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A client the fakes are handed and never call. Without the auth option the
/// client starts a periodic refresh timer, and flutter_test fails any test
/// that leaves a timer pending.
SupabaseClient _client() => SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );

class _FakeMealRepository extends MealRepository {
  _FakeMealRepository._(SupabaseClient client, {required this.entries})
      : super(client: client, foodRepository: FoodRepository(client: client));

  factory _FakeMealRepository({List<DailyLogEntry> entries = const []}) =>
      _FakeMealRepository._(_client(), entries: entries);

  List<DailyLogEntry> entries;

  final List<String> deleted = [];
  bool throwOnRead = false;

  @override
  Future<List<DailyLogEntry>> fetchDayLog(DateTime day) async {
    if (throwOnRead) throw Exception('nope');
    return entries;
  }

  @override
  Future<void> deleteLogEntry(DailyLogEntry entry) async {
    deleted.add(entry.id);
    entries = entries.where((e) => e.id != entry.id).toList();
  }
}

class _FakeUserRepository extends UserRepository {
  _FakeUserRepository({this.profile}) : super(client: _client());

  UserProfile? profile;

  /// Starts empty and grows through [logWater], the way the real table does.
  List<WaterEntry> water = const [];

  bool throwOnWaterRead = false;
  final List<int> logged = [];
  final List<String> deletedWater = [];

  /// Records the last call, including the null that means "go back to
  /// deriving it from bodyweight" — which is why this is a separate flag
  /// rather than checking for null.
  bool targetWasSet = false;
  int? lastTarget;

  double? loggedWeightKg;

  @override
  Future<UserProfile?> fetchProfile() async => profile;

  @override
  Future<List<WaterEntry>> fetchWaterDay(DateTime day) async {
    if (throwOnWaterRead) throw Exception('no such table');
    return water;
  }

  @override
  Future<void> logWater({required int millilitres, DateTime? day}) async {
    logged.add(millilitres);
    water = [
      ...water,
      WaterEntry(
        id: 'w${water.length + 1}',
        millilitres: millilitres,
        loggedAt: DateTime.now(),
      ),
    ];
  }

  @override
  Future<void> deleteWaterEntry(WaterEntry entry) async {
    deletedWater.add(entry.id);
    water = water.where((e) => e.id != entry.id).toList();
  }

  @override
  Future<void> updateWaterTarget({int? millilitres}) async {
    targetWasSet = true;
    lastTarget = millilitres;
  }

  @override
  Future<void> logWeight({required double weightKg}) async {
    loggedWeightKg = weightKg;
  }
}

UserProfile _profile({
  int calories = 3000,
  int protein = 180,
  int carbs = 350,
  int fat = 90,
  double weightKg = 88.5,
  int? waterTargetMl,
}) =>
    UserProfile(
      id: 'u1',
      username: 'maxgains',
      displayName: 'Max Gains',
      gender: Gender.male,
      dateOfBirth: DateTime(1996, 3, 2),
      heightCm: 180,
      currentWeightKg: weightKg,
      targetWeightKg: 95,
      activityLevel: ActivityLevel.moderatelyActive,
      units: UnitSystem.metric,
      dailyCalorieTarget: calories,
      proteinTargetG: protein,
      carbsTargetG: carbs,
      fatTargetG: fat,
      onboardingCompleted: true,
      waterTargetMl: waterTargetMl,
    );

DailyLogEntry _entry({
  required String id,
  String? slot,
  int calories = 0,
  int protein = 0,
}) =>
    DailyLogEntry.fromRow({
      'id': id,
      'log_date': '2026-09-05',
      'meal_type': slot,
      'item_name': 'Thing $id',
      'calories_logged': calories,
      'protein_logged_g': protein,
      'carbs_logged_g': 0,
      'fat_logged_g': 0,
    });

TrackerCubit _cubit(_FakeMealRepository meals, _FakeUserRepository users) =>
    TrackerCubit(mealRepository: meals, userRepository: users);

void main() {
  test('loads the day and totals what is in it', () async {
    final meals = _FakeMealRepository(entries: [
      _entry(id: 'a', slot: 'breakfast', calories: 520, protein: 40),
      _entry(id: 'b', slot: 'lunch', calories: 980, protein: 60),
    ]);
    final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

    await cubit.load();

    expect(cubit.state.status, TrackerStatus.ready);
    expect(cubit.state.consumed.calories, 1500);
    expect(cubit.state.consumed.proteinG, 100);
    expect(cubit.state.caloriesRemaining, 1500);
    expect(cubit.state.isOverTarget, isFalse);
    expect(cubit.state.calorieProgress, closeTo(0.5, 0.0001));

    await cubit.close();
  });

  test('groups entries by slot, with a subtotal each', () async {
    final meals = _FakeMealRepository(entries: [
      _entry(id: 'a', slot: 'breakfast', calories: 300),
      _entry(id: 'b', slot: 'breakfast', calories: 220),
      _entry(id: 'c', slot: 'dinner', calories: 800),
    ]);
    final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

    await cubit.load();

    expect(cubit.state.entriesIn(MealSlot.breakfast).length, 2);
    expect(cubit.state.totalIn(MealSlot.breakfast).calories, 520);
    expect(cubit.state.totalIn(MealSlot.dinner).calories, 800);
    expect(cubit.state.entriesIn(MealSlot.lunch), isEmpty);
    expect(cubit.state.totalIn(MealSlot.lunch).calories, 0);

    await cubit.close();
  });

  test('entries with no slot are kept and still counted', () async {
    // Every row written before slots existed looks like this. Dropping them
    // would make the day's total disagree with the log the user can see.
    final meals = _FakeMealRepository(entries: [
      _entry(id: 'a', slot: 'lunch', calories: 400),
      _entry(id: 'legacy', calories: 600),
    ]);
    final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

    await cubit.load();

    expect(cubit.state.unsortedEntries.map((e) => e.id), ['legacy']);
    expect(cubit.state.unsortedTotal.calories, 600);
    expect(cubit.state.consumed.calories, 1000);

    await cubit.close();
  });

  test('reports going over rather than wrapping the ring', () async {
    final meals = _FakeMealRepository(entries: [
      _entry(id: 'a', slot: 'dinner', calories: 3400),
    ]);
    final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

    await cubit.load();

    expect(cubit.state.isOverTarget, isTrue);
    expect(cubit.state.caloriesRemaining, -400);
    expect(cubit.state.calorieProgress, 1.0);

    await cubit.close();
  });

  test('a zero target counts as no target rather than a full ring', () async {
    // UserProfile defaults a null column to 0, and dividing by that gives
    // either infinity or a full ring on the first bite.
    final meals = _FakeMealRepository(entries: [
      _entry(id: 'a', slot: 'lunch', calories: 500),
    ]);
    final cubit = _cubit(
      meals,
      _FakeUserRepository(profile: _profile(calories: 0)),
    );

    await cubit.load();

    expect(cubit.state.hasTarget, isFalse);
    expect(cubit.state.calorieTarget, isNull);
    expect(cubit.state.caloriesRemaining, isNull);
    expect(cubit.state.calorieProgress, 0);
    expect(cubit.state.isOverTarget, isFalse);
    // Intake is still known and still shown.
    expect(cubit.state.consumed.calories, 500);

    await cubit.close();
  });

  test('no users row reports missing rather than failure', () async {
    final cubit = _cubit(_FakeMealRepository(), _FakeUserRepository());

    await cubit.load();

    expect(cubit.state.status, TrackerStatus.missing);

    await cubit.close();
  });

  test('a failed read surfaces the error without losing the day', () async {
    final meals = _FakeMealRepository(entries: [
      _entry(id: 'a', slot: 'lunch', calories: 400),
    ]);
    final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

    await cubit.load();
    expect(cubit.state.entries, hasLength(1));

    meals.throwOnRead = true;
    await cubit.refresh();

    expect(cubit.state.status, TrackerStatus.failure);
    expect(cubit.state.errorMessage, isNotNull);
    // A silent refresh that fails leaves what was already on screen.
    expect(cubit.state.entries, hasLength(1));

    await cubit.close();
  });

  test('deleting an entry re-reads the day', () async {
    final meals = _FakeMealRepository(entries: [
      _entry(id: 'a', slot: 'lunch', calories: 400),
      _entry(id: 'b', slot: 'dinner', calories: 600),
    ]);
    final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

    await cubit.load();
    await cubit.deleteEntry(cubit.state.entries.first);

    expect(meals.deleted, ['a']);
    expect(cubit.state.entries.map((e) => e.id), ['b']);
    expect(cubit.state.consumed.calories, 600);
    expect(cubit.state.isSaving, isFalse);

    await cubit.close();
  });

  test('resizing an entry with no weight is refused, not guessed', () async {
    final meals = _FakeMealRepository(entries: [
      DailyLogEntry.fromRow({
        'id': 'a',
        'log_date': '2026-09-05',
        'meal_id': 'm1',
        'quantity_g': 0,
        'calories_logged': 640,
      }),
    ]);
    final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

    await cubit.load();
    await cubit.resizeEntry(cubit.state.entries.first, 250);

    expect(cubit.state.consumed.calories, 640);
    expect(cubit.state.actionErrorKey, isNull);

    await cubit.close();
  });

  group('water', () {
    test('derives the goal from bodyweight when none is stored', () async {
      final users = _FakeUserRepository(profile: _profile(weightKg: 80));
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();

      // 80 kg * 35 ml/kg — the same figure the insight card has always quoted.
      expect(cubit.state.waterTargetMl, 2800);
      expect(cubit.state.hasCustomWaterTarget, isFalse);

      await cubit.close();
    });

    test('a stored goal wins over the derived one', () async {
      final users = _FakeUserRepository(
        profile: _profile(weightKg: 80, waterTargetMl: 4000),
      );
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();

      expect(cubit.state.waterTargetMl, 4000);
      expect(cubit.state.hasCustomWaterTarget, isTrue);

      await cubit.close();
    });

    test('no usable weight means no goal rather than a goal of zero', () async {
      final users = _FakeUserRepository(profile: _profile(weightKg: 0));
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();

      expect(cubit.state.waterTargetMl, isNull);
      expect(cubit.state.hasWaterTarget, isFalse);
      expect(cubit.state.waterProgress, 0);

      await cubit.close();
    });

    test('adding and undoing a drink moves the total', () async {
      final users = _FakeUserRepository(profile: _profile(weightKg: 80));
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();
      await cubit.addWater(250);
      await cubit.addWater(500);

      expect(users.logged, [250, 500]);
      expect(cubit.state.waterMl, 750);
      expect(cubit.state.waterProgress, closeTo(750 / 2800, 0.0001));

      // Undo takes the most recent one, not the first.
      await cubit.undoLastWater();
      expect(users.deletedWater, ['w2']);
      expect(cubit.state.waterMl, 250);

      await cubit.close();
    });

    test('undo with nothing logged does nothing', () async {
      final users = _FakeUserRepository(profile: _profile());
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();
      await cubit.undoLastWater();

      expect(users.deletedWater, isEmpty);
      expect(cubit.state.actionErrorKey, isNull);

      await cubit.close();
    });

    test('clearing the goal is a real write, not a no-op', () async {
      // Null means "derive from bodyweight", which is a choice someone makes.
      // It must reach the repository rather than being filtered out as absent.
      final users = _FakeUserRepository(
        profile: _profile(waterTargetMl: 4000),
      );
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();
      await cubit.setWaterTarget(null);

      expect(users.targetWasSet, isTrue);
      expect(users.lastTarget, isNull);

      await cubit.close();
    });

    test('refuses a goal outside what the column will store', () async {
      final users = _FakeUserRepository(profile: _profile());
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();
      await cubit.setWaterTarget(0);
      await cubit.setWaterTarget(30000);

      expect(users.targetWasSet, isFalse);

      await cubit.close();
    });

    test('water failing does not take the day down with it', () async {
      // What "tracker_water.sql has not been run" looks like: the food still
      // loads, and the card says why rather than reading zero forever.
      final meals = _FakeMealRepository(entries: [
        _entry(id: 'a', slot: 'lunch', calories: 400),
      ]);
      final users = _FakeUserRepository(profile: _profile())
        ..throwOnWaterRead = true;
      final cubit = _cubit(meals, users);

      await cubit.load();

      expect(cubit.state.status, TrackerStatus.ready);
      expect(cubit.state.consumed.calories, 400);
      expect(cubit.state.waterMl, 0);
      expect(cubit.state.waterErrorDetail, isNotNull);

      await cubit.close();
    });
  });

  group('browsing days', () {
    test('walks back and reloads', () async {
      final meals = _FakeMealRepository();
      final cubit = _cubit(meals, _FakeUserRepository(profile: _profile()));

      await cubit.load();
      final DateTime today = cubit.state.day;

      await cubit.previousDay();

      expect(cubit.state.day, today.subtract(const Duration(days: 1)));
      expect(cubit.state.isToday, isFalse);

      await cubit.close();
    });

    test('never walks forward past today', () async {
      final cubit = _cubit(
        _FakeMealRepository(),
        _FakeUserRepository(profile: _profile()),
      );

      await cubit.load();
      final DateTime today = cubit.state.day;

      await cubit.nextDay();
      expect(cubit.state.day, today);

      await cubit.showDay(today.add(const Duration(days: 7)));
      expect(cubit.state.day, today);

      await cubit.close();
    });

    test('walking back then forward lands on today again', () async {
      final cubit = _cubit(
        _FakeMealRepository(),
        _FakeUserRepository(profile: _profile()),
      );

      await cubit.load();
      final DateTime today = cubit.state.day;

      await cubit.previousDay();
      await cubit.previousDay();
      await cubit.nextDay();
      await cubit.nextDay();

      expect(cubit.state.day, today);
      expect(cubit.state.isToday, isTrue);

      await cubit.close();
    });

    test('the overnight refresh leaves a browsed day alone', () async {
      // refreshIfDayChanged fires on every tab switch. Someone looking at last
      // Tuesday should still be looking at it.
      final cubit = _cubit(
        _FakeMealRepository(),
        _FakeUserRepository(profile: _profile()),
      );

      await cubit.load();
      await cubit.previousDay();
      final DateTime browsed = cubit.state.day;

      await cubit.refreshIfDayChanged();

      expect(cubit.state.day, browsed);

      await cubit.close();
    });
  });

  group('weight', () {
    test('records today\'s weigh-in', () async {
      final users = _FakeUserRepository(profile: _profile());
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();
      await cubit.logWeight(89.2);

      expect(users.loggedWeightKg, 89.2);

      await cubit.close();
    });

    test('refuses on a past day, where the write could not honour it',
        () async {
      final users = _FakeUserRepository(profile: _profile());
      final cubit = _cubit(_FakeMealRepository(), users);

      await cubit.load();
      await cubit.previousDay();
      await cubit.logWeight(89.2);

      expect(users.loggedWeightKg, isNull);

      await cubit.close();
    });
  });
}
