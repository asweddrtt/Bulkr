import 'dart:math';

/// Builds a `users.username` candidate.
///
/// The column is `VARCHAR(50) UNIQUE NOT NULL` but nothing in the onboarding
/// flow asks the user for a handle and no OAuth provider supplies one, so we
/// derive a starting point from whatever identity we do have. The user can
/// overwrite it on screen 2.
class UsernameGenerator {
  UsernameGenerator({Random? random}) : _random = random ?? Random();

  final Random _random;

  static const int maxLength = 50;

  /// Reserved so a generated suffix always fits: '_' + 4 chars.
  static const int _suffixLength = 4;

  static const String _suffixAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// Derives a handle from the provider's display name, falling back to the
  /// email local-part, then to a generic stem.
  String suggest({String? displayName, String? email}) {
    final fromName = slugify(displayName ?? '');
    if (fromName.isNotEmpty) return fromName;

    final localPart = (email ?? '').split('@').first;
    final fromEmail = slugify(localPart);
    if (fromEmail.isNotEmpty) return fromEmail;

    return withSuffix('bulkr');
  }

  /// Lowercases, replaces runs of non-alphanumerics with a single underscore,
  /// and trims to what the column can hold.
  ///
  /// Returns an empty string when the input has nothing usable in it — for
  /// instance a display name written entirely in a non-Latin script — so
  /// callers can fall through to the next source.
  static String slugify(String input) {
    final lowered = input.toLowerCase().trim();
    final replaced = lowered.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final trimmed = replaced.replaceAll(RegExp(r'^_+|_+$'), '');
    if (trimmed.isEmpty) return '';
    return trimmed.length <= maxLength ? trimmed : trimmed.substring(0, maxLength);
  }

  /// Appends a short random suffix, trimming the stem first so the result
  /// still fits inside [maxLength].
  String withSuffix(String base) {
    final suffix = List.generate(
      _suffixLength,
      (_) => _suffixAlphabet[_random.nextInt(_suffixAlphabet.length)],
    ).join();

    final room = maxLength - _suffixLength - 1;
    final stem = base.length <= room ? base : base.substring(0, room);
    return '${stem}_$suffix';
  }

  /// True when [value] could be stored in the column and is worth showing to
  /// another human. Screen 2 uses this for inline validation.
  static bool isValid(String value) {
    if (value.length < 3 || value.length > maxLength) return false;
    return RegExp(r'^[a-z0-9_]+$').hasMatch(value);
  }
}
