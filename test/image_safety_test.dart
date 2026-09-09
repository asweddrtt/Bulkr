import 'dart:typed_data';

import 'package:bulkr/core/image_safety.dart';
import 'package:flutter_test/flutter_test.dart';

/// The threshold, and the direction it errs in.
///
/// Yahoo's open_nsfw defaults to 0.7 and is sensitive to bare skin, which in an
/// app whose best content is a shirtless progress photo is exactly the wrong
/// sensitivity. The number here is the one thing in this feature worth being
/// deliberate about, so it gets a test rather than a comment alone.
void main() {
  // Without this, `refuseIfExplicit` throws on the binding before it reaches
  // the model at all — and the fail-open tests below then pass for a reason
  // that has nothing to do with fail-open. With it initialized, the native
  // TFLite library genuinely is not present in a unit-test process, which is
  // the same failure a device hits when the model cannot load: the real case
  // this posture exists for.
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  test('refuses only what the model is confident about', () {
    expect(ImageSafety.isExplicit(1.0), isTrue);
    expect(
      ImageSafety.isExplicit(ImageSafety.threshold),
      isTrue,
      reason: 'the threshold itself is refused, not just above it',
    );
    expect(ImageSafety.isExplicit(ImageSafety.threshold - 0.001), isFalse);
  });

  test('a progress photo scoring in open_nsfw middle band is allowed', () {
    // The band a shirtless physique shot lands in. The package would call
    // anything from 0.4 "questionable" and anything from 0.7 NSFW; both would
    // refuse posts this app exists to collect.
    for (final double score in <double>[0.45, 0.6, 0.7, 0.85]) {
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
      greaterThan(0.7),
      reason: 'below the package default is the wrong side of the trade',
    );
    expect(
      ImageSafety.threshold,
      lessThan(1.0),
      reason: 'at 1.0 nothing is ever refused and the feature is decoration',
    );
  });

  test('empty bytes are not an image and are not refused', () async {
    // Reached when a picker hands back nothing. It must not throw: the upload
    // that follows will fail on its own terms with a message that fits.
    await expectLater(ImageSafety.refuseIfExplicit(Uint8List(0)), completes);
  });

  test('an unavailable model allows the upload instead of blocking it',
      () async {
    // The whole posture of this check, and the case that actually happens on a
    // device: the native library fails to load, or the asset is missing from
    // the bundle. A moderation step that can take "post a photo" down with it
    // is worse than the content it was added to catch.
    //
    // There is no TFLite native library in a unit-test process, so this is that
    // failure for real rather than a stand-in for it.
    await expectLater(
      ImageSafety.refuseIfExplicit(Uint8List.fromList(<int>[1, 2, 3, 4])),
      completes,
    );
  });
}
