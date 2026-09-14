import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Every number that decides how many bytes a picture costs.
///
/// ## Why they are all here
///
/// They were spread across three screens as private constants — the post
/// composer and the meal editor each had their own copy of the same pair, and
/// the avatar picker had a third — so "how big is an upload" was a question
/// with three answers and no single place to change it. Nothing is derived
/// from anything, nothing is checked against the size it is drawn at, and a
/// number set once in 2025 is a number nobody revisits.
///
/// They are pricing decisions, like `PlanLimits`: storage is billed by the
/// gigabyte and egress by the gigabyte served, and the feed is the busiest
/// screen in the app. `image_budget_test.dart` checks each one still covers
/// what it is drawn at, so shrinking one to save money cannot quietly make it
/// smaller than the place it is shown.
///
/// ## Why a second file exists at all
///
/// A meal photo is uploaded large enough to survive being looked at full
/// size. It is then drawn in a 44px thumbnail on a post card, a half-width
/// card in the meals grid, and a third-width tile in saved posts — and every
/// one of those was downloading the whole file to do it.
///
/// Caching fixed the *second* look. Nothing fixes the first one except not
/// sending the bytes, which means having something smaller to send.
///
/// ## Why not Supabase's image transformations
///
/// `?width=400` on a render URL would do the same job with no upload work, and
/// it is billed per origin image per month, forever, for a file whose small
/// copy never changes. Making it once at upload time costs a little storage
/// and nothing after that.
class ImageResize {
  const ImageResize._();

  /// The long edge a photo is captured at — post photos and meal photos.
  ///
  /// Derived from the one place a photo is shown largest: full width, in the
  /// feed and in the photo viewer. The widest phone in circulation is 440pt
  /// across at 3x, which is 1320 real pixels, and no phone is wider than that.
  ///
  /// 1280 sits fractionally under it and comfortably over every other device —
  /// a three percent upscale on the largest screen, at a scale nobody can see,
  /// in exchange for **36% fewer pixels than the 1600 this used to be**. That
  /// 1600 was never derived from anything; it was bigger than any screen it
  /// could be drawn on, and every byte over 1320 was paid for on upload, paid
  /// for again in storage, and paid for again on every view.
  ///
  /// Zooming in the photo viewer is the one thing this costs: a 2x pinch wants
  /// 2640 pixels and never had them at 1600 either, so it is softer than it
  /// was rather than soft for the first time.
  static const int captureEdge = 1280;

  /// JPEG quality for a captured photo.
  ///
  /// 78 rather than the 82 this used to be. Progress photos are skin and gym
  /// lighting, which is where JPEG banding shows first, so this stays well
  /// above the high-60s where that starts rather than chasing the last
  /// kilobyte.
  static const int captureQuality = 78;

  /// The long edge an avatar is captured at.
  ///
  /// The largest an avatar is ever drawn is 64pt, on a profile header — 192
  /// real pixels at 3x, or about 210 on the widest phone. Everywhere else is
  /// smaller: 34pt in the feed, 26pt on a comment.
  ///
  /// So the 512 this used to be was two and a half times wider than the
  /// biggest place it appears, which is four times the pixels — on a file the
  /// feed downloads one of per post.
  static const int avatarEdge = 320;

  /// JPEG quality for an avatar. Drawn small enough that 80 is invisible.
  static const int avatarQuality = 80;

  /// The long edge of a generated thumbnail.
  ///
  /// The widest place one is shown is a meal card at half the screen — about
  /// 195pt, so 585 real pixels on a 3x phone. 640 covers that with a little
  /// room and is a small fraction of the captured file once re-encoded.
  ///
  /// Deliberately **not** used for a full-width feed photo, which is what it
  /// would have to be nearly twice as wide to serve. With [captureEdge] at
  /// 1280 a third size in between would save little enough that it is not
  /// worth a column, a migration and a backfill.
  static const int thumbnailEdge = 640;

  /// JPEG quality for the small copy.
  ///
  /// Lower than [captureQuality]. At thumbnail scale the artefacts are below
  /// the size of a drawn pixel, and the bytes saved are the entire point of
  /// the file.
  static const int thumbnailQuality = 70;

  /// A JPEG copy of [bytes] whose long edge is at most [thumbnailEdge].
  ///
  /// Returns null rather than throwing when the bytes are not an image this
  /// can read — a thumbnail is an optimisation, and failing to make one must
  /// never fail the upload it belongs to. The caller falls back to the full
  /// size, which is where it was before.
  ///
  /// Runs on a background isolate. Decoding and re-encoding a [captureEdge]
  /// JPEG in pure Dart is a few hundred milliseconds, and a few hundred
  /// milliseconds on the UI thread is a visible stutter at exactly the moment
  /// somebody is watching a save happen.
  static Future<Uint8List?> thumbnail(Uint8List bytes) {
    return compute(_resize, bytes);
  }
}

/// The isolate entry point. Top-level because `compute` needs it to be.
Uint8List? _resize(Uint8List bytes) {
  try {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final int longEdge = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;

    // Already small enough. Re-encoding it would spend CPU to produce a file
    // that is not usefully smaller and is one generation more compressed.
    if (longEdge <= ImageResize.thumbnailEdge) return null;

    // Only the long edge is given, so the other is computed and the aspect
    // ratio is kept. A thumbnail that crops is a thumbnail that lies about
    // what the picture is.
    final img.Image resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: ImageResize.thumbnailEdge)
        : img.copyResize(decoded, height: ImageResize.thumbnailEdge);

    return img.encodeJpg(resized, quality: ImageResize.thumbnailQuality);
  } catch (_) {
    // Same contract as the null above: no thumbnail is a worse feed, not a
    // failed upload.
    return null;
  }
}
