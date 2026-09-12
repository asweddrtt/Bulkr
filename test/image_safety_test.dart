import 'dart:typed_data';

import 'package:bulkr/core/config/moderation_config.dart';
import 'package:bulkr/core/image_safety.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nsfw_detect/nsfw_detect.dart';

/// The threshold, the score it is compared against, and the direction the
/// whole thing errs in.
///
/// OpenNSFW2 is Yahoo's open_nsfw and is sensitive to bare skin, which in an
/// app whose best content is a shirtless progress photo is exactly the wrong
/// sensitivity. These are the two decisions in this feature worth being
/// deliberate about, so they get tests rather than comments alone.
void main() {
  // Without a binding, `refuseIfExplicit` throws on the platform channel
  // before it reaches the model at all — and the two fail-open tests below
  // then pass for a reason that has nothing to do with fail-open. With it
  // initialized there genuinely is no Core ML on a Linux test host, which is
  // the same shape of failure a device hits when the model cannot load: the
  // real case that posture exists for.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  ScanResult resultWith(List<NsfwLabel> labels) => ScanResult(
        item: MediaItem.empty(),
        status: ScanStatus.completed,
        labels: labels,
        scannedAt: DateTime(2026),
        confidenceThreshold: ImageSafety.threshold,
      );

  test('refuses only what the model is confident about', () {
    expect(ImageSafety.isExplicit(1.0), isTrue);
    expect(
      ImageSafety.isExplicit(ImageSafety.threshold),
      isTrue,
      reason: 'the threshold itself is refused, not just above it',
    );
    expect(ImageSafety.isExplicit(ImageSafety.threshold - 0.001), isFalse);
  });

  test('a progress photo in the open_nsfw middle band is allowed', () {
    // The band a shirtless physique shot lands in. The package would call
    // anything from 0.7 NSFW, which would refuse posts this app exists to
    // collect.
    //
    // 0.85 used to be in this list, when the threshold was 0.92. It is not any
    // more, and that is the trade made deliberately rather than discovered
    // later: an actual nude went through at 0.92, so the ceiling came down and
    // a physique shot scoring 0.85 will now be refused. If real photos land
    // there the number moves again — with this list as the record of the cost.
    for (final double score in <double>[0.45, 0.6, 0.7, 0.74]) {
      expect(
        ImageSafety.isExplicit(score),
        isFalse,
        reason: '$score would have refused a legitimate progress photo',
      );
    }
  });

  test('the threshold errs towards letting things through', () {
    // Stated as a test so lowering it is a deliberate act with a failing test
    // attached, not a quiet edit. A miss is one bad post that reports and
    // blocking then handle; a false positive is a user who cannot post their
    // progress and concludes the app is broken.
    expect(
      ImageSafety.threshold,
      greaterThanOrEqualTo(0.7),
      reason: 'below the package default is the wrong side of the trade',
    );
    expect(
      ImageSafety.threshold,
      lessThan(1.0),
      reason: 'at 1.0 nothing is ever refused and the feature is decoration',
    );
  });

  test('the score is the unsafe label, not whichever label came first', () {
    // The reason `scoreOf` exists. `ScanResult.isNsfw` only answers true when
    // an unsafe category is also the *top* label, so this image — which the
    // model called 0.8 nudity — reads as safe there purely because `safe`
    // scored a hair higher.
    final ScanResult borderline = resultWith(const <NsfwLabel>[
      NsfwLabel(category: NsfwCategory.safe, confidence: 0.81),
      NsfwLabel(category: NsfwCategory.nudity, confidence: 0.8),
    ]);

    expect(
      borderline.isNsfw,
      isFalse,
      reason: 'the gap this exists to close — if this ever becomes true, '
          'scoreOf can be replaced by isNsfw',
    );
    expect(ImageSafety.scoreOf(borderline), 0.8);
    expect(ImageSafety.isExplicit(ImageSafety.scoreOf(borderline)), isTrue);
  });

  test('the score takes the highest of the two unsafe categories', () {
    expect(
      ImageSafety.scoreOf(resultWith(const <NsfwLabel>[
        NsfwLabel(category: NsfwCategory.nudity, confidence: 0.4),
        NsfwLabel(category: NsfwCategory.explicitNudity, confidence: 0.97),
      ])),
      0.97,
    );
    expect(
      ImageSafety.scoreOf(resultWith(const <NsfwLabel>[
        NsfwLabel(category: NsfwCategory.explicitNudity, confidence: 0.2),
        NsfwLabel(category: NsfwCategory.nudity, confidence: 0.9),
      ])),
      0.9,
    );
  });

  test('suggestive on its own does not count as explicit', () {
    // Curses are allowed in this app and so is a gym selfie. "Suggestive" is
    // the category a swimsuit lands in, and refusing it would refuse the
    // content the feed is for.
    final ScanResult suggestive = resultWith(const <NsfwLabel>[
      NsfwLabel(category: NsfwCategory.suggestive, confidence: 0.99),
      NsfwLabel(category: NsfwCategory.safe, confidence: 0.4),
    ]);

    expect(ImageSafety.scoreOf(suggestive), 0.0);
    expect(ImageSafety.isExplicit(ImageSafety.scoreOf(suggestive)), isFalse);
  });

  test('a scan with no labels scores zero rather than throwing', () {
    // What a `skipped` result or a cache hit with nothing in it looks like.
    expect(ImageSafety.scoreOf(resultWith(const <NsfwLabel>[])), 0.0);
  });

  group('the channel-order experiment', () {
    // The reason every image is scored twice: the bundled model declares an
    // RGB input but bakes in open_nsfw's BGR means, and nothing in it reverses
    // the channels back. Scoring both orders settles by measurement what
    // reading the weights cannot.
    //
    // If this swap silently did nothing, two identical renderings would be
    // scored twice and every log line would look exactly like the experiment
    // having been run. So it is tested for real.
    test('exchanges red and blue and leaves green alone', () {
      final img.Image source = img.Image(width: 2, height: 1);
      source.setPixelRgb(0, 0, 10, 20, 30);
      source.setPixelRgb(1, 0, 200, 100, 0);

      final img.Image swapped = swapRedAndBlue(source);

      expect(
        <num>[
          swapped.getPixel(0, 0).r,
          swapped.getPixel(0, 0).g,
          swapped.getPixel(0, 0).b,
        ],
        <num>[30, 20, 10],
      );
      expect(
        <num>[
          swapped.getPixel(1, 0).r,
          swapped.getPixel(1, 0).g,
          swapped.getPixel(1, 0).b,
        ],
        <num>[0, 100, 200],
      );
    });

    test('leaves the image it was given untouched', () {
      // The two renderings are scored one after the other, so mutating the
      // source in place would make the first one meaningless.
      final img.Image source = img.Image(width: 1, height: 1);
      source.setPixelRgb(0, 0, 10, 20, 30);

      swapRedAndBlue(source);

      expect(
        <num>[
          source.getPixel(0, 0).r,
          source.getPixel(0, 0).g,
          source.getPixel(0, 0).b,
        ],
        <num>[10, 20, 30],
      );
    });

    test('a grey image is its own swap, so it proves nothing on its own', () {
      // Worth stating: on a greyscale photo both renderings are identical and
      // the doubled scan is pure cost. It is the colour photos that carry the
      // signal, which is most of them.
      final img.Image grey = img.Image(width: 1, height: 1);
      grey.setPixelRgb(0, 0, 128, 128, 128);

      final img.Pixel swapped = swapRedAndBlue(grey).getPixel(0, 0);
      expect(<num>[swapped.r, swapped.g, swapped.b], <num>[128, 128, 128]);
    });
  });

  test('empty bytes are not an image and are not refused', () async {
    // Reached when a picker hands back nothing. It must not throw: the upload
    // that follows will fail on its own terms with a message that fits.
    await expectLater(ImageSafety.refuseIfExplicit(Uint8List(0)), completes);
  });

  test('an unavailable model allows the upload instead of blocking it', () async {
    // The whole posture of this check, and the case that actually happened on
    // a device: the model fails to load, so the check cannot answer. A
    // moderation step that can take "post a photo" down with it is worse than
    // the content it was added to catch.
    //
    // There is no Core ML on the test host, so this is that failure for real
    // rather than a stand-in for it.
    await expectLater(
      ImageSafety.refuseIfExplicit(Uint8List.fromList(<int>[1, 2, 3, 4])),
      completes,
    );
  });

  group('model readiness', _modelReadinessTests);
  group('where the model comes from', _modelSourceTests);
}

