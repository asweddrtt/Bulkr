import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../styles/app_color.dart';
import 'animations/press_scale.dart';

/// Asks whether the photo is being taken now or already exists.
///
/// A sheet rather than two buttons on the form: the choice is momentary and
/// shouldn't take up permanent space, and on iOS the camera permission prompt
/// only makes sense right after the user has asked for the camera.
class ImageSourceSheet extends StatelessWidget {
  const ImageSourceSheet({super.key, this.canRemove = false});

  /// Offers "remove photo" when there is already one attached.
  final bool canRemove;

  /// Resolves to the chosen source, or null when dismissed.
  ///
  /// [ImageSourceChoice.remove] means the user wants the existing photo gone.
  static Future<ImageSourceChoice?> show(
    BuildContext context, {
    bool canRemove = false,
  }) {
    return showModalBottomSheet<ImageSourceChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ImageSourceSheet(canRemove: canRemove),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'meal_photo_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                fontSize: 16.sp,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 16.h),
            _SourceRow(
              icon: Icons.photo_camera_rounded,
              label: 'meal_photo_camera'.tr(),
              onTap: () =>
                  Navigator.of(context).pop(ImageSourceChoice.camera),
            ),
            SizedBox(height: 10.h),
            _SourceRow(
              icon: Icons.photo_library_rounded,
              label: 'meal_photo_library'.tr(),
              onTap: () =>
                  Navigator.of(context).pop(ImageSourceChoice.library),
            ),
            if (canRemove) ...[
              SizedBox(height: 10.h),
              _SourceRow(
                icon: Icons.delete_outline_rounded,
                label: 'meal_photo_remove'.tr(),
                isDestructive: true,
                onTap: () =>
                    Navigator.of(context).pop(ImageSourceChoice.remove),
              ),
            ],
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
}

/// What the user picked in [ImageSourceSheet].
enum ImageSourceChoice {
  camera,
  library,
  remove;

  /// The plugin's equivalent, for the two choices that open a picker.
  ImageSource? get pluginSource => switch (this) {
        ImageSourceChoice.camera => ImageSource.camera,
        ImageSourceChoice.library => ImageSource.gallery,
        ImageSourceChoice.remove => null,
      };
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  static const Color _destructive = Color(0xFFFF5722);

  @override
  Widget build(BuildContext context) {
    final Color tint = isDestructive ? _destructive : AppColors.primaryNeon;

    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(5.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 20.sp),
              SizedBox(width: 12.w),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
