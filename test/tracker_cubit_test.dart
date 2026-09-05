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

  final UserProfile? profile;

  @override
  Future<UserProfile?> fetchProfile() async => profile;
}

UserProfile _profile({
  int calories = 3000,
  int protein = 180,
  int carbs = 350,
  int fat = 90,
}) =>
    UserProfile(
      id: 'u1',
      username: 'maxgains',
      displayName: 'Max Gains',
      gender: Gender.male,
      dateOfBirth: DateTime(1996, 3, 2),
      heightCm: 180,
      currentWeightKg: 88.5,
      targetWeightKg: 95,
      activityLevel: ActivityLevel.moderatelyActive,
      units: UnitSystem.metric,
      dailyCalorieTarget: calories,
      proteinTargetG: protein,
      carbsTargetG: carbs,
      fatTargetG: fat,
      onboardingCompleted: true,
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
}
