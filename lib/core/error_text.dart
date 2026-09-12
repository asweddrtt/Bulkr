import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'moderation_error.dart';
import 'plan_limit_error.dart';

/// What kind of failure this was, coarsely enough to act on.
///
/// The categories are chosen to be the ones where the *answer* differs. There
/// is no point separating a 500 from a 502 when the user does the same thing
/// about both; there is every point separating either from being offline,
/// because one is worth retrying now and the other is not.
enum FailureKind {
  /// No usable connection. `SocketException`, a DNS failure, a dropped TLS
  /// handshake.
  offline,

  /// A connection that did not answer in time.
  timeout,

  /// Row-level security said no — SQLSTATE 42501. Almost always a policy that
  /// has not been applied rather than anything the user did, which is why the
  /// code rides along in debug.
  permission,

  /// The moderation trigger refused a blocked term, or the on-device model
  /// refused an image. Not a fault: an answer.
  refused,

  /// A free account has filled up one of its ceilings.
  ///
  /// Separate from [permission] on purpose. Both arrive from Postgres saying
  /// no, and they need opposite responses: a permission failure is a bug
  /// nobody holding the phone can act on, and this is a sentence with an
  /// obvious next step. Telling somebody they lack permission to save their
  /// twenty-first meal would be both wrong and insulting.
  planLimit,

  /// The row is gone, or was never there.
  notFound,

  /// The server answered, and the answer was an error.
  server,

  /// Everything else, including anything this function has not learned to
  /// recognise yet.
  unknown,
}

/// A failure, classified once, for the three places that need it.
///
/// Before this, every cubit carried its own private `_describe`. There were
/// fourteen of them, in four slightly different variants, and all of them
/// ended `return error.toString()` — so the user-visible text for being
/// offline was:
///
///     ClientException with SocketException: Failed host lookup:
///     'hqdfaeiyflbbzkduskaz.supabase.co' … uri=https://…/rest/v1/posts?select=…
///
/// which names the backend, reads like a crash, and tells somebody on a train
/// nothing they can act on.
@immutable
class DescribedFailure {
  const DescribedFailure({
    required this.kind,
    required this.technical,
    this.code,
    this.refusal,
  });

  final FailureKind kind;

  /// The original, unabridged. For logs, for Crashlytics, and for the debug
  /// build's on-screen detail — never shown to a user in release.
  final String technical;

  /// SQLSTATE, or an HTTP status, when there was one.
  final String? code;

  /// The exact sentence to show, when the failure carries its own — a blocked
  /// term's refusal comes from the database, and the image refusal is built
  /// from a translation key. Overrides [messageKey] when present.
  final String? refusal;

  /// The translation key for what the user is told.
  String get messageKey => switch (kind) {
        FailureKind.offline => 'error_offline',
        FailureKind.timeout => 'error_timeout',
        FailureKind.permission => 'error_permission',
        FailureKind.notFound => 'error_not_found',
        FailureKind.server => 'error_server',
        FailureKind.refused => 'error_generic',
        // Never reached in practice — a plan limit always carries its own
        // sentence — but a fallback that said "something went wrong" would be
        // the wrong shape if one ever arrived without a hint.
        FailureKind.planLimit => 'error_generic',
        FailureKind.unknown => 'error_generic',
      };

  /// Whether trying the same thing again in a moment could work.
  bool get isRetryable =>
      kind == FailureKind.offline ||
      kind == FailureKind.timeout ||
      kind == FailureKind.server;

  /// What the user reads.
  ///
  /// In a release build this is the translated sentence and nothing else. In a
  /// debug build the technical detail is appended, because the person looking
  /// at a debug build is the person who wants it — and because the previous
  /// behaviour, useful to exactly one developer, was being shown to everybody.
  String get message {
    final String friendly = refusal ?? messageKey.tr();
    if (!kDebugMode) return friendly;

    final String detail = [code, technical].whereType<String>().join(' · ');
    return detail.isEmpty ? friendly : '$friendly\n\n$detail';
  }

  @override
  String toString() => 'DescribedFailure($kind, ${code ?? '-'}, $technical)';
}

/// Classifies [error].
///
/// Ordered most-specific first, and the moderation checks come before the
/// generic Postgres formatting deliberately: a blocked term is an answer to
/// give, and `(BLKR1)` appended to it is not an improvement.
DescribedFailure describeFailure(Object error) {
  final String? blocked = blockedTermRefusal(error);
  if (blocked != null) {
    return DescribedFailure(
      kind: FailureKind.refused,
      technical: '$error',
      code: blockedTermSqlState,
      refusal: blocked,
    );
  }

  final PlanLimit? limit = planLimitReached(error);
  if (limit != null) {
    return DescribedFailure(
      kind: FailureKind.planLimit,
      technical: '$error',
      code: planLimitSqlState,
      refusal: planLimitMessage(limit),
    );
  }

  final String? explicit = explicitImageRefusal(error);
  if (explicit != null) {
    return DescribedFailure(
      kind: FailureKind.refused,
      technical: '$error',
      refusal: explicit,
    );
  }

  if (error is TimeoutException) {
    return DescribedFailure(kind: FailureKind.timeout, technical: '$error');
  }

  // The two shapes of "no network" that actually reach us. `http`'s wrapper is
  // the common one, because it is what Supabase's own client throws; the bare
  // SocketException arrives from the direct Open Food Facts calls.
  if (error is SocketException ||
      error is http.ClientException ||
      error is HandshakeException) {
    return DescribedFailure(
      kind: FailureKind.offline,
      technical: '$error',
    );
  }

  if (error is PostgrestException) {
    return DescribedFailure(
      kind: _fromSqlState(error.code),
      technical: error.message,
      code: error.code,
    );
  }

  if (error is StorageException) {
    return DescribedFailure(
      kind: error.statusCode == '404'
          ? FailureKind.notFound
          : FailureKind.server,
      technical: error.message,
      code: error.statusCode,
    );
  }

  if (error is AuthException) {
    return DescribedFailure(
      kind: FailureKind.server,
      technical: error.message,
      code: error.statusCode,
    );
  }

  return DescribedFailure(kind: FailureKind.unknown, technical: '$error');
}

/// What the user is told, in one call, for the common case.
///
/// Replaces the fourteen private `_describe` methods. Keeping the same shape —
/// `Object` in, `String` out — is what made replacing them a one-line change
/// per cubit rather than a rewrite of every error path.
String describeError(Object error) => describeFailure(error).message;

FailureKind _fromSqlState(String? code) => switch (code) {
      // Row-level security refused it. In practice this is nearly always a
      // policy file that has not been run rather than a user doing something
      // they should not — see the notes in supabase/README.md.
      '42501' => FailureKind.permission,
      'PGRST301' || '401' || '403' => FailureKind.permission,
      // PostgREST's "no rows returned" for a `.single()` that found nothing.
      'PGRST116' || '404' => FailureKind.notFound,
      // A connection that died mid-request surfaces here rather than as a
      // SocketException, because PostgREST has already wrapped it.
      '08000' || '08006' || '57014' => FailureKind.offline,
      null => FailureKind.unknown,
      _ => FailureKind.server,
    };
