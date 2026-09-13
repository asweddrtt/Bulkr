import 'package:equatable/equatable.dart';

/// Why a typed email or password cannot be used.
///
/// Checked on the device before anything is sent, for one reason: a round trip
/// to be told "that is not an email address" is a round trip, and on a bad
/// connection it is several seconds of a spinner to learn something the app
/// already knew.
///
/// It is *not* a security boundary. Supabase enforces its own password policy
/// server-side, and that is the rule; this is the courtesy.
enum CredentialProblem {
  emailEmpty,
  emailMalformed,
  passwordEmpty,
  passwordTooShort,
  passwordTooSimple,
  passwordMismatch,
}

/// An email and password pair, validated.
class EmailCredentials extends Equatable {
  const EmailCredentials({required this.email, required this.password});

  /// Trimmed and lower-cased.
  ///
  /// Both matter. A keyboard that capitalises the first letter is the default
  /// on every phone, and `Ali@x.com` signing up then `ali@x.com` signing in is
  /// a support ticket that reads as "it forgot my account" — Postgres compares
  /// the stored address exactly.
  final String email;

  /// Never trimmed. A leading or trailing space is a legitimate character in a
  /// password, and silently removing one means the password that worked at
  /// sign-up fails at sign-in.
  final String password;

  factory EmailCredentials.from({
    required String email,
    required String password,
  }) => EmailCredentials(email: email.trim().toLowerCase(), password: password);

  /// The shortest password Bulkr accepts.
  ///
  /// Eight rather than Supabase's default six. The server is the real rule and
  /// is more permissive, which is the right way round: a client stricter than
  /// the server can only ever refuse something that would have worked, never
  /// accept something that will not.
  static const int minPasswordLength = 8;

  /// Whether [value] is plausibly an email address.
  ///
  /// Deliberately loose. The full grammar in RFC 5322 admits quoted strings,
  /// comments and addresses nobody has ever typed, and every regex claiming to
  /// implement it rejects somebody's real address. The only check worth making
  /// here is the one that catches a typo — something before an `@`, something
  /// after it, and a dot in the domain — because the address is confirmed by
  /// an email arriving, which is the only test that actually proves anything.
  static bool looksLikeEmail(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.contains(' ')) return false;

    return RegExp(r'^[^@]+@[^@.]+(\.[^@.]+)+$').hasMatch(trimmed);
  }

  /// What is wrong with signing in with these, or null when nothing is.
  ///
  /// Sign-in checks less than sign-up on purpose: an existing account may have
  /// a password shorter than today's minimum, and refusing to *let them in*
  /// because the rules tightened would lock out the people who joined earliest.
  CredentialProblem? get signInProblem {
    if (email.isEmpty) return CredentialProblem.emailEmpty;
    if (!looksLikeEmail(email)) return CredentialProblem.emailMalformed;
    if (password.isEmpty) return CredentialProblem.passwordEmpty;
    return null;
  }

  /// What is wrong with creating an account with these, or null.
  CredentialProblem? signUpProblem({String? confirmation}) {
    final CredentialProblem? basics = signInProblem;
    if (basics != null) return basics;

    if (password.length < minPasswordLength) {
      return CredentialProblem.passwordTooShort;
    }

    // A letter and a digit. Not a menu of symbols and cases — those rules push
    // people towards `Password1!`, which is worse than a long simple one, and
    // the length check above is doing most of the work.
    final bool hasLetter = password.contains(RegExp(r'[A-Za-z]'));
    final bool hasDigit = password.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasDigit) return CredentialProblem.passwordTooSimple;

    if (confirmation != null && confirmation != password) {
      return CredentialProblem.passwordMismatch;
    }

    return null;
  }

  /// Whether an address on its own is usable — for the reset form, which has
  /// no password field.
  static CredentialProblem? resetProblem(String email) {
    final String trimmed = email.trim();
    if (trimmed.isEmpty) return CredentialProblem.emailEmpty;
    if (!looksLikeEmail(trimmed)) return CredentialProblem.emailMalformed;
    return null;
  }

  /// The translation key for [problem].
  static String messageKey(CredentialProblem problem) => switch (problem) {
    CredentialProblem.emailEmpty => 'auth_email_required',
    CredentialProblem.emailMalformed => 'auth_email_malformed',
    CredentialProblem.passwordEmpty => 'auth_password_required',
    CredentialProblem.passwordTooShort => 'auth_password_short',
    CredentialProblem.passwordTooSimple => 'auth_password_simple',
    CredentialProblem.passwordMismatch => 'auth_password_mismatch',
  };

  @override
  List<Object?> get props => <Object?>[email, password];
}
