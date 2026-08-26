import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Behind the settings gear. Small on purpose: it exists so the user can see
/// which account they are actually signed in as, and get out of it.
class AccountSheet extends StatelessWidget {
  const AccountSheet({
    super.key,
    required this.email,
    required this.username,
    required this.onSignOut,
  });

  /// The email on the Supabase session — the answer to "which account is this?".
  final String? email;

  final String username;
  final Future<void> Function() onSignOut;

  static Future<void> show(
    BuildContext context, {
    required String? email,
    required String username,
    required Future<void> Function() onSignOut,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AccountSheet(
        email: email,
        username: username,
        onSignOut: onSignOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border(
            top: BorderSide(color: AppColors.darkBorder, width: 1.h),
          ),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 20.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColors.darkBorder,
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
            ),
            SizedBox(height: 18.h),
            Text(
              'account_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                fontSize: 18.sp,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              email ?? 'account_no_email'.tr(),
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              '@$username',
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            SizedBox(height: 24.h),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await onSignOut();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF5722),
                  side: const BorderSide(color: Color(0xFFFF5722)),
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
                child: Text(
                  'sign_out_btn'.tr().toUpperCase(),
                  style: GoogleFonts.anton(fontSize: 16.sp, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
