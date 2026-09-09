import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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

/// One rendering of a picked image, and what the model said about it.
///
/// Exists so the decision below is made over a list rather than over one
/// number, and so the log can say which rendering produced the score. Both
/// matter: see [ImageSafety.channelOrderIsUnverified].
@immutable
class _Variant {
  const _Variant(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
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
/// The first version used `nsfw_detector_flutter`, which wraps
/// `tflite_flutter`, which resolves TensorFlow Lite's C API at runtime with
/// `dlsym`. On a device that build did nothing at all:
///
///     dlsym(RTLD_DEFAULT, TfLiteModelCreate): symbol not found
///
/// The framework was never in the process, so every call threw and every call
/// was then allowed by the fail-open branch below. `nsfw_detect` needs no
/// third-party native library: its iOS side is Swift calling Vision and Core
/// ML, frameworks that ship with the OS and link at build time, so there is no
/// symbol to look up and nothing to fail to find.
abstract final class ImageSafety {
  /// The score above which an image is refused.
  ///
  /// **Not yet calibrated against real photos.** 0.92 was tried and let an
  /// actual nude through; 0.75 was tried and let explicit content through
  /// while refusing a topless shot — which is not a threshold being too high,
  /// it is scores that do not mean much yet. See
  /// [channelOrderIsUnverified] for the suspected reason.
  ///
  /// It stays at 0.75 until there are real numbers to move it with. Picking a
  /// third number from intuition is how the first two were picked.
  ///
  /// A Dart constant with no asset behind it, so moving it is a Shorebird
  /// patch rather than a build.
  static const double threshold = 0.75;

  /// Whether a refusal shows the score that caused it.
  ///
  /// On while [threshold] is being calibrated. A refused image is the only
  /// moment the number reaches somebody who can report it, and there is no
  /// other way to read one off a phone.
  static const bool showScoreInRefusal = true;

  /// The edge length the model actually sees.
  ///
  /// OpenNSFW2 takes a 224x224 image. Left to itself the plugin hands Vision
  /// the full picture with `.scaleFit`; preparing the input here instead means
  /// the two renderings below differ *only* in channel order, which is the
  /// whole point of comparing them.
  static const int inputEdge = 224;

  /// Why every image is scored twice.
  ///
  /// The bundled `OpenNSFW2.mlmodelc` declares its input as an **RGB** image
  /// and bakes in a per-channel bias of −104, −117, −123. Those are Yahoo's
  /// open_nsfw means, and in open_nsfw they apply to **BGR** — the reference
  /// preprocessing reverses the channels before subtracting. Nothing in the
  /// model's op list reverses them back.
  ///
  /// So either the conversion folded the swap into the first convolution, or
  /// red and blue reach the network transposed. Which of those is true decides
  /// whether the scores mean anything, and it cannot be settled by reading the
  /// weights.
  ///
  /// So it is settled by measurement instead: the image is scored in both
  /// channel orders and the higher score wins. Whichever order is correct, the
  /// correct one is in the set, and the log names the one that fired. Two
  /// scans of a 224x224 buffer cost a few milliseconds — cheap enough that
  /// resolving this by experiment beats resolving it by argument.
  ///
  /// Once the log shows one order consistently doing the work, this drops to a
  /// single scan in a patch.
  static const bool channelOrderIsUnverified = true;

  /// Refuses an explicit image, and lets everything else through.
  ///
  /// Throws [ExplicitImageException] only when the model is confident. Every
  /// other outcome — model missing, decode failure, an unsupported platform,
  /// anything at all — allows the upload and says so in the log.
  ///
  /// That direction is chosen, not lazy. Fail-closed here means one bad model
  /// load turns "post a photo" into a feature that does not work, for
  /// everybody, with no error anybody can act on.
  ///
  /// It is also the branch that hid the broken TFLite build for a whole
  /// release, which is why the log lines below say the check did not run
  /// rather than implying the image was fine.
  static Future<void> refuseIfExplicit(Uint8List bytes) async {
    if (bytes.isEmpty) return;

    final List<_Variant> variants = await _prepare(bytes);

    double worst = 0;
    String worstName = 'none';
    int scored = 0;

    for (final _Variant variant in variants) {
      final double? score = await _score(variant);
      if (score == null) continue;

      scored++;
      debugPrint(
        'Bulkr: nudity check ${variant.name} scored '
        '${score.toStringAsFixed(3)}.',
      );

      if (score > worst) {
        worst = score;
        worstName = variant.name;
      }
    }

    if (scored == 0) {
      // Every rendering failed to score. Nothing was measured, so nothing is
      // concluded — but this is the silent-failure case that cost a release,
      // so it is loud.
      debugPrint(
        'Bulkr: nudity check produced no score at all, so the upload was '
        'allowed. The model did not run.',
      );
      return;
    }

    debugPrint(
      'Bulkr: nudity check worst was $worstName at ${worst.toStringAsFixed(3)} '
      '(threshold $threshold).',
    );

    if (isExplicit(worst)) throw ExplicitImageException(worst);
  }

  /// Scores one rendering, or null when it could not be scored.
  static Future<double?> _score(_Variant variant) async {
    final ScanResult result;
    try {
      result = await NsfwDetector.instance.scanBytes(
        variant.bytes,
        confidenceThreshold: threshold,
      );
    } catch (error) {
      debugPrint('Bulkr: nudity check ${variant.name} threw — $error');
      return null;
    }

    if (result.status != ScanStatus.completed) {
      // `failed` is a native error — no model, an undecodable buffer.
      // `skipped` is configuration or a cache hit carrying no labels. Neither
      // is a verdict, so neither is treated as one.
      debugPrint(
        'Bulkr: nudity check ${variant.name} came back '
        '${result.status.name} — ${result.errorMessage ?? 'no reason given'}',
      );
      return null;
    }

    return scoreOf(result);
  }

  /// The renderings to score, most likely to work first.
  ///
  /// Falls back to the original bytes untouched when they cannot be decoded —
  /// which is the pre-existing behaviour, so a format this cannot read is no
  /// worse off than before.
  static Future<List<_Variant>> _prepare(Uint8List bytes) async {
    final List<Uint8List>? prepared = await compute(_renderVariants, bytes);

    if (prepared == null || prepared.length != 2) {
      debugPrint(
        'Bulkr: nudity check could not re-render the image, scanning it as '
        'picked.',
      );
      return <_Variant>[_Variant('as-picked', bytes)];
    }

    return <_Variant>[
      _Variant('rgb', prepared[0]),
      _Variant('channels-swapped', prepared[1]),
    ];
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
}

/// Builds the two renderings, on a background isolate.
///
/// Top-level because `compute` needs it to be. Returns `[rgb, swapped]`, or
/// null when the bytes are not an image this can read.
///
/// Both are PNG rather than JPEG: they are already down to 224x224, so the
/// bytes are small either way, and a lossy re-encode at the exact size the
/// network reads would be noise added directly to the thing being measured.
List<Uint8List>? _renderVariants(Uint8List bytes) {
  try {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // The whole frame, squashed to square. Not a centre crop: a crop drops the
    // edges of the picture, and an image is not safe because the explicit part
    // of it was near a border.
    final img.Image small = img.copyResize(
      decoded,
      width: ImageSafety.inputEdge,
      height: ImageSafety.inputEdge,
    );

    return <Uint8List>[
      img.encodePng(small),
      img.encodePng(swapRedAndBlue(small)),
    ];
  } catch (_) {
    return null;
  }
}

/// A copy of [source] with its red and blue channels exchanged.
///
/// Public and tested because it is the kind of loop that silently does
/// nothing: `image` hands out a `Pixel` that is a cursor over the underlying
/// buffer rather than a copy, so whether these assignments reach the bytes is
/// a property of that package and not something to take on trust. A no-op here
/// would leave two identical renderings being scored twice and look, from
/// every log line, exactly like the experiment having been run.
@visibleForTesting
img.Image swapRedAndBlue(img.Image source) {
  final img.Image swapped = source.clone();

  for (final img.Pixel pixel in swapped) {
    final num red = pixel.r;
    pixel.r = pixel.b;
    pixel.b = red;
  }

  return swapped;
}
