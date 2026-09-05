import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../styles/app_color.dart';
import '../widgets/bulkr_image.dart';

/// A photo, at the size it was taken.
///
/// The feed crops to 4:5 because a column of pictures of different shapes is a
/// mess to scroll. That crop is a layout decision, not a claim about the
/// photo, and until now it was the only view of it there was — a progress
/// shot with the feet cut off had them cut off permanently.
///
/// Contained rather than covered here, so nothing is hidden; the black ground
/// is what the leftover space becomes.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  final List<String> urls;
  final int initialIndex;

  static Future<void> open(
    BuildContext context, {
    required List<String> urls,
    int initialIndex = 0,
  }) {
    if (urls.isEmpty) return Future<void>.value();

    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        // Black rather than opaque, so the feed stays visible under the fade
        // rather than the screen going white for a frame on the way in.
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: PhotoViewerScreen(urls: urls, initialIndex: initialIndex),
        ),
      ),
    );
  }

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);

  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.urls.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (_, index) => _ZoomablePhoto(url: widget.urls[index]),
          ),

          // Tapping anywhere that is not a photo being dragged closes it. Above
          // the pages so it catches the gaps, below the close button so that
          // still works.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(8.w),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 22.sp,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.urls.length > 1)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Text(
                          '${_page + 1} / ${widget.urls.length}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.sp,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One photo, pinchable.
///
/// [InteractiveViewer] rather than a package: it does pinch, pan and
/// double-tap-to-reset in the framework, and a photo viewer is not worth a
/// dependency.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url});

  final String url;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _transform = TransformationController();

  /// Whether the photo is zoomed in. While it is, the page view must not steal
  /// a horizontal drag — panning around a zoomed photo and swiping to the next
  /// one are the same gesture, and the zoomed one has to win.
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final bool zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _isZoomed) setState(() => _isZoomed = zoomed);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _reset() => _transform.value = Matrix4.identity();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Double tap puts it back rather than zooming further in: getting out of
      // a zoom is the thing that is hard to do by pinching.
      onDoubleTap: _isZoomed ? _reset : null,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 4,
        panEnabled: _isZoomed,
        child: Center(
          child: BulkrImage(
            url: widget.url,
            fit: BoxFit.contain,
            placeholderColor: Colors.black,
            fallback: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                color: AppColors.textGray,
                size: 28.sp,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
