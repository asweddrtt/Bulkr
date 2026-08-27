import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../styles/app_color.dart';

/// Reads a barcode off a package.
///
/// The one input that identifies a packaged food exactly: no spelling, no
/// ranking, no choosing between six versions of the same yoghurt.
class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  /// Resolves to the scanned code, or null when dismissed.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const BarcodeScannerSheet(),
    );
  }

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet> {
  late final MobileScannerController _controller;

  /// The camera reports the same code many times a second while it stays in
  /// frame. Without this the sheet would pop, and then keep trying to pop.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      // Only the symbologies that appear on food packaging. Narrowing the set
      // makes detection quicker and stops a QR code on the same label winning.
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      ],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    // Releases the camera. Without it the torch stays lit and the preview keeps
    // running behind whatever is on screen next.
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final Barcode barcode in capture.barcodes) {
      final String? value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;

      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.7.sh,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  // A denied permission or a device with no usable camera is a
                  // normal outcome, not a crash — the user can still search by
                  // name, which is what the message says.
                  // Three parameters, not two: the builder is handed the
                  // preview it would have wrapped, which is null while the
                  // camera never started.
                  errorBuilder: (context, error, child) => _buildError(error),
                ),
                IgnorePointer(child: CustomPaint(painter: _ReticlePainter())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 14.h, 8.w, 12.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'barcode_scan_title'.tr().toUpperCase(),
                  style: GoogleFonts.anton(
                    fontSize: 17.sp,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'barcode_scan_subtitle'.tr(),
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    color: AppColors.textGray,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: Icon(Icons.flashlight_on_outlined, size: 22.sp),
            color: AppColors.primaryNeon,
            tooltip: 'barcode_torch'.tr(),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, size: 22.sp),
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildError(MobileScannerException error) {
    return ColoredBox(
      color: const Color(0xFF121212),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 40.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography_outlined,
                size: 34.sp,
                color: AppColors.darkBorder,
              ),
              SizedBox(height: 14.h),
              Text(
                'barcode_camera_unavailable'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  color: AppColors.textGray,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Corner brackets over the middle of the frame.
///
/// Not a functional crop — the scanner reads the whole image — but it tells the
/// user where to hold the package, which is most of what makes scanning feel
/// quick rather than fiddly.
class _ReticlePainter extends CustomPainter {
  static const double _boxFraction = 0.72;
  static const double _cornerFraction = 0.12;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide * _boxFraction;
    final Rect box = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: side,
      height: side * 0.62,
    );

    final Paint shade = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(RRect.fromRectAndRadius(box, const Radius.circular(8))),
      ),
      shade,
    );

    final Paint stroke = Paint()
      ..color = AppColors.primaryNeon
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double arm = box.shortestSide * _cornerFraction * 2;

    for (final (Offset corner, double dx, double dy) in [
      (box.topLeft, 1.0, 1.0),
      (box.topRight, -1.0, 1.0),
      (box.bottomLeft, 1.0, -1.0),
      (box.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner.translate(arm * dx, 0), stroke);
      canvas.drawLine(corner, corner.translate(0, arm * dy), stroke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
