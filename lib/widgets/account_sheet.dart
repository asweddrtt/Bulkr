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
    this.onRemoveAds,
    this.adFreeRemaining,
    required this.onPremium,
    required this.isPremium,
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

  /// Opens the upgrade screen, or — for somebody who already pays — says so.
  ///
  /// Present either way. A subscriber tapping "Bulkr Premium" and finding
  /// nothing there is a subscriber wondering whether the payment worked.
  final VoidCallback onPremium;

  final bool isPremium;

  /// Watch a rewarded video, get a day without ads.
  ///
  /// Null when there is nothing to offer — a premium account, a build with no
  /// rewarded ad unit configured, a platform with no AdMob app — and the row
  /// is then absent rather than present and disabled. An offer you cannot
  /// accept is worse than no offer: it reads as the app being broken, and it
  /// advertises a benefit of paying to somebody who already paid.
  final VoidCallback? onRemoveAds;

  /// How much of an earned ad-free window is left, when one is running.
  ///
  /// The row stays visible while it runs, saying so. Hiding it the moment the
  /// reward is granted would make the thing the user just did disappear, and
  /// "did that work?" is a question worth never making anybody ask.
  final Duration? adFreeRemaining;

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
    VoidCallback? onRemoveAds,
    Duration? adFreeRemaining,
    required VoidCallback onPremium,
    required bool isPremium,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // Without this the sheet is capped at nine sixteenths of the screen, and
      // this one is taller than that: five rows with helper text, sign out,
      // and delete. Everything past the cap was not clipped-but-reachable, it
      // was simply gone — sign out included, on a sheet that exists to let
      // somebody sign out.
      isScrollControlled: true,
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
        onRemoveAds: onRemoveAds,
        adFreeRemaining: adFreeRemaining,
        onPremium: onPremium,
        isPremium: isPremium,
      ),
    );
  }

  /// Either the offer, or how long is left of the one already running.
  ///
  /// Rounded up to the next hour, and never to "0h": a window with eleven
  /// minutes left is still a window, and saying zero would read as it having
  /// already gone.
  String _removeAdsHelper() {
    final Duration? left = adFreeRemaining;
    if (left == null || left.inSeconds <= 0) {
      return 'account_remove_ads_helper'.tr();
    }

    final int hours = (left.inMinutes / 60).ceil();
    return 'account_remove_ads_active'.tr(namedArgs: <String, String>{
      'hours': hours == 1 ? '1 hour' : '$hours hours',
    });
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
        // Nine tenths rather than all of it: the strip left over is what the
        // user taps to dismiss, and a sheet with no way out but a button is
        // its own bug.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          // The padding belongs to the scroll view rather than the box around
          // it, so the last row can clear the bottom edge instead of stopping
          // short of it.
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
                style: GoogleFonts.inter(fontSize: 13.sp, color: Colors.white),
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
                    // First, and the only row that is about something the
                    // user does not already have. Everything below it is a
                    // thing they own; this is the one thing for sale, and
                    // burying it under four rows they never tap would be
                    // coy rather than tasteful.
                    SheetActionRow(
                      icon: Icons.workspace_premium_outlined,
                      label: 'account_premium'.tr(),
                      helper: isPremium
                          ? 'account_premium_active'.tr()
                          : 'account_premium_helper'.tr(),
                      onTap: () {
                        Navigator.of(context).pop();
                        onPremium();
                      },
                    ),
                    SizedBox(height: 10.h),
                    // Then, ordered by how often they are wanted: your own
                    // details, then what you kept, then making something, then
                    // the moderation list nobody opens unless they mean to.
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
                    if (onRemoveAds != null) ...[
                      SheetActionRow(
                        icon: Icons.block_flipped,
                        label: 'account_remove_ads'.tr(),
                        helper: _removeAdsHelper(),
                        // Deliberately does not close the sheet. The video
                        // takes half a minute and comes back to wherever it
                        // was opened from; popping first would drop the user
                        // on the profile with no sign that anything happened.
                        onTap: onRemoveAds!,
                      ),
                      SizedBox(height: 10.h),
                    ],
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
      ),
    );
  }
}
