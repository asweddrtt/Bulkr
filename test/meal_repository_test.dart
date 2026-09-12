import 'dart:convert';

import 'package:bulkr/data/meal_repository.dart';
import 'package:bulkr/models/daily_log_entry.dart';
import 'package:bulkr/models/macros.dart';
import 'package:bulkr/models/meal.dart';
import 'package:bulkr/models/meal_slot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the tracker writes, and which day it writes it to.
///
/// `MealRepository` is a thousand lines and had no tests. The part worth
/// pinning hardest is the date: `daily_logs.log_date` is a Postgres `DATE`,
/// and the repository deliberately sends the user's **local** day rather than
/// a UTC timestamp. Get that wrong and a meal logged at 9pm in UTC+3 lands on
/// tomorrow, which the user experiences as food disappearing from today and a
/// streak breaking for no reason — at night, for everybody east of Greenwich,
/// and never for a developer testing at noon in UTC.
void main() {
  late List<_Call> calls;

  /// A client with a session, answering every PostgREST call with [rows].
  ///
  /// The session is the point: almost every method here begins
  /// `if (userId == null) return`, so without one the tests would all pass
  /// against a repository that never made a request.
  Future<SupabaseClient> signedInClient({
    List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[],
  }) async {
    calls = <_Call>[];

    final SupabaseClient client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      httpClient: MockClient((http.Request request) async {
        if (request.url.path.contains('/auth/v1/token')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': _jwt('user-1'),
              'token_type': 'bearer',
              'expires_in': 3600,
              'refresh_token': 'refresh',
              'user': <String, dynamic>{
                'id': 'user-1',
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'someone@example.com',
                'created_at': '2026-01-01T00:00:00Z',
                'app_metadata': <String, dynamic>{},
                'user_metadata': <String, dynamic>{},
              },
            }),
            200,
            request: request,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
          );
        }

        calls.add(_Call(request.url, request.method, request.body));

        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: const <String, String>{
            'content-type': 'application/json',
            'content-range': '0-0/*',
          },
        );
      }),
    );

    await client.auth.setSession('refresh');
    return client;
  }

  Meal meal() => Meal(
        id: 'meal-1',
        creatorId: 'user-1',
        title: 'Anabolic Rigatoni',
        totals: const Macros(
          calories: 820.4,
          proteinG: 55.6,
          carbsG: 90.2,
          fatG: 22.9,
        ),
        createdAt: DateTime(2026, 8, 20),
      );

  group('which day a log lands on', () {
    test('sends the local calendar day, not a UTC timestamp', () async {
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      // A local date with no time on it. If the repository converted to UTC,
      // anyone east of Greenwich would see this become the 3rd.
      await repo.logMeal(meal: meal(), day: DateTime(2026, 9, 4, 21, 30));

      final Map<String, dynamic> body =
          jsonDecode(calls.single.body) as Map<String, dynamic>;

      expect(body['log_date'], '2026-09-04');
      // Specifically not an ISO timestamp: the column is a DATE, and sending
      // a time lets Postgres do the truncation with its own timezone rather
      // than the user's.
      expect(body['log_date'], isNot(contains('T')));
      expect(body['log_date'], isNot(contains('Z')));
    });

    test('pads single-digit months and days', () async {
      // '2026-1-5' is not a date Postgres accepts, and the failure would be a
      // 400 on the first of every month with a single-digit day.
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      await repo.logMeal(meal: meal(), day: DateTime(2026, 1, 5));

      final Map<String, dynamic> body =
          jsonDecode(calls.single.body) as Map<String, dynamic>;
      expect(body['log_date'], '2026-01-05');
    });

    test('reads back the same day it was asked for', () async {
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      await repo.fetchDayLog(DateTime(2026, 12, 25));

      expect(
        Uri.decodeFull(calls.single.url.toString()),
        contains('log_date=eq.2026-12-25'),
      );
    });
  });

  group('logging a meal', () {
    test('writes the macros the tracker will sum, rounded', () async {
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      await repo.logMeal(meal: meal(), slot: MealSlot.dinner);

      final Map<String, dynamic> body =
          jsonDecode(calls.single.body) as Map<String, dynamic>;

      expect(body['user_id'], 'user-1');
      expect(body['meal_id'], 'meal-1');
      expect(body['item_name'], 'Anabolic Rigatoni');
      expect(body['meal_type'], MealSlot.dinner.dbValue);
      // Rounded ints, not the raw doubles: these are what the day's totals are
      // added up from, and a column of 820.4000000001 helps nobody.
      expect(body['calories_logged'], 820);
      expect(body['protein_logged_g'], 56);
    });

    test('a meal with no weight records zero rather than null', () async {
      // Zero reads as "the whole meal, weight not recorded". The calorie
      // columns are the figures that matter; this one is only known for meals
      // built from weighed ingredients.
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      await repo.logMeal(meal: meal());

      final Map<String, dynamic> body =
          jsonDecode(calls.single.body) as Map<String, dynamic>;
      expect(body['quantity_g'], 0);
    });

    test('an unslotted entry sends a null slot rather than inventing one',
        () async {
      // The tracker shows these under a heading of their own. Guessing
      // "breakfast" would put food in a meal the user did not eat it at.
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      await repo.logMeal(meal: meal());

      final Map<String, dynamic> body =
          jsonDecode(calls.single.body) as Map<String, dynamic>;
      expect(body['meal_type'], isNull);
    });
  });

  group('reading a day', () {
    test('asks only for this user, in a stable order', () async {
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      await repo.fetchDayLog(DateTime(2026, 9, 4));

      final String url = Uri.decodeFull(calls.single.url.toString());
      expect(url, contains('/rest/v1/daily_logs'));
      expect(url, contains('user_id=eq.user-1'));
      // No time-of-day column exists, so this only has to be stable.
      // Insertion order is the closest thing to the order things were eaten.
      expect(url, contains('order=id.asc'));
    });

    test('maps rows into entries', () async {
      final SupabaseClient client = await signedInClient(
        rows: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 11,
            'user_id': 'user-1',
            'log_date': '2026-09-04',
            'meal_id': 'meal-1',
            'meal_type': 'dinner',
            'item_name': 'Anabolic Rigatoni',
            'quantity_g': 450,
            'calories_logged': 820,
            'protein_logged_g': 56,
            'carbs_logged_g': 90,
            'fat_logged_g': 23,
          },
        ],
      );
      final MealRepository repo = MealRepository(client: client);

      final List<DailyLogEntry> entries =
          await repo.fetchDayLog(DateTime(2026, 9, 4));

      expect(entries, hasLength(1));
      expect(entries.single.itemName, 'Anabolic Rigatoni');
      expect(entries.single.slot, MealSlot.dinner);
      expect(entries.single.macros.caloriesRounded, 820);
    });

    test('an empty day is an empty list, not an error', () async {
      final SupabaseClient client = await signedInClient();
      final MealRepository repo = MealRepository(client: client);

      expect(await repo.fetchDayLog(DateTime(2026, 9, 4)), isEmpty);
    });
  });

  group('signed out', () {
    // Every one of these begins `if (userId == null) return`. That is a
    // deliberate contract and not an accident, so it is worth a test: the
    // router should never let it happen, and if it does the app must not throw
    // on a screen the user can see.
    SupabaseClient anonymousClient() {
      calls = <_Call>[];
      return SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((http.Request request) async {
          calls.add(_Call(request.url, request.method, request.body));
          return http.Response('[]', 200,
              request: request,
              headers: const <String, String>{
                'content-type': 'application/json',
                'content-range': '0-0/*',
              });
        }),
      );
    }

    test('reading a day answers empty without asking the server', () async {
      final MealRepository repo = MealRepository(client: anonymousClient());

      expect(await repo.fetchDayLog(DateTime(2026, 9, 4)), isEmpty);
      expect(calls, isEmpty);
    });

    test('logging a meal writes nothing rather than throwing', () async {
      final MealRepository repo = MealRepository(client: anonymousClient());

      await expectLater(repo.logMeal(meal: meal()), completes);
      expect(calls, isEmpty);
    });

    test('the library is empty rather than an error', () async {
      final MealRepository repo = MealRepository(client: anonymousClient());

      expect(await repo.fetchLibrary(), isEmpty);
    });
  });
}

class _Call {
  _Call(this.url, this.method, this.body);

  final Uri url;
  final String method;
  final String body;
}

/// A structurally valid JWT. Not signed — nothing client-side verifies it, and
/// gotrue only needs to be able to parse it.
String _jwt(String subject) {
  String segment(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');

  final int expiry =
      DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;

  return '${segment(<String, dynamic>{'alg': 'HS256', 'typ': 'JWT'})}'
      '.${segment(<String, dynamic>{
        'sub': subject,
        'exp': expiry,
        'role': 'authenticated',
      })}'
      '.signature';
}
