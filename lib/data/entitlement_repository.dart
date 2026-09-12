import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entitlement.dart';
import 'app_preferences.dart';

/// What the signed-in user has paid for.
///
/// One row, read rarely — at launch, on sign-in, and when coming back from the
/// store — and cached on the device in between. There is no write here at all,
/// because there is no write policy: `subscriptions` is service-role-only, and
/// a purchase becomes premium by way of a store notification reaching the
/// backend, never by the app asking to be upgraded. See `supabase/premium.sql`.
class EntitlementRepository {
  EntitlementRepository({SupabaseClient? client, AppPreferences? preferences})
    : _client = client ?? Supabase.instance.client,
      _preferences = preferences ?? AppPreferences();

  final SupabaseClient _client;
  final AppPreferences _preferences;

  /// Long enough for a cold start on a bad connection, short enough that the
  /// app is not waiting on a subscription check to decide whether to draw a
  /// banner. Nothing user-facing blocks on this — the cache answers first.
  static const Duration timeout = Duration(seconds: 8);

  String? get _userId => _client.auth.currentUser?.id;

  /// The last answer this device was given, without asking the network.
  ///
  /// Free when there is nothing cached, when the cache belongs to a different
  /// account, or when it cannot be parsed. Every one of those is "we do not
  /// know", and the safe reading of not knowing is the tier that costs
  /// nothing — the opposite guess hands out premium to anyone who corrupts a
  /// preference file.
  Future<Entitlement> cached() async {
    final String? userId = _userId;
    if (userId == null) return Entitlement.free;

    final String? raw = await _preferences.cachedEntitlement(userId);
    if (raw == null) return Entitlement.free;

    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return Entitlement.free;

      return Entitlement.fromJson(decoded);
    } catch (error) {
      debugPrint('Bulkr: cached entitlement unreadable — $error');
      return Entitlement.free;
    }
  }

  /// Asks the server, and remembers the answer.
  ///
  /// No row means free: an account that has never paid is simply not in the
  /// table, which is why nothing creates a row at sign-up.
  ///
  /// Throws on a real failure — offline, a policy problem — so the caller can
  /// decide whether to keep showing what it had. It does *not* throw when the
  /// table is missing, because an app running against a project where
  /// `premium.sql` has not been applied yet is an app where nobody is premium,
  /// and that is an answer rather than an error.
  Future<Entitlement> fetch() async {
    final String? userId = _userId;
    if (userId == null) return Entitlement.free;

    late final Map<String, dynamic>? row;
    try {
      row = await _client
          .from('subscriptions')
          .select('tier, expires_at, source, product_id')
          .eq('user_id', userId)
          .maybeSingle()
          .timeout(timeout);
    } on PostgrestException catch (error) {
      if (_isMissingTable(error)) {
        debugPrint(
          'Bulkr: no subscriptions table — everyone is free. '
          'Apply supabase/premium.sql.',
        );
        return Entitlement.free;
      }
      rethrow;
    }

    final Entitlement entitlement = row == null
        ? Entitlement.free
        : Entitlement.fromRow(row);

    await _remember(userId, entitlement);
    return entitlement;
  }

  /// Forgets what this device knew. Called on sign-out, alongside the rest of
  /// [AppPreferences.clear].
  Future<void> forget() => _preferences.clearEntitlement();

  Future<void> _remember(String userId, Entitlement entitlement) async {
    try {
      await _preferences.setCachedEntitlement(
        userId,
        jsonEncode(entitlement.toJson()),
      );
    } catch (error) {
      // A cache that cannot be written costs a network round trip next launch
      // and nothing else.
      debugPrint('Bulkr: could not cache entitlement — $error');
    }
  }

  /// Whether this failure means the table is not there.
  ///
  /// Two codes say it — `42P01` from Postgres, and `PGRST205` from PostgREST's
  /// own schema cache, which is the one that actually comes back — and the
  /// message has to be checked as well as the code, because the code is not
  /// always where it ends up. A 404 from PostgREST arrives with `code` set to
  /// the HTTP status and the whole JSON error body left in `message`, so
  /// matching on `code` alone would let a missing table through as a hard
  /// failure and put an error on a screen for a state that is simply "nobody
  /// is premium".
  static bool _isMissingTable(PostgrestException error) {
    if (error.code == '42P01' || error.code == 'PGRST205') return true;

    final String message = error.message;
    if (message.contains('PGRST205') || message.contains('42P01')) return true;

    return message.contains('subscriptions') &&
        (message.contains('does not exist') ||
            message.contains('Could not find the table'));
  }
}
