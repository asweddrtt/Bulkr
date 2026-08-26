import 'package:bulkr/cubit/meals/meals_cubit.dart';
import 'package:bulkr/data/food_repository.dart';
import 'package:bulkr/data/meal_repository.dart';
import 'package:bulkr/models/macros.dart';
import 'package:bulkr/models/meal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records which write was asked for instead of talking to Supabase. The base
/// constructor is handed a client it never calls.
class _FakeMealRepository extends MealRepository {
  _FakeMealRepository._(SupabaseClient client, {required this.throwOnWrite})
      : super(
          client: client,
          // Passed explicitly: the default would reach for
          // `Supabase.instance`, which no test initialises.
          foodRepository: FoodRepository(client: client),
        );

  factory _FakeMealRepository({bool throwOnWrite = false}) {
    return _FakeMealRepository._(
      SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        // Without this the auth client starts a periodic refresh timer, and
        // flutter_test fails any test that leaves a timer pending.
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
      throwOnWrite: throwOnWrite,
    );
  }

  final bool throwOnWrite;

  final List<String> deleted = [];
  final List<String> unsaved = [];

  @override
  Future<void> deleteMeal(Meal meal) async {
    if (throwOnWrite) throw Exception('nope');
    deleted.add(meal.id);
  }

  @override
  Future<void> removeFromLibrary(Meal meal) async {
    if (throwOnWrite) throw Exception('nope');
    unsaved.add(meal.id);
  }
}

void main() {
  Meal meal(String id, {bool isMine = true}) => Meal(
        id: id,
        creatorId: isMine ? 'me' : 'someone-else',
        title: 'Meal $id',
        totals: const Macros(calories: 900),
        createdAt: DateTime(2026, 8, 20),
        isMine: isMine,
        isSaved: !isMine,
      );

  /// Seeds the library through `adopt`, the public path a freshly created meal
  /// takes, rather than reaching into the cubit's protected `emit`.
  MealsCubit cubitWith(
    _FakeMealRepository repository,
    List<Meal> library,
  ) {
    final cubit = MealsCubit(mealRepository: repository);
    for (final Meal meal in library.reversed) {
      cubit.adopt(meal);
    }
    return cubit;
  }

  group('removeMeal', () {
    test('deletes a meal the user wrote', () async {
      final repository = _FakeMealRepository();
      final cubit = cubitWith(repository, [meal('a'), meal('b')]);

      await cubit.removeMeal(meal('a'));

      expect(repository.deleted, ['a']);
      expect(repository.unsaved, isEmpty);
      expect(cubit.state.library.map((m) => m.id), ['b']);

      await cubit.close();
    });

    test('only unsaves a meal someone else wrote', () async {
      final repository = _FakeMealRepository();
      final cubit = cubitWith(
        repository,
        [meal('a', isMine: false), meal('b')],
      );

      await cubit.removeMeal(meal('a', isMine: false));

      // The meal is not the user's to delete — only their library row goes.
      expect(repository.deleted, isEmpty);
      expect(repository.unsaved, ['a']);
      expect(cubit.state.library.map((m) => m.id), ['b']);

      await cubit.close();
    });

    test('puts the meal back when the write fails', () async {
      final repository = _FakeMealRepository(throwOnWrite: true);
      final cubit = cubitWith(repository, [meal('a'), meal('b'), meal('c')]);

      await cubit.removeMeal(meal('b'));

      expect(cubit.state.library.map((m) => m.id), ['a', 'b', 'c']);
      expect(cubit.state.actionErrorKey, isNotNull);

      await cubit.close();
    });

    test('restores the original order, not just the membership', () async {
      final repository = _FakeMealRepository(throwOnWrite: true);
      final cubit = cubitWith(repository, [meal('a'), meal('b'), meal('c')]);

      await cubit.removeMeal(meal('a'));

      expect(cubit.state.library.first.id, 'a');

      await cubit.close();
    });
  });

  group('storagePathFor', () {
    test('extracts the object path from a public URL', () {
      expect(
        MealRepository.storagePathFor(
          'https://x.supabase.co/storage/v1/object/public/meal-images/'
          'user-1/1724688000.jpg',
        ),
        'user-1/1724688000.jpg',
      );
    });

    test('drops a query string', () {
      expect(
        MealRepository.storagePathFor(
          'https://x.supabase.co/storage/v1/object/public/meal-images/'
          'user-1/a.jpg?token=abc',
        ),
        'user-1/a.jpg',
      );
    });

    test('is null for a meal with no photo', () {
      expect(MealRepository.storagePathFor(null), isNull);
      expect(MealRepository.storagePathFor(''), isNull);
    });

    test('is null for an image hosted somewhere that is not ours to delete',
        () {
      expect(
        MealRepository.storagePathFor('https://example.test/photo.jpg'),
        isNull,
      );
      expect(
        MealRepository.storagePathFor(
          'https://x.supabase.co/storage/v1/object/public/avatars/a.jpg',
        ),
        isNull,
      );
    });
  });
}
