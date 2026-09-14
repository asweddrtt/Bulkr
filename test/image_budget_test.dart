import 'package:bulkr/core/image_resize.dart';
import 'package:flutter_test/flutter_test.dart';

/// How many bytes a picture is allowed to cost.
///
/// Storage is billed by the gigabyte and egress by the gigabyte served, and
/// the feed — the screen opened most — serves a photo and an avatar per post.
/// So these are pricing numbers, and like `PlanLimits` they are the kind that
/// get set once and never revisited: the capture edge was 1600 because 1600
/// sounded safe, not because anything needed it.
///
/// This file exists so that shrinking one to save money cannot quietly make it
/// smaller than the place it is drawn — and so that growing one back has to
/// argue with a number rather than a feeling.
///
/// Everything below is derived from screen geometry rather than restated. An
/// assertion that `captureEdge == 1280` would pass for any value somebody
/// typed and would catch nothing.
void main() {
  // --- what the hardware actually asks for --------------------------------

  /// The widest phone in circulation, in logical points. No phone is wider.
  const double widestPhonePt = 440;

  /// And its pixel ratio. 3x is the ceiling on phones.
  const double maxPixelRatio = 3;

  /// `ScreenUtil`'s design width. A size written `64.w` is 64 points on a
  /// phone this wide and scales up proportionally on anything wider.
  const double designWidthPt = 390;

  double physicalFor(double pointsAtDesignWidth) =>
      pointsAtDesignWidth * (widestPhonePt / designWidthPt) * maxPixelRatio;

  /// A photo at full width, in the feed and in the photo viewer.
  final double fullWidthPhoto = widestPhonePt * maxPixelRatio;

  /// The largest avatar anywhere: 64.w, on a profile header. The feed's is
  /// 34.w and a comment's is 26.w.
  final double largestAvatar = physicalFor(64);

  /// The widest thing a thumbnail is used for: a meal card at half the screen,
  /// about 195.w.
  final double widestThumbnail = physicalFor(195);

  /// How far under a placement an image may fall before the softness shows.
  /// Three percent is not visible; twenty is.
  const double tolerableUpscale = 0.90;

  group('each size covers what it is drawn at', () {
    test('a captured photo covers a full-width photo', () {
      expect(
        ImageResize.captureEdge,
        greaterThanOrEqualTo(fullWidthPhoto * tolerableUpscale),
        reason: 'photos would look soft in the feed on a large phone',
      );
    });

    test('an avatar covers the largest avatar', () {
      expect(ImageResize.avatarEdge, greaterThanOrEqualTo(largestAvatar));
    });

    test('a thumbnail covers the widest place one is used', () {
      expect(
        ImageResize.thumbnailEdge,
        greaterThanOrEqualTo(widestThumbnail * tolerableUpscale),
      );
    });
  });

  group('and none of them is paid for twice', () {
    test('a captured photo is never wider than the widest screen', () {
      // The other half of the trade, and the one that was being lost. Every
      // pixel past this is uploaded, stored and served forever to be drawn on
      // nothing.
      expect(
        ImageResize.captureEdge,
        lessThanOrEqualTo(fullWidthPhoto),
        reason: 'no screen can show these pixels',
      );
    });

    test('an avatar is not more than double what it needs', () {
      // Double the edge is four times the pixels, on a file the feed fetches
      // one of per post.
      expect(ImageResize.avatarEdge, lessThanOrEqualTo(largestAvatar * 2));
    });

    test('the sizes are in the order their names imply', () {
      // A thumbnail wider than the capture would be an upscale stored as an
      // optimisation, and `ImageResize.thumbnail` would decline to make one at
      // all — leaving every small placement back on the full file.
      expect(ImageResize.avatarEdge, lessThan(ImageResize.thumbnailEdge));
      expect(ImageResize.thumbnailEdge, lessThan(ImageResize.captureEdge));
    });
  });

  group('quality stays in the band where nobody can tell', () {
    const int visibleArtefacts = 65;
    const int wastedBytes = 90;

    test('every quality is between the two failures', () {
      for (final int quality in <int>[
        ImageResize.captureQuality,
        ImageResize.avatarQuality,
        ImageResize.thumbnailQuality,
      ]) {
        expect(quality, greaterThanOrEqualTo(visibleArtefacts));
        expect(quality, lessThanOrEqualTo(wastedBytes));
      }
    });

    test('a thumbnail is compressed harder than the photo it came from', () {
      // At thumbnail scale the artefacts are below the size of a drawn pixel,
      // and the bytes saved are the entire point of the file.
      expect(
        ImageResize.thumbnailQuality,
        lessThan(ImageResize.captureQuality),
      );
    });
  });
}
