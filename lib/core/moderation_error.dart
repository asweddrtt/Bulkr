import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The SQLSTATE `supabase/moderation_terms.sql` raises when a post or comment
/// contains a blocked term.
///
/// A code rather than a message match: the wording of the refusal can be
/// improved without silently turning this check into a no-op, which is what
/// matching on `error.message` would do the first time somebody reworded it.
const String blockedTermSqlState = 'BLKR1';

/// The refusal to show the author, or null when this is some other failure.
///
/// The text comes from the database rather than the translation file, and that
/// is a deliberate trade with a shelf life: it means adding this needs no new
/// translation key, which is what lets it reach phones as a Shorebird patch
/// instead of waiting for a store build. The moment Bulkr has a second locale
/// this has to move into `en-US.json` and its siblings — until then, an
/// English-only app reading an English string from Postgres costs nothing.
///
/// Deliberately does not say which word was refused. The author knows what they
/// typed, and naming the term is a hint for getting the next one through.
String? blockedTermRefusal(Object error) {
  if (error is! PostgrestException) return null;
  if (error.code != blockedTermSqlState) return null;

  // The trigger raises a message and a hint; both are written to be read by
  // whoever is holding the phone. The prefix is for the Postgres log, where
  // there is no other clue which application raised it, and is noise here.
  final String message = error.message.replaceFirst(RegExp(r'^Bulkr:\s*'), '');
  final String? hint = error.hint?.trim();

  if (hint == null || hint.isEmpty) return message;
  return '$message $hint';
}

/// Thrown when a picked image was refused and not uploaded.
///
/// Its own type rather than a generic failure: every caller shows a different
/// surface, and "we could not upload that" is the wrong sentence for "we are
/// not going to".
///
/// Carries what the server said for the log and for Crashlytics. Neither field
/// is ever shown to the person holding the phone — see [explicitImageRefusal].
class ExplicitImageException implements Exception {
  const ExplicitImageException(this.score, {this.label});

  /// How confident the model was, 0 to 1.
  final double score;

  /// The label that caused it — `Exposed Male Genitalia`, and so on.
  ///
  /// Null when the refusal came from somewhere that does not name one. This is
  /// most of why Rekognition was chosen over a scalar: a log line naming the
  /// label is something a person can act on and argue with, where a bare 0.97
  /// is not.
  final String? label;

  @override
  String toString() =>
      'Image refused${label == null ? '' : ' as $label'} at $score';
}

/// The refusal to show when a picked image was judged explicit.
///
/// A real translation key rather than a string from the database, unlike
/// [blockedTermRefusal]: the moderation policy now lives in an edge function
/// and changes without an app release either way, so there is nothing to buy
/// by keeping this one patch-shaped.
///
/// Deliberately carries no score and no label. An earlier version appended
/// `(scored 0.812, threshold 0.75)` while the on-device threshold was being
/// calibrated, which meant a false positive on somebody's progress photo
/// showed them a number they could not act on and read as the app
/// malfunctioning. The numbers go to analytics now, where they are useful.
String? explicitImageRefusal(Object error) {
  if (error is! ExplicitImageException) return null;

  return 'image_explicit_refused'.tr();
}
