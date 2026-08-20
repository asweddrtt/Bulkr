import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/auth_user.dart';
import '../models/user_profile.dart';
import '../styles/app_color.dart';

/// Account sheet behind the settings gear: rename the athlete or sign out.
/// Returns the new display name, or null when nothing was changed.
class AccountSheet extends StatefulWidget {
  final UserProfile profile;
  final Future<void> Function() onSignOut;

  const AccountSheet({
    super.key,
    required this.profile,
    required this.onSignOut,
  });

  static Future<String?> show(
    BuildContext context, {
    required UserProfile profile,
    required Future<void> Function() onSignOut,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AccountSheet(profile: profile, onSignOut: onSignOut),
    );
  }

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.profile.displayName);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _providerLabel {
    switch (widget.profile.provider) {
      case AuthProvider.apple:
        return 'provider_apple'.tr();
      case AuthProvider.google:
        return 'provider_google'.tr();
      case AuthProvider.email:
        return 'provider_email'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
          border: const Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'account_title'.tr().toUpperCase(),
                style: GoogleFonts.anton(
                  fontSize: 20.sp,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'signed_in_with'.tr(namedArgs: {'provider': _providerLabel}),
                style: GoogleFonts.inter(
                  fontSize: 11.sp,
                  color: AppColors.textGray,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'display_name_label'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.offWhiteMuted,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(height: 8.h),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                onSubmitted: (value) => Navigator.of(context).pop(value),
                style: GoogleFonts.anton(fontSize: 22.sp, color: Colors.white),
                cursorColor: AppColors.primaryNeon,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.cardDeep,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.r),
                    borderSide: const BorderSide(color: AppColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.r),
                    borderSide: const BorderSide(
                      color: AppColors.primaryNeon,
                      width: 2,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pop(_nameController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                  child: Text(
                    'save_btn'.tr().toUpperCase(),
                    style: GoogleFonts.anton(fontSize: 15.sp),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await widget.onSignOut();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF5722),
                    side: const BorderSide(color: Color(0xFFFF5722)),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
                  child: Text(
                    'sign_out_btn'.tr().toUpperCase(),
                    style: GoogleFonts.anton(fontSize: 15.sp),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
