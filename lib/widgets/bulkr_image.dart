import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../styles/app_color.dart';

/// Every remote image in the app.
///
/// There is one of these rather than a `Image.network` per call site, because
/// the two things that make remote images expensive are decided per call site
/// and were previously not being decided at all.
///
/// ## Why not Image.network
///
/// Flutter's own network image caches in memory and nowhere else. Kill the app
/// and every avatar, every meal photo and every post picture is fetched again
/// — which on Supabase is billed egress, and on a phone is somebody's mobile
/// data. [CachedNetworkImage] keeps them on disk, so the second look at a feed
/// costs nothing at all.
///
/// ## Why the size matters
///
/// Photos are uploaded at up to 1600px wide. Decoded, that is roughly 1600 ×
/// 1200 × 4 bytes — about 7 MB of memory — and it was 7 MB whether the picture
/// filled the screen or sat in a 44px thumbnail on a post card. [width] and
/// [height] are the box it is drawn in, and the decode is sized to match, so a
/// thumbnail costs a thumbnail. Scrolling a feed of them is the difference
/// between a few megabytes and a few hundred.
///
/// Null [width] means "as wide as it gets" — a full-bleed photo — and skips
/// the resize rather than guessing.
class BulkrImage extends StatelessWidget {
  const BulkrImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
    this.placeholderColor,
  });

  final String url;

  /// The box this is drawn in, in logical pixels. Used for the decode size,
  /// not for layout — the parent still decides how big the widget is.
  final double? width;
  final double? height;

  final BoxFit fit;

  /// Drawn instead when the URL is unreachable or is not an image. A plain
  /// coloured block when omitted, which is what most call sites want.
  final Widget? fallback;

  /// The block shown while it loads and behind a transparent image.
  final Color? placeholderColor;

  @override
  Widget build(BuildContext context) {
    final Color background = placeholderColor ?? const Color(0xFF232323);

    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
      // Physical pixels, not logical: a 44pt thumbnail on a 3x screen still
      // wants 132 real pixels, and decoding to 44 would show visibly soft.
      memCacheWidth: _decodeWidth(context),
      // A block, not a spinner. A feed of spinners flickers; a feed of blocks
      // just fills in — and the fade is what makes that read as loading rather
      // than as a bug.
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, __) => ColoredBox(color: background),
      errorWidget: (_, __, ___) =>
          fallback ??
          ColoredBox(
            color: background,
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.textGray,
                size: 20,
              ),
            ),
          ),
    );
  }

  int? _decodeWidth(BuildContext context) {
    final double? logical = width;
    if (logical == null || logical <= 0) return null;

    final double ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return (logical * ratio).round();
  }

  /// The same caching, as an [ImageProvider], for the places that need one —
  /// a [CircleAvatar]'s `backgroundImage`, or a [DecorationImage].
  static ImageProvider provider(String url) => CachedNetworkImageProvider(url);
}
