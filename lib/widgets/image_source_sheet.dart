import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import 'sheet_action_row.dart';

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
    return SheetShell(
      title: 'meal_photo_title'.tr(),
      children: [
        SheetActionRow(
          icon: Icons.photo_camera_rounded,
          label: 'meal_photo_camera'.tr(),
          onTap: () => Navigator.of(context).pop(ImageSourceChoice.camera),
        ),
        SizedBox(height: 10.h),
        SheetActionRow(
          icon: Icons.photo_library_rounded,
          label: 'meal_photo_library'.tr(),
          onTap: () => Navigator.of(context).pop(ImageSourceChoice.library),
        ),
        if (canRemove) ...[
          SizedBox(height: 10.h),
          SheetActionRow(
            icon: Icons.delete_outline_rounded,
            label: 'meal_photo_remove'.tr(),
            isDestructive: true,
            onTap: () => Navigator.of(context).pop(ImageSourceChoice.remove),
          ),
        ],
      ],
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
