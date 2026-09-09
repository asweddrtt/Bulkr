import 'package:flutter/foundation.dart';
import 'package:nsfw_detector_flutter/nsfw_detector_flutter.dart';

/// Thrown when a picked image looks explicit and was not uploaded.
///
/// Its own type rather than a generic failure: every caller shows a different
/// surface, and "we could not upload that" is the wrong sentence for "we are
/// not going to".
class ExplicitImageException implements Exception {
  const ExplicitImageException(this.score);

  /// What the model scored it, 0 to 1. Logged, never shown — a number invites
  /// somebody to find the edge of it.
  final double score;

  @override
  String toString() => 'Image scored $score and was refused';
}

/// Checks a picked image before it is uploaded, on the device, for free.
///
/// On-device and pre-upload on purpose. Nothing leaves the phone, nothing is
/// billed, and an explicit image is never written to storage at all — so there
/// is no window where it exists at a public URL, and no pending state for the
/// post to sit in.
///
/// It is bypassable. A modified client can skip this, which is true of every
/// client-side check ever written; it is a filter on accidents and on the
/// casually antisocial, and reports plus blocking remain the answer to somebody
/// determined. That is the trade for "free, forever, no account".
abstract final class ImageSafety {
  /// The score above which an image is refused.
  ///
  /// **Calibrate this against real progress photos before trusting it.** The
  /// bundled model is Yahoo's open_nsfw, whose own default is 0.7, and it is
  /// sensitive to bare skin — which in an app whose best content is a shirtless
  /// physique shot is precisely the wrong sensitivity. 0.7 would refuse posts
  /// this app exists to collect.
  ///
  /// 0.92 is deliberately near the top: a miss shows up as one bad post that
  /// reports and blocking then handle, while a false positive shows up as a
  /// user who cannot post their progress and concludes the app is broken. The
  /// asymmetry is not close.
  ///
  /// This is a Dart constant with no asset behind it, so moving it after
  /// testing on real photos is a Shorebird patch rather than a build.
  static const double threshold = 0.92;

  /// Refuses an explicit image, and lets everything else through.
  ///
  /// Throws [ExplicitImageException] only when the model is confident. Every
  /// other outcome — model missing, decode failure, an unsupported platform,
  /// anything at all — allows the upload and says so in the log.
  ///
  /// That direction is chosen, not lazy. Fail-closed here means one bad model
  /// load turns "post a photo" into a feature that does not work, for
  /// everybody, with no error anybody can act on. A moderation check that can
  /// take the app down with it is worse than the content it was added to catch.
  static Future<void> refuseIfExplicit(Uint8List bytes) async {
    if (bytes.isEmpty) return;

    final NsfwResult? result;
    try {
      // Off the UI thread. It reloads the model per call, which costs a few
      // hundred milliseconds and keeps nothing resident afterwards — the right
      // trade for something that runs when a person picks a photo, not in a
      // loop.
      result = await NsfwDetector.detectBytesInBackground(
        bytes,
        threshold: threshold,
      );
    } catch (error) {
      debugPrint(
        'Bulkr: image check unavailable, allowing the upload — $error',
      );
      return;
    }

    // Null means the bytes were not a decodable image. Storage will take it or
    // reject it on its own merits; this is not the place to decide that.
    if (result == null) return;

    debugPrint('Bulkr: image scored ${result.score.toStringAsFixed(3)}.');

    if (isExplicit(result.score)) throw ExplicitImageException(result.score);
  }

  /// Whether a score is refused, as a pure function so it can be tested.
  ///
  /// `NsfwResult.isNsfw` is not used: it is computed against the threshold
  /// handed to the detector, and depending on a second copy of that decision
  /// means two places to change and one of them forgotten.
  static bool isExplicit(double score) => score >= threshold;
}
