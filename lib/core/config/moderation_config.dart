/// Where the on-device nudity model comes from on Android.
///
/// ## Why this exists at all
///
/// On iOS the model is bundled: `OpenNSFW2.mlmodelc` ships inside the
/// `nsfw_detect` pod, so there is nothing to fetch and nothing to configure.
///
/// Android is different and it is not obvious from the outside. The plugin's
/// Android descriptor for the same model id carries a `downloadUrl` instead of
/// an asset, so `requiresDownload` is true and the model has to be fetched
/// once before the first scan can run. Until it is, every scan fails, and
/// `ImageSafety` allows the upload — which is how the check managed to be
/// completely absent on Android while looking, from the code, like it was
/// running everywhere.
///
/// ## Why you probably want to set [modelUrl]
///
/// The plugin's default points at a GitHub release in a third-party
/// repository:
///
///     github.com/nexas105/flutter_nsfw_scaner/releases/.../OpenNSFW2.tflite.zip
///
/// Two problems with leaning on that for a moderation feature:
///
///   1. **It is not ours.** If that repository is renamed, the release
///      deleted, or the asset replaced, Android moderation stops working — and
///      it stops working silently, in the fail-open direction.
///   2. **It is not verified.** The plugin supports pinning a SHA-256 on a
///      descriptor and its own comment says to "pin this for any URL the
///      integrator does not fully control" — but the built-in OpenNSFW2
///      descriptor leaves it null. So the bytes are trusted as they arrive.
///
/// Both are fixed the same way: put the file somewhere you control — the
/// Supabase project already has public Storage buckets — and point this at it.
/// The archive is ~11 MB and never changes, so it is a one-time upload.
///
///     flutter build appbundle \
///       --dart-define=NSFW_MODEL_URL=https://<project>.supabase.co/storage/v1/object/public/models/OpenNSFW2.tflite.zip
///
/// Left empty, the plugin's default is used and the check still works. This is
/// a supply-chain improvement, not a prerequisite.
class ModerationConfig {
  const ModerationConfig._();

  /// A mirror for the OpenNSFW2 TFLite archive. Empty means "use the
  /// plugin's default".
  static const String modelUrl = String.fromEnvironment('NSFW_MODEL_URL');

  /// Whether a mirror has been configured, and is a URL rather than a typo.
  ///
  /// Checked rather than trusted for the same reason [LegalConfig] checks its
  /// own: this arrives from a `--dart-define` on a build machine, where a
  /// mistake is not a compile error and the symptom is a feature that quietly
  /// stops working.
  static bool get hasMirror {
    if (modelUrl.isEmpty) return false;
    final Uri? parsed = Uri.tryParse(modelUrl);
    return parsed != null && parsed.isScheme('https') && parsed.host.isNotEmpty;
  }
}
