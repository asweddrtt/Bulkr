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
