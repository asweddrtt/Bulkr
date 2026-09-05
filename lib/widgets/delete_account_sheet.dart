import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Confirms deleting an account, by making the user type their handle.
///
/// A typed confirmation rather than a yes/no. This is the one action in the app
/// that nothing can undo — the login, the profile, every post, comment, meal
/// and log, and the replies other people's threads were holding — and a dialog
/// somebody can dismiss by tapping where OK usually is does not match that.
///
/// Typing the handle also makes the target unambiguous. Somebody signed in on a
/// shared device is being asked to name the account, not just to agree.
class DeleteAccountSheet extends StatefulWidget {
  const DeleteAccountSheet({super.key, required this.username});

  final String username;

  /// True when the user confirmed. Dismissal is false, never null, so the
  /// caller cannot accidentally treat "they backed out" as "go ahead".
  static Future<bool> show(BuildContext context, String username) async {
    final bool? confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DeleteAccountSheet(username: username),
    );

    return confirmed ?? false;
  }

  @override
  State<DeleteAccountSheet> createState() => _DeleteAccountSheetState();
}

class _DeleteAccountSheetState extends State<DeleteAccountSheet> {
  final TextEditingController _typed = TextEditingController();

  static const Color _danger = Color(0xFFFF5722);

  bool get _matches =>
      _typed.text.trim().toLowerCase() == widget.username.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _typed.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _typed.dispose();
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
          border: Border.all(color: _danger.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'account_delete_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: _danger,
                fontSize: 17.sp,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'account_delete_body'.tr(),
              style: GoogleFonts.inter(
                color: AppColors.offWhiteMuted,
                fontSize: 12.sp,
                height: 1.5,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'account_delete_prompt'.tr(namedArgs: {'handle': widget.username}),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 12.sp,
                height: 1.4,
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6.r),
                border: Border.all(
                  color: _matches ? _danger : AppColors.darkBorder,
                ),
              ),
              child: TextField(
                controller: _typed,
                autocorrect: false,
                enableSuggestions: false,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                  hintText: widget.username,
                  hintStyle: GoogleFonts.inter(
                    color: AppColors.darkBorder,
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ),
            SizedBox(height: 18.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.darkBorder),
                      padding: EdgeInsets.symmetric(vertical: 13.h),
                    ),
                    child: Text(
                      'cancel'.tr().toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: ElevatedButton(
                    // Disabled until the handle matches. The button being dead
                    // is the confirmation — there is nothing to read past.
                    onPressed:
                        _matches ? () => Navigator.of(context).pop(true) : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _danger,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF2A2A2A),
                      disabledForegroundColor: AppColors.textGray,
                      padding: EdgeInsets.symmetric(vertical: 13.h),
                    ),
                    child: Text(
                      'account_delete_action'.tr().toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
