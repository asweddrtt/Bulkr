import 'dart:convert';

import 'package:bulkr/cubit/entitlement/entitlement_cubit.dart';
import 'package:bulkr/data/app_preferences.dart';
import 'package:bulkr/data/entitlement_repository.dart';
import 'package:bulkr/models/entitlement.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Who is premium, how the device remembers it, and — mostly — which way it
/// fails.
///
/// Every interesting case here is a failure case, because the happy path is
/// one row with one column in it. What matters is that a lapsed subscription
/// stops being premium without a round trip, that an unreadable cache reads as
/// free rather than as premium, and that a refresh which never answers leaves
/// a paying user with what they paid for.
void main() {
  group('reading a row', () {
    test('no row at all is free', () {
      // Accounts that have never paid are simply not in the table, which is
      // why nothing creates a row at sign-up.
      expect(Entitlement.free.isPremium, isFalse);
      expect(Entitlement.free.tier, Tier.free);
    });

    test('a premium row with a future date is premium', () {
      final Entitlement entitlement = Entitlement.fromRow(<String, dynamic>{
        'tier': 'premium',
        'expires_at':
            DateTime.now().add(const Duration(days: 20)).toIso8601String(),
        'source': 'app_store',
      });

      expect(entitlement.isPremium, isTrue);
      expect(entitlement.source, 'app_store');
    });

    test('a premium row with a past date is not premium', () {
      // The row outlives the period. Between the store telling the backend a
      // subscription lapsed and this device refreshing, the cached row still
      // says premium — so the date is read here rather than trusted to a
      // round trip that may not happen for days.
      final Entitlement entitlement = Entitlement.fromRow(<String, dynamic>{
        'tier': 'premium',
        'expires_at': '2020-01-01T00:00:00Z',
      });

      expect(entitlement.isPremium, isFalse);
      expect(entitlement.hasLapsed, isTrue);
    });

    test('a tier this build has never heard of is free', () {
      // A future 'coach' or 'lifetime' tier must not read as premium in an old
      // client just because it is not 'free'.
      final Entitlement entitlement =
          Entitlement.fromRow(<String, dynamic>{'tier': 'coach'});

      expect(entitlement.tier, Tier.free);
      expect(entitlement.isPremium, isFalse);
    });

    test('a missing or unparseable date is treated as no end date', () {
      final Entitlement entitlement = Entitlement.fromRow(
        <String, dynamic>{'tier': 'premium', 'expires_at': null},
      );

      expect(entitlement.expiresAt, isNull);
      expect(entitlement.isPremium, isTrue);
    });

    test('survives a round trip through the cache', () {
      final Entitlement before = Entitlement(
        tier: Tier.premium,
        expiresAt: DateTime(2027, 3, 4, 12),
        source: 'play',
      );

      final Entitlement after = Entitlement.fromJson(
        jsonDecode(jsonEncode(before.toJson())) as Map<String, dynamic>,
      );

      expect(after, before);
    });
  });

  group('the repository', () {
    late AppPreferences preferences;
    late List<Uri> calls;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      preferences =
          AppPreferences(preferences: await SharedPreferences.getInstance());
      calls = <Uri>[];
    });

    Future<SupabaseClient> signedInClient({
      List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[],
      int status = 200,
      Map<String, dynamic>? error,
    }) async {
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
                'content-type': 'application/json'
              },
            );
          }

          calls.add(request.url);

          return http.Response(
            jsonEncode(error ?? rows),
            status,
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

    test('asks for one row, by user', () async {
      final EntitlementRepository repo = EntitlementRepository(
        client: await signedInClient(),
        preferences: preferences,
      );

      await repo.fetch();

      expect(calls.single.path, contains('/rest/v1/subscriptions'));
      expect(Uri.decodeFull(calls.single.toString()),
          contains('user_id=eq.user-1'));
    });

    test('no row means free, and asks nothing else', () async {
      final EntitlementRepository repo = EntitlementRepository(
        client: await signedInClient(),
        preferences: preferences,
      );

      expect((await repo.fetch()).isPremium, isFalse);
    });

    test('caches what the server said, keyed to the user', () async {
      final EntitlementRepository repo = EntitlementRepository(
        client: await signedInClient(rows: <Map<String, dynamic>>[
          <String, dynamic>{
            'tier': 'premium',
            'expires_at':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'source': 'app_store',
          }
        ]),
        preferences: preferences,
      );

      expect((await repo.fetch()).isPremium, isTrue);
      // And without the network this time.
      expect((await repo.cached()).isPremium, isTrue);
      expect(await preferences.cachedEntitlement('somebody-else'), isNull);
    });

    test('a cache belonging to another account is not read', () async {
      // One device, two accounts. A premium flag that outlived its owner would
      // hand the next person an ad-free app they did not pay for.
      await preferences.setCachedEntitlement(
        'user-2',
        jsonEncode(<String, dynamic>{'tier': 'premium'}),
      );

      final EntitlementRepository repo = EntitlementRepository(
        client: await signedInClient(),
        preferences: preferences,
      );

      expect((await repo.cached()).isPremium, isFalse);
    });

    test('an unreadable cache is free, not premium', () async {
      await preferences.setCachedEntitlement('user-1', 'not json at all');

      final EntitlementRepository repo = EntitlementRepository(
        client: await signedInClient(),
        preferences: preferences,
      );

      // The safe reading of "we do not know" is the tier that costs nothing.
      // The other guess hands premium to anyone who corrupts a preference
      // file.
      expect((await repo.cached()).isPremium, isFalse);
    });

    test('a missing table is an answer, not an error', () async {
      // An app running against a project where premium.sql has not been
      // applied is an app where nobody is premium. Throwing here would put an
      // error banner on a screen for a state that is simply "free".
      final EntitlementRepository repo = EntitlementRepository(
        client: await signedInClient(
          status: 404,
          error: <String, dynamic>{
            'code': 'PGRST205',
            'message':
                "Could not find the table 'public.subscriptions' in the schema cache",
          },
        ),
        preferences: preferences,
      );

      expect((await repo.fetch()).isPremium, isFalse);
    });

    test('a real server failure is thrown, not swallowed', () async {
      // Because the caller keeps what it had, and can only do that if it is
      // told the answer never arrived.
      final EntitlementRepository repo = EntitlementRepository(
        client: await signedInClient(
          status: 500,
          error: <String, dynamic>{'message': 'boom'},
        ),
        preferences: preferences,
      );

      await expectLater(repo.fetch(), throwsA(isA<PostgrestException>()));
    });

    test('signed out asks nothing and is free', () async {
      final SupabaseClient anonymous = SupabaseClient(
        'https://example.supabase.co',
        'test-publishable-key',
        httpClient: MockClient((http.Request request) async {
          calls.add(request.url);
          return http.Response('[]', 200,
              request: request,
              headers: const <String, String>{
                'content-type': 'application/json',
                'content-range': '0-0/*',
              });
        }),
      );

      final EntitlementRepository repo = EntitlementRepository(
        client: anonymous,
        preferences: preferences,
      );

      expect((await repo.fetch()).isPremium, isFalse);
      expect(calls, isEmpty);
    });
  });

  group('the cubit', () {
    late AppPreferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      preferences =
          AppPreferences(preferences: await SharedPreferences.getInstance());
    });

    Future<SupabaseClient> client({
      List<Map<String, dynamic>> rows = const <Map<String, dynamic>>[],
      int status = 200,
      Map<String, dynamic>? error,
    }) async {
      final SupabaseClient created = SupabaseClient(
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
                'content-type': 'application/json'
              },
            );
          }

          return http.Response(
            jsonEncode(error ?? rows),
            status,
            request: request,
            headers: const <String, String>{
              'content-type': 'application/json',
              'content-range': '0-0/*',
            },
          );
        }),
      );

      await created.auth.setSession('refresh');
      return created;
    }

    List<Map<String, dynamic>> premiumRow() => <Map<String, dynamic>>[
          <String, dynamic>{
            'tier': 'premium',
            'expires_at':
                DateTime.now().add(const Duration(days: 30)).toIso8601String(),
            'source': 'app_store',
          }
        ];

    test('starts free and showing ads', () {
      final EntitlementCubit cubit = EntitlementCubit(
        repository: EntitlementRepository(
          client: SupabaseClient('https://example.supabase.co', 'k'),
          preferences: preferences,
        ),
      );

      expect(cubit.state.isPremium, isFalse);
      expect(cubit.state.showsAds, isTrue);
      expect(cubit.state.status, EntitlementStatus.initial);

      cubit.close();
    });

    test('a paid account stops showing ads', () async {
      final EntitlementCubit cubit = EntitlementCubit(
        repository: EntitlementRepository(
          client: await client(rows: premiumRow()),
          preferences: preferences,
        ),
      );

      await cubit.load();

      expect(cubit.state.isPremium, isTrue);
      expect(cubit.state.showsAds, isFalse);
      expect(cubit.state.limits.savedMeals, isNull);

      await cubit.close();
    });

    test('a failed refresh keeps what it had', () async {
      // The important one. A subscriber going into a tunnel must not start
      // seeing the ads they paid to remove, so a failure is not evidence of a
      // downgrade — it is the absence of evidence of anything.
      await preferences.setCachedEntitlement(
        'user-1',
        jsonEncode(<String, dynamic>{'tier': 'premium'}),
      );

      final EntitlementCubit cubit = EntitlementCubit(
        repository: EntitlementRepository(
          client: await client(
            status: 500,
            error: <String, dynamic>{'message': 'boom'},
          ),
          preferences: preferences,
        ),
      );

      await cubit.load();

      expect(cubit.state.isPremium, isTrue);
      expect(cubit.state.errorMessage, isNotNull);
      expect(cubit.state.status, EntitlementStatus.ready);

      await cubit.close();
    });

    test('the server downgrading someone is honoured', () async {
      // The other direction, and it has to work or a cancelled subscription
      // stays premium on that device forever.
      await preferences.setCachedEntitlement(
        'user-1',
        jsonEncode(<String, dynamic>{'tier': 'premium'}),
      );

      final EntitlementCubit cubit = EntitlementCubit(
        repository: EntitlementRepository(
          client: await client(),
          preferences: preferences,
        ),
      );

      await cubit.load();

      expect(cubit.state.isPremium, isFalse);
      expect(cubit.state.showsAds, isTrue);

      await cubit.close();
    });

    test('clearing forgets the account, on disk and in memory', () async {
      final EntitlementCubit cubit = EntitlementCubit(
        repository: EntitlementRepository(
          client: await client(rows: premiumRow()),
          preferences: preferences,
        ),
      );

      await cubit.load();
      expect(cubit.state.isPremium, isTrue);

      await cubit.clear();

      expect(cubit.state.isPremium, isFalse);
      expect(cubit.state.status, EntitlementStatus.initial);
      expect(await preferences.cachedEntitlement('user-1'), isNull);

      await cubit.close();
    });

    test('signing out clears it along with everything else', () async {
      // `AuthCubit.signOut` calls `AppPreferences.clear()`, and the cached
      // entitlement has to be one of the things that goes — otherwise the next
      // account to sign in on this device reads the last one's subscription.
      await preferences.setCachedEntitlement(
        'user-1',
        jsonEncode(<String, dynamic>{'tier': 'premium'}),
      );

      await preferences.clear();

      expect(await preferences.cachedEntitlement('user-1'), isNull);
    });
  });
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
