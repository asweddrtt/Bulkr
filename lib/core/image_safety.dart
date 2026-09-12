import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:nsfw_detect/nsfw_detect.dart';

import 'analytics_events.dart';
import 'config/moderation_config.dart';
import 'telemetry.dart';

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
///
/// ## How Android runs the same check
///
/// Worth spelling out, because the section above is about iOS and reads as
/// though it covered both — which is how Android ended up not running this
/// check at all for its entire existence.
///
/// The model id is the same on both platforms: `opennsfw2_coreml`. The name is
/// misleading — it identifies *the model*, not a format — and the plugin
/// registers a different engine against it per platform. On iOS that is Core
/// ML reading `OpenNSFW2.mlmodelc`, bundled inside the pod. On Android it is
/// TensorFlow Lite reading `OpenNSFW2.tflite`, which is **not** bundled: the
/// plugin's Android descriptor carries a `downloadUrl` instead, so
/// `requiresDownload` is true and the file has to be fetched once.
///
/// Nothing used to fetch it. So on Android the load threw `ModelNotFound`,
/// [_score] returned null for every rendering, `scored` was zero, and
/// [refuseIfExplicit] allowed the upload — the fail-open branch behaving
/// exactly as designed, and indistinguishable from outside from a model that
/// was working. Which is precisely the shape of the TensorFlow Lite bug above.
///
/// [ensureModelReady] is the fix: it downloads the model once, caches the
/// in-flight fetch so concurrent posts share it, and is awaited by
/// [refuseIfExplicit] before anything is scored. [warmUp] starts it when a
/// photo is picked, so the download overlaps with the user writing their post
/// and has usually finished before they press Post.
///
/// ## What still fails open, and why it is not silent
///
/// A first post on a phone with no connection, or a download that times out,
/// still ends in an allowed upload. That direction is deliberate and unchanged
/// — fail-closed would mean one bad network moment turns "post a photo" into a
/// feature that does not work.
///
/// What has changed is that it is now loud and rare rather than quiet and
/// universal: `AnalyticsEvent.imageCheckDidNotRun` fires with
/// `reason=model_unavailable`, and `moderation_model_failed` carries whether it
/// was a timeout or an error. If those counts are not near zero, Android
/// moderation is not working and the dashboard says so.
///
/// See [ModerationConfig] for why the download URL is worth pointing at
/// something you control.
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
  /// **Off.** It was on while the threshold was being calibrated, because a
  /// refused image was the only moment the number reached somebody who could
  /// report it and there was no other way to read one off a phone.
  ///
  /// There is now. Every score goes to analytics — refusals *and* allowances,
  /// see [refuseIfExplicit] — so the distribution can be read off a dashboard
  /// instead of off a stranger's screenshot. The number no longer has to
  /// be shown to the person it was refused to, who cannot act on it and reads
  /// `(scored 0.812, threshold 0.75)` as the app malfunctioning.
  static const bool showScoreInRefusal = false;

  /// The model both platforms score against.
  ///
  /// Passed explicitly to every scan rather than left to the plugin's default,
  /// which happens to be this same id. The id reads as iOS-only — it is
  /// literally `opennsfw2_coreml` — but it is the identifier for *the model*,
  /// not for a format: the plugin registers a Core ML engine against it on
  /// iOS and a TensorFlow Lite engine against it on Android. Naming it here
  /// is what stops the next reader concluding, as this file previously did,
  /// that Android has no model to run.
  static const String modelId = ModelIds.openNsfw2;

  /// Whether the model must be fetched before the first scan.
  ///
  /// True on Android only. See [ensureModelReady].
  static bool get modelNeedsFetching {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  /// How long a scan will wait for the model to arrive.
  ///
  /// Generous, because it is only ever paid once per install and the
  /// alternative is a check that does not run. Short enough that somebody on a
  /// dead connection is not held at a spinner indefinitely — past this the
  /// upload proceeds unchecked, and says so.
  static const Duration fetchTimeout = Duration(seconds: 45);

  /// The in-flight or completed fetch, so concurrent callers share one
  /// download rather than starting four.
  ///
  /// Cleared on failure: a phone that was offline when it first tried to post
  /// must be able to try again, and caching `false` forever would turn one bad
  /// moment into a permanently disabled check.
  static Future<bool>? _fetch;

  /// Makes the model available, and answers whether it is.
  ///
  /// Idempotent and safe to call from anywhere — the composer calls it when a
  /// photo is picked so the download overlaps with the user typing, and
  /// [refuseIfExplicit] calls it again as the backstop.
  ///
  /// Never throws. A model that cannot be fetched is a check that does not
  /// run; it is not a reason the app cannot post.
  static Future<bool> ensureModelReady() {
    if (!modelNeedsFetching) return Future<bool>.value(true);
    return _fetch ??= _fetchModel();
  }

  static Future<bool> _fetchModel() async {
    final Stopwatch elapsed = Stopwatch()..start();

    try {
      // A mirror we control, when one is configured. Set before `ensureReady`
      // because the plugin persists it and reads it when resolving the
      // descriptor's download URL — see [ModerationConfig] for why the
      // default is worth replacing.
      if (ModerationConfig.hasMirror) {
        await NsfwDetector.instance
            .setModelUrl(modelId, ModerationConfig.modelUrl);
      }

      // Downloads if missing, then loads it into the interpreter. Returns
      // once it is genuinely usable rather than once the bytes have landed.
      await NsfwDetector.instance.models
          .ensureReady(modelId)
          .timeout(fetchTimeout);

      debugPrint(
        'Bulkr: nudity model ready after ${elapsed.elapsedMilliseconds}ms.',
      );
      unawaited(Telemetry.send(AnalyticsEvent.moderationModelReady(
        milliseconds: elapsed.elapsedMilliseconds,
        mirrored: ModerationConfig.hasMirror,
      )));
      return true;
    } catch (error, stackTrace) {
      // Cleared so the next attempt actually retries.
      _fetch = null;

      debugPrint('Bulkr: nudity model could not be fetched — $error');
      unawaited(Telemetry.send(AnalyticsEvent.moderationModelFailed(
        kind: error is TimeoutException ? 'timeout' : 'error',
        milliseconds: elapsed.elapsedMilliseconds,
      )));
      // Recorded rather than only counted: this is the one failure that turns
      // moderation off, and the exception says whether it was the network,
      // the URL, or the archive.
      unawaited(Telemetry.recordError(error, stackTrace,
          reason: 'fetching the nudity model'));
      return false;
    }
  }

  /// Starts the fetch without waiting for it.
  ///
  /// For the moment a photo is picked: the download and the user composing
  /// their post then happen at the same time, so by the time they hit Post the
  /// model is usually already there and the check costs nothing visible.
  static void warmUp() {
    if (!modelNeedsFetching) return;
    unawaited(ensureModelReady());
  }

  /// Forgets the cached fetch. For tests.
  @visibleForTesting
  static void resetModelForTest() => _fetch = null;

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
  ///
  /// Left on. Unlike [showScoreInRefusal] this is not a calibration aid the
  /// user can see — it is a correctness hedge, and turning it off means
  /// *choosing* a channel order, which is the thing that cannot yet be done
  /// honestly. What has changed is how it gets resolved: the winning variant
  /// now rides on every `image_refused` and `image_allowed` event, so the
  /// answer arrives as a distribution over real photos rather than by reading
  /// the weights.
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

    // Android fetches the model on first use. Awaited here rather than only
    // warmed up at pick time, because the warm-up is an optimisation and this
    // is the guarantee: without it, the very first photo on a fresh install
    // would always go up unchecked — which is exactly what was happening to
    // every photo on every Android install.
    if (!await ensureModelReady()) {
      debugPrint(
        'Bulkr: nudity model unavailable, so the upload was allowed without '
        'a check.',
      );
      unawaited(Telemetry.send(AnalyticsEvent.imageCheckDidNotRun(
        reason: 'model_unavailable',
      )));
      return;
    }

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
      // so it is loud in both directions: the console for whoever is holding
      // the phone, and analytics for the far more common case of nobody being
      // there at all.
      debugPrint(
        'Bulkr: nudity check produced no score at all, so the upload was '
        'allowed. The model did not run.',
      );
      unawaited(Telemetry.send(AnalyticsEvent.imageCheckDidNotRun(
        // A category, not the exception text: on Android this is the known
        // missing-model case described on the class, and everywhere else it
        // is worth telling apart from it.
        reason: _platformLabel,
      )));
      return;
    }

    debugPrint(
      'Bulkr: nudity check worst was $worstName at ${worst.toStringAsFixed(3)} '
      '(threshold $threshold).',
    );

    // Sent for allowed images too, and that is deliberate. A threshold cannot
    // be judged from refusals alone: refusals are the complaints, and the
    // false *negatives* — the explicit image that scored 0.7 and went up — are
    // the half that never complains. Only both halves make a distribution.
    if (isExplicit(worst)) {
      unawaited(Telemetry.send(AnalyticsEvent.imageRefused(
        score: worst,
        threshold: threshold,
        variant: worstName,
      )));
      throw ExplicitImageException(worst);
    }

    unawaited(Telemetry.send(AnalyticsEvent.imageAllowed(
      score: worst,
      variant: worstName,
    )));
  }

  /// Which platform a missing score came from.
  ///
  /// Android is expected to be missing today — see the note on this class — so
  /// separating it is what stops the expected case from hiding an unexpected
  /// one on iOS, where the model is bundled and a failure means something has
  /// actually broken.
  static String get _platformLabel {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android_no_model';
    if (Platform.isIOS) return 'ios_unexpected';
    return 'other';
  }

  /// Scores one rendering, or null when it could not be scored.
  static Future<double?> _score(_Variant variant) async {
    final ScanResult result;
    try {
      result = await NsfwDetector.instance.scanBytes(
        variant.bytes,
        // Named rather than defaulted: the plugin's default happens to be the
        // same id today, and a silent change to it would turn this check into
        // a different model's opinion without anything here saying so.
        modelId: modelId,
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
