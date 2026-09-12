import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/analytics_events.dart';
import '../core/image_resize.dart';
import '../core/moderation_error.dart';
import '../core/telemetry.dart';

/// Asks the server whether a picture belongs on the feed.
///
/// Replaces the on-device model, which did not work on either platform: on iOS
/// it scored a full nude below a topless photo, and on Android its model 404s
/// so it never ran at all. Both stories are in [ImageSafety].
///
/// ## Why the server
///
/// The AWS credentials cannot ship in the binary, which is reason enough. The
/// better reason is that the *decision* now lives somewhere a patched client
/// cannot reach, and the policy behind it —
/// `supabase/functions/moderate-image/policy.ts` — can be changed without an
/// app release. The old threshold was a Dart constant; moving it took a
/// Shorebird patch and reached only phones that took the patch.
///
/// ## What it throws
///
/// [ExplicitImageException], the same type the on-device check threw. That is
/// deliberate and is what made this a small change: `describeFailure` already
/// maps it to `FailureKind.refused`, `explicitImageRefusal` already turns it
/// into a sentence, and every composer, meal editor and avatar picker already
/// shows that sentence. The verdict changed; nothing downstream had to.
class ModerationService {
  ModerationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const String functionName = 'moderate-image';

  /// How long a caller waits before the upload proceeds unchecked.
  ///
  /// A person is watching a spinner with their finger on Post, so this is much
  /// shorter than the model download it replaces. Rekognition typically
  /// answers in a few hundred milliseconds; past this, something is wrong.
  static const Duration timeout = Duration(seconds: 12);

  /// Refuses an explicit image, and lets everything else through.
  ///
  /// Throws [ExplicitImageException] when the server says no. Every other
  /// outcome — offline, a 502, a timeout, a function that was never deployed —
  /// allows the upload and says so loudly.
  ///
  /// That direction is unchanged from the on-device check and chosen for the
  /// same reason: fail-closed means one bad network moment turns "post a
  /// photo" into a feature that does not work, for everybody. The difference
  /// is that a failure here is now *rare and visible* rather than universal
  /// and silent — see `moderation_unavailable` in the dashboard.
  Future<void> refuseIfExplicit(Uint8List bytes) async {
    if (bytes.isEmpty) return;

    final Stopwatch elapsed = Stopwatch()..start();

    final _Verdict verdict;
    try {
      verdict = await _ask(bytes).timeout(timeout);
    } on ExplicitImageException {
      // The refusal itself, thrown from inside `_ask`. Not a failure to
      // report — it is the answer, and it must not be swallowed by the catch
      // below that exists for infrastructure problems.
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('Bulkr: moderation unavailable, upload allowed — $error');

      unawaited(Telemetry.send(AnalyticsEvent.imageCheckDidNotRun(
        reason: error is TimeoutException ? 'timeout' : 'unavailable',
      )));
      unawaited(Telemetry.recordError(error, stackTrace,
          reason: 'moderating an image'));
      return;
    }

    debugPrint(
      'Bulkr: moderation ${verdict.verdict} in ${elapsed.elapsedMilliseconds}ms '
      '(${verdict.observed.join(', ')})',
    );
  }

  /// One round trip. Throws [ExplicitImageException] on a refusal.
  Future<_Verdict> _ask(Uint8List bytes) async {
    // A 640px copy rather than the original, and the original is still what
    // gets uploaded — this rendering exists only to be looked at. Three
    // reasons, in the order they matter:
    //
    //   1. Rekognition refuses inline bytes over 5 MB and a modern phone photo
    //      goes well past that.
    //   2. Somebody is watching a spinner. A 6 MB round trip on a phone
    //      connection is the difference between a pause and a hang.
    //   3. Moderation models see a few hundred pixels anyway, so the extra
    //      resolution buys no accuracy — it only costs time.
    //
    // `thumbnail` rather than a new resize path: it already runs on a
    // background isolate, already returns null instead of throwing on an image
    // it cannot read, and is already tested. It answers null when the picture
    // is *already* under 640px, which is why the fallback is the original
    // bytes rather than a failure.
    final Uint8List? small = await ImageResize.thumbnail(bytes);
    final Uint8List payload = small ?? bytes;

    final FunctionResponse response = await _client.functions.invoke(
      functionName,
      body: <String, dynamic>{'image': base64Encode(payload)},
    );

    final Object? data = response.data;
    if (data is! Map) {
      throw StateError('moderation returned ${response.status}: $data');
    }

    if (data['error'] != null) {
      throw StateError('moderation returned ${data['error']}');
    }

    final List<String> observed = <String>[
      for (final Object? entry in (data['observed'] as List<Object?>? ?? const []))
        if (entry is Map && entry['name'] != null)
          '${entry['name']} ${(((entry['confidence'] as num?) ?? 0) * 100).round()}%',
    ];

    final String verdict = '${data['verdict']}';
    final double confidence = ((data['confidence'] as num?) ?? 0).toDouble();
    final String? reason = data['reason'] as String?;

    if (verdict == 'refuse') {
      unawaited(Telemetry.send(AnalyticsEvent.imageRefused(
        score: confidence,
        // The label that caused it, not a number. This is the whole reason
        // Rekognition was chosen over a scalar — a dashboard that says
        // "Exposed Male Genitalia 97%" is actionable, "adult: LIKELY" is not.
        threshold: 0,
        variant: reason ?? 'unknown',
      )));

      throw ExplicitImageException(confidence, label: reason);
    }

    unawaited(Telemetry.send(AnalyticsEvent.imageAllowed(
      score: confidence,
      variant: observed.isEmpty ? 'clean' : 'reviewed',
    )));

    return _Verdict(verdict: verdict, observed: observed);
  }
}

@immutable
class _Verdict {
  const _Verdict({required this.verdict, required this.observed});

  final String verdict;
  final List<String> observed;
}