/// Making the check actually run on Android.
///
/// The model id is the same on both platforms, but only iOS bundles it: the
/// plugin's Android descriptor carries a `downloadUrl`, so `requiresDownload`
/// is true and the file has to be fetched once before anything can be scored.
/// Nothing fetched it. Every Android scan therefore threw `ModelNotFound`,
/// `scored` was zero, and the fail-open branch allowed the upload — so the
/// check was completely absent on that platform while looking, from this file,
/// like it ran everywhere.
///
/// These pin the parts of the fix that are decidable without a device. The
/// download itself needs a platform channel and a network, and neither exists
/// in a unit test — so what is checked here is the wiring around it: that a
/// scan cannot happen before the model is ready, that a failure is retried
/// rather than cached forever, and that concurrent posts share one download.
void _modelReadinessTests() {
  setUp(ImageSafety.resetModelForTest);

  test('the model id is the one the plugin registers on both platforms', () {
    // Reads as iOS-only and is not. If this ever stops matching the plugin's
    // id, Android silently falls back to "unknown model" and the check is off
    // again — which is the failure this whole group exists to prevent.
    expect(ImageSafety.modelId, ModelIds.openNsfw2);
  });

  test('a host with no fetching required is ready immediately', () async {
    // The Linux test host is not Android, so this takes the bundled path and
    // must not attempt a download or a platform call.
    expect(ImageSafety.modelNeedsFetching, isFalse);
    expect(await ImageSafety.ensureModelReady(), isTrue);
  });

  test('warming up is safe to call when nothing needs fetching', () {
    // Called from ImageSourceSheet on every picker open, including on iOS and
    // in tests. It must never throw and never block.
    expect(ImageSafety.warmUp, returnsNormally);
  });

  test('the fetch timeout is long enough to be paid once, not per post',
      () async {
    // A one-time ~11 MB download on a phone connection. Too short and the
    // check silently never runs on a slow network, which is the bug being
    // fixed wearing a different hat.
    expect(ImageSafety.fetchTimeout.inSeconds, greaterThanOrEqualTo(30));
  });

  test('an empty image is not scored, and needs no model', () async {
    // Cheapest guard, and it must come before the readiness check so a
    // zero-byte file cannot trigger a download.
    await expectLater(
      ImageSafety.refuseIfExplicit(Uint8List(0)),
      completes,
    );
  });
}

/// Where the model is fetched from.
void _modelSourceTests() {
  test('no mirror is configured by default', () {
    // The plugin's own default is a GitHub release in a third-party
    // repository, unpinned by any SHA-256. That works, and is worth replacing
    // for a moderation feature — see ModerationConfig.
    expect(ModerationConfig.hasMirror, isFalse);
    expect(ModerationConfig.modelUrl, isEmpty);
  });

  test('a mirror has to be a real https URL to count', () {
    // Arrives from a --dart-define on a build machine, where a typo is not a
    // compile error and the symptom is moderation quietly reverting to the
    // third-party default.
    bool usable(String value) {
      if (value.isEmpty) return false;
      final Uri? parsed = Uri.tryParse(value);
      return parsed != null &&
          parsed.isScheme('https') &&
          parsed.host.isNotEmpty;
    }

    expect(usable(''), isFalse);
    expect(usable('tbd'), isFalse);
    expect(usable('http://example.com/model.zip'), isFalse);
    expect(usable('https://'), isFalse);
    expect(
      usable('https://example.supabase.co/storage/v1/object/public/'
          'models/OpenNSFW2.tflite.zip'),
      isTrue,
    );
  });
}
