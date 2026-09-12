/// Where the privacy policy and terms actually live.
///
/// Separate from [SupabaseConfig] because these are not connection settings —
/// they are a publishing decision, and they change without the backend
/// changing.
///
/// ## Why this is empty by default
///
/// Because the alternative is worse. The welcome screen used to render
///
///     BY CONTINUING YOU AGREE TO THE Policy
///
/// with `Policy` underlined, inside a plain `RichText` with no recogniser and
/// no URL. It looked like a link, it was not one, and there was nothing behind
/// it to read — so the app asked for agreement to a document that did not
/// exist.
///
/// A wrong URL would be the same failure with extra steps: a 404 is not a
/// privacy policy. So the default is empty, [hasPrivacyPolicy] is false, and
/// the screen renders the sentence without pretending any of it is tappable.
/// The moment a real URL is set, the link becomes a link.
///
/// ## This has to be set before the App Store sees it
///
/// Guideline 5.1.1 requires a reachable privacy policy, and the sign-up screen
/// is where review looks for it. An app that collects an email address, body
/// measurements, photos and messages — and, since this release, analytics —
/// will not pass without one.
///
/// Set at build time, so it can change without a code change:
///
///   flutter build ipa --dart-define=PRIVACY_POLICY_URL=https://...
///
/// or edit the defaults below, which is what `codemagic.yaml` would then not
/// have to carry.
class LegalConfig {
  const LegalConfig._();

  /// The privacy policy. Required before release — see above.
  static const String privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
  );

  /// Terms of service. Optional: Apple requires a privacy policy and accepts
  /// the standard EULA in place of custom terms, so this stays empty until
  /// there is something to point it at.
  static const String termsUrl = String.fromEnvironment('TERMS_URL');

  /// The support address App Store guideline 1.2 asks a user-generated-content
  /// app for, alongside the reporting and blocking the app already has.
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@bulkr.app',
  );

  static bool get hasPrivacyPolicy => _isUsable(privacyPolicyUrl);

  static bool get hasTerms => _isUsable(termsUrl);

  /// An `https` URL and nothing else.
  ///
  /// Checked rather than trusted, because this arrives from a `--dart-define`
  /// on a build machine — a typo there is not a compile error, and the failure
  /// it causes is a link that silently does nothing, which is the exact bug
  /// this file exists to remove.
  static bool _isUsable(String value) {
    if (value.isEmpty) return false;
    final Uri? parsed = Uri.tryParse(value);
    return parsed != null && parsed.isScheme('https') && parsed.host.isNotEmpty;
  }
}
