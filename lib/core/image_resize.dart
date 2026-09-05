import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Makes the small copy of a picture that most of the app actually shows.
///
/// ## Why a second file exists at all
///
/// A meal photo is uploaded at up to 1600px because it has to survive being
/// looked at full size. It is then drawn in a 44px thumbnail on a post card, a
/// half-width card in the meals grid, and a third-width tile in saved posts —
/// and every one of those was downloading the whole 1600px file to do it.
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

  /// The long edge of a generated thumbnail.
  ///
  /// The widest place one is shown is a meal card at half the screen — about
  /// 195pt, so 585 real pixels on a 3x phone. 640 covers that with a little
  /// room and is about a twentieth of a 1600px file once re-encoded.
  static const int thumbnailEdge = 640;

  /// JPEG quality for the small copy.
  ///
  /// Lower than the 82 the full-size upload uses. At thumbnail scale the
  /// artefacts are below the size of a drawn pixel, and the bytes saved are
  /// the entire point of the file.
  static const int thumbnailQuality = 70;

  /// A JPEG copy of [bytes] whose long edge is at most [thumbnailEdge].
  ///
  /// Returns null rather than throwing when the bytes are not an image this
  /// can read — a thumbnail is an optimisation, and failing to make one must
  /// never fail the upload it belongs to. The caller falls back to the full
  /// size, which is where it was before.
  ///
  /// Runs on a background isolate. Decoding and re-encoding a 1600px JPEG in
  /// pure Dart is a few hundred milliseconds, and a few hundred milliseconds
  /// on the UI thread is a visible stutter at exactly the moment somebody is
  /// watching a save happen.
  static Future<Uint8List?> thumbnail(Uint8List bytes) {
    return compute(_resize, bytes);
  }
}

/// The isolate entry point. Top-level because `compute` needs it to be.
Uint8List? _resize(Uint8List bytes) {
  try {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final int longEdge =
        decoded.width > decoded.height ? decoded.width : decoded.height;

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
