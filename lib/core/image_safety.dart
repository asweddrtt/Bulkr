import 'package:flutter/foundation.dart';
import 'package:nsfw_detect/nsfw_detect.dart';

/// Thrown when a picked image looks explicit and was not uploaded.
///
/// Its own type rather than a generic failure: every caller shows a different
/// surface, and "we could not upload that" is the wrong sentence for "we are
/// not going to".
class ExplicitImageException implements Exception {
  const ExplicitImageException(this.score);

  /// What the model scored it, 0 to 1.
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
///
/// ## Why this runs through Core ML rather than TensorFlow Lite
///
/// The first version of this used `nsfw_detector_flutter`, which wraps
/// `tflite_flutter`, which finds TensorFlow Lite's C API at runtime with
/// `dlsym`. On a device that build did nothing at all:
///
///     Failed to lookup symbol 'TfLiteModelCreate':
///     dlsym(RTLD_DEFAULT, TfLiteModelCreate): symbol not found
///
/// The TensorFlowLiteC framework was never in the process, so every call threw
/// and every call was then allowed by the fail-open branch below — a nude was
/// published while the check was, from the outside, "installed and working".
///
/// `nsfw_detect` needs no third-party native library. Its iOS side is Swift
/// calling Vision and Core ML — frameworks that ship with the OS and are
/// linked at build time, so there is no symbol to look up and nothing to fail
/// to find — against an OpenNSFW2 model compiled into the plugin's own bundle.
/// The entire failure mode above cannot recur.
abstract final class ImageSafety {
  /// The score above which an image is refused.
  ///
  /// The model is OpenNSFW2 — Yahoo's open_nsfw, converted to Core ML — and it
  /// is sensitive to bare skin, which in an app whose best content is a
  /// shirtless physique shot is precisely the wrong sensitivity. The package's
  /// own default is 0.7; 0.75 sits just above it, close enough to catch what
  /// the model is sure about with a little room left for progress photos.
  ///
  /// The asymmetry behind erring high: a miss is one bad post that reports and
  /// blocking then handle, a false positive is somebody who cannot post their
  /// progress and concludes the app is broken. 0.92 was tried and bought so
  /// much of one side that it caught nothing at all.
  ///
  /// This is a Dart constant with no asset behind it, so moving it after
  /// testing on real photos is a Shorebird patch rather than a build.
  static const double threshold = 0.75;

  /// Refuses an explicit image, and lets everything else through.
  ///
  /// Throws [ExplicitImageException] only when the model is confident. Every
  /// other outcome — model missing, decode failure, an unsupported platform,
  /// anything at all — allows the upload and says so in the log.
  ///
  /// That direction is chosen, not lazy. Fail-closed here means one bad model
  /// load turns "post a photo" into a feature that does not work, for
  /// everybody, with no error anybody can act on. A moderation check that can
  /// take the app down with it is worse than the content it was added to
  /// catch.
  ///
  /// It is also the branch that hid the broken TFLite build for a whole
  /// release, which is why the log line below names the check rather than the
  /// upload, and why it says the check did not run rather than that the image
  /// was fine.
  static Future<void> refuseIfExplicit(Uint8List bytes) async {
    if (bytes.isEmpty) return;

    final ScanResult result;
    try {
      // The threshold is handed over as well, so `result.confidenceThreshold`
      // agrees with ours if anything ever reads it. The decision below is
      // still made here — see [scoreOf].
      result = await NsfwDetector.instance.scanBytes(
        bytes,
        confidenceThreshold: threshold,
      );
    } catch (error) {
      debugPrint(
        'Bulkr: nudity check did not run, so the upload was allowed — $error',
      );
      return;
    }

    if (result.status != ScanStatus.completed) {
      // `failed` is a native error — no model, an undecodable buffer. `skipped`
      // is configuration or a cache hit that carried no labels. Neither is a
      // verdict, so neither is treated as one.
      debugPrint(
        'Bulkr: nudity check returned ${result.status.name}, so the upload was '
        'allowed — ${result.errorMessage ?? 'no reason given'}',
      );
      return;
    }

    final double score = scoreOf(result);

    // Every image, allowed or not. Three different outcomes look identical
    // from outside the app — a score under the threshold, a model that did not
    // load, and a phone still running an older build — and only a number
    // separates them.
    debugPrint('Bulkr: nudity check scored ${score.toStringAsFixed(3)}.');

    if (isExplicit(score)) throw ExplicitImageException(score);
  }

  /// How explicit the model thought the image was, 0 to 1.
  ///
  /// The highest confidence across both unsafe categories rather than
  /// `ScanResult.isNsfw`. That getter answers only when an unsafe category is
  /// also the *top* label, so an image the model called 0.8 nudity and 0.81
  /// safe reads as safe — which is not the call this app wants to make, and is
  /// invisible from the outside because it returns a plain bool.
  ///
  /// Pure, and separate from the platform call, so the decision this feature
  /// turns on is testable without a device.
  static double scoreOf(ScanResult result) {
    final double nudity = result.confidenceFor(NsfwCategory.nudity);
    final double explicit = result.confidenceFor(NsfwCategory.explicitNudity);
    return nudity > explicit ? nudity : explicit;
  }

  /// Whether a score is refused, as a pure function so it can be tested.
  static bool isExplicit(double score) => score >= threshold;

  /// Whether a refusal shows the score that caused it.
  ///
  /// On while [threshold] is being calibrated. A refused image is the only
  /// event that carries useful information — "0.99" means the model was
  /// certain, "0.76" means the threshold is sitting on top of the physique
  /// shots this app exists to collect — and there is no other way to read it
  /// off a phone.
  ///
  /// A Dart constant, so turning it off once the number is settled is a
  /// Shorebird patch rather than a build.
  static const bool showScoreInRefusal = true;
}
