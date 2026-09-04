import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/user_repository.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';

/// What someone changed about themselves.
class ProfileEdit {
  const ProfileEdit({required this.displayName, required this.bio});

  /// Empty means "clear it" rather than "leave it", which is why these are
  /// non-nullable: the sheet always sends both fields, and the repository
  /// turns empty into null.
  final String displayName;
  final String bio;
}

/// Editing the two things a person writes about themselves.
///
/// Name and bio, and nothing else. Everything else on the `users` row is a
/// number the calorie engine derives from — height, target weight, activity
/// level — and those belong to the dashboard's own flows, where changing one
/// recalculates a plan. A field that quietly rewrote someone's calorie target
/// from a profile screen would be a surprise.
///
/// The avatar is not here either: it comes from whichever OAuth provider they
/// signed in with, and letting them change it means an upload, a bucket and a
/// crop UI. Worth doing, not worth smuggling in.
class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({
    super.key,
    required this.displayName,
    required this.bio,
  });

  final String displayName;
  final String bio;

  /// Opens the sheet and writes what comes back.
  ///
  /// Resolves to the saved values so the caller can update what is on screen
  /// without refetching — and to null when nothing was saved, which is the
  /// signal to leave the screen alone.
  static Future<ProfileEdit?> open(
    BuildContext context, {
    required String displayName,
    required String bio,
  }) async {
    final UserRepository users = context.read<UserRepository>();

    final ProfileEdit? edit = await showModalBottomSheet<ProfileEdit>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EditProfileSheet(displayName: displayName, bio: bio),
    );

    if (edit == null) return null;

    await users.updateProfile(displayName: edit.displayName, bio: edit.bio);
    return edit;
  }

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.displayName);
  late final TextEditingController _bio =
      TextEditingController(text: widget.bio);

  /// Matches the CHECK constraint on `users.bio`, so the field refuses what
  /// the database would.
  static const int _maxBio = 300;

  /// `users.display_name` is a `character varying` with no length constraint,
  /// so this bound is the UI's own: a name that does not fit on a post card is
  /// a name that gets truncated everywhere it appears.
  static const int _maxName = 40;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(18.w),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'profile_edit_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 16.sp,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'profile_edit_name'.tr().toUpperCase(),
              style: GoogleFonts.inter(
                color: AppColors.textGray,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 6.h),
            _Field(
              controller: _name,
              hint: 'profile_edit_name_hint'.tr(),
              maxLength: _maxName,
            ),
            SizedBox(height: 14.h),
            Text(
              'profile_edit_about'.tr().toUpperCase(),
              style: GoogleFonts.inter(
                color: AppColors.textGray,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 6.h),
            _Field(
              controller: _bio,
              hint: 'profile_edit_about_hint'.tr(),
              maxLength: _maxBio,
              minLines: 3,
              maxLines: 5,
            ),
            SizedBox(height: 18.h),
            SizedBox(
              width: double.infinity,
              child: PressScale(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(
                    ProfileEdit(
                      displayName: _name.text,
                      bio: _bio.text,
                    ),
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(vertical: 13.h),
                    decoration: BoxDecoration(
                      color: AppColors.buttonNeon,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      'profile_edit_save'.tr().toUpperCase(),
                      style: GoogleFonts.inter(
                        color: Colors.black,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.sentences,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13.sp,
          height: 1.4,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          // The built-in counter is shown, unlike elsewhere in the app: a bio
          // has a bound people will actually reach, and finding out by having
          // the field stop accepting characters is worse than seeing it coming.
          counterStyle: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 9.sp,
          ),
          hintText: hint,
          hintStyle: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 13.sp,
          ),
        ),
      ),
    );
  }
}
