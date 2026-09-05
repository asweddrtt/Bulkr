import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import 'sheet_action_row.dart';

/// Behind the settings gear. Small on purpose: it exists so the user can see
/// which account they are actually signed in as, and get out of it.
class AccountSheet extends StatelessWidget {
  const AccountSheet({
    super.key,
    required this.email,
    required this.username,
    required this.onSignOut,
    required this.onManageBlocked,
    required this.onDeleteAccount,
    required this.onSavedPosts,
    required this.onCreateGroup,
    required this.onChallenges,
    this.onEditProfile,
  });

  /// The email on the Supabase session — the answer to "which account is this?".
  final String? email;

  final String username;
  final Future<void> Function() onSignOut;

  /// Opens the list of people this user has blocked, so it can be undone.
  final VoidCallback onManageBlocked;

  /// Everything the user has bookmarked.
  final VoidCallback onSavedPosts;

  /// Starts a group. Also an icon on the profile header — this is the row for
  /// somebody who does not know the icon is there.
  final VoidCallback onCreateGroup;

  /// The challenges this user has joined. Here because the only other way in
  /// is a challenge post being on screen — scroll past it and the thing you
  /// joined is gone.
  final VoidCallback onChallenges;

  /// Name and about. Null until the profile row has loaded, which is what
  /// keeps this row out rather than opening a sheet with empty fields in it.
  final VoidCallback? onEditProfile;

  /// Deletes the account. Confirmed by the screen, not here — a sheet is not
  /// where something irreversible should be one tap away.
  final VoidCallback onDeleteAccount;

  static Future<void> show(
    BuildContext context, {
    required String? email,
    required String username,
    required Future<void> Function() onSignOut,
    required VoidCallback onManageBlocked,
    required VoidCallback onDeleteAccount,
    required VoidCallback onSavedPosts,
    required VoidCallback onCreateGroup,
    required VoidCallback onChallenges,
    VoidCallback? onEditProfile,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AccountSheet(
        email: email,
        username: username,
        onSignOut: onSignOut,
        onManageBlocked: onManageBlocked,
        onDeleteAccount: onDeleteAccount,
        onSavedPosts: onSavedPosts,
        onCreateGroup: onCreateGroup,
        onChallenges: onChallenges,
        onEditProfile: onEditProfile,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Ordered by how often they are wanted: your own details,
                  // then what you kept, then making something, then the
                  // moderation list nobody opens unless they mean to.
                  if (onEditProfile != null) ...[
                    SheetActionRow(
                      icon: Icons.edit_outlined,
                      label: 'account_edit_profile'.tr(),
                      helper: 'account_edit_profile_helper'.tr(),
                      onTap: () {
                        Navigator.of(context).pop();
                        onEditProfile!();
                      },
                    ),
                    SizedBox(height: 10.h),
                  ],
                  SheetActionRow(
                    icon: Icons.bookmark_border,
                    label: 'account_saved_posts'.tr(),
                    helper: 'account_saved_posts_helper'.tr(),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSavedPosts();
                    },
                  ),
                  SizedBox(height: 10.h),
                  SheetActionRow(
                    icon: Icons.emoji_events_outlined,
                    label: 'account_challenges'.tr(),
                    helper: 'account_challenges_helper'.tr(),
                    onTap: () {
                      Navigator.of(context).pop();
                      onChallenges();
                    },
                  ),
                  SizedBox(height: 10.h),
                  SheetActionRow(
                    icon: Icons.group_add_outlined,
                    label: 'account_create_group'.tr(),
                    helper: 'account_create_group_helper'.tr(),
                    onTap: () {
                      Navigator.of(context).pop();
                      onCreateGroup();
                    },
                  ),
                  SizedBox(height: 10.h),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: SheetActionRow(
                icon: Icons.block,
                label: 'account_blocked'.tr(),
                helper: 'account_blocked_helper'.tr(),
                onTap: () {
                  Navigator.of(context).pop();
                  onManageBlocked();
                },
              ),
            ),
            SizedBox(height: 14.h),
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
            SizedBox(height: 18.h),
            // Last, quiet, and a text button rather than an outlined one. It
            // should be findable by someone looking for it and not by someone
            // aiming at sign out — those two are one tap apart and only one of
            // them can be undone.
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onDeleteAccount();
                },
                child: Text(
                  'account_delete'.tr(),
                  style: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 11.sp,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textGray,
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
