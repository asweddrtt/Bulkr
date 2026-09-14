import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import 'bulkr_nav_bar.dart';

/// What a message is about, which is the only thing a call site has to decide.
///
/// Colour is a property of the *kind* of message, not of the screen showing it
/// — before this every snackbar in the app wrote `const Color(0xFF2A2A2A)` by
/// hand, and the two that did not were a saved-meal confirmation in full neon
/// and a scan failure in the same grey as a success. A reader learns nothing
/// from a colour that means something different each time.
enum SnackTone {
  /// Something happened and there is nothing to do about it. The default, and
  /// the one most messages are.
  neutral,

  /// It worked. Neon, because that is what this app's "yes" looks like
  /// everywhere else, and black text because neon will not carry white.
  success,

  /// It did not work. Red-tinted rather than red: a full red bar over a black
  /// app reads as a crash, and most of these are "couldn't reach the server".
  danger,

  /// A premium wall, or something premium just unlocked. Neon on charcoal, so
  /// it is recognisably the same colour as the upgrade button without being
  /// the same shout as a success.
  premium,
}

/// Every snackbar in Bulkr.
///
/// ## Floating, and clear of the navigation bar
///
/// Material's default snackbar is a full-bleed rectangle welded to the bottom
/// edge. Under a floating pill navigation bar that is wrong twice: it collides
/// with the pill, and a square-cornered bar under a rounded one looks like a
/// different app's widget leaked in. These float, are inset on all sides, and
/// are lifted clear of the bar.
///
/// The lift is the part worth reading. `BulkrNavBar` is the shell's
/// `bottomNavigationBar`, so Flutter would raise a floating snackbar above it
/// automatically — but only for the `Scaffold` that owns it, and every tab in
/// this app nests its own `Scaffold` inside that shell. The snackbar is shown
/// in the nested one, which has no navigation bar and therefore no idea
/// anything is in the way. So the lift is applied here instead, and only on
/// the shell route: a pushed full-screen route (the meal editor, the paywall)
/// has no bar under it, and lifting there would leave the message hanging in
/// the middle of nothing.
///
/// [clearsNavBar] overrides the guess for a caller that knows better.
class BulkrSnackBar {
  const BulkrSnackBar._();

  static const Duration _default = Duration(seconds: 4);

  /// Shows [message], replacing whatever is already up.
  ///
  /// Replacing rather than queueing: two messages in a row nearly always mean
  /// the second one supersedes the first, and a queue makes somebody wait four
  /// seconds to read news that is already stale.
  static void show(
    BuildContext context,
    String message, {
    SnackTone tone = SnackTone.neutral,
    Duration duration = _default,
    String? actionLabel,
    VoidCallback? onAction,
    bool? clearsNavBar,
  }) {
    showOn(
      ScaffoldMessenger.of(context),
      message,
      tone: tone,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      clearsNavBar: clearsNavBar ?? _underNavBar(context),
    );
  }

  /// The same, for a caller holding a messenger it captured before an `await`.
  ///
  /// Which is most of the asynchronous ones: reading a `ScaffoldMessenger` off
  /// a `BuildContext` after the widget has gone is how a save handler throws
  /// in a place nobody is looking.
  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    SnackTone tone = SnackTone.neutral,
    Duration duration = _default,
    String? actionLabel,
    VoidCallback? onAction,
    bool clearsNavBar = true,
  }) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        build(
          message,
          tone: tone,
          duration: duration,
          actionLabel: actionLabel,
          onAction: onAction,
          clearsNavBar: clearsNavBar,
        ),
      );
  }

  /// The bar itself, for the rare caller that wants to hand it somewhere else.
  static SnackBar build(
    String message, {
    SnackTone tone = SnackTone.neutral,
    Duration duration = _default,
    String? actionLabel,
    VoidCallback? onAction,
    bool clearsNavBar = true,
  }) {
    final _Palette palette = _paletteFor(tone);

    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.background,
      elevation: 8,
      duration: duration,
      margin: EdgeInsets.fromLTRB(
        16.w,
        0,
        16.w,
        clearsNavBar ? _navBarLift : 16.h,
      ),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14.r),
        side: BorderSide(color: palette.border),
      ),
      content: Row(
        children: <Widget>[
          Icon(palette.icon, color: palette.accent, size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                color: palette.foreground,
                fontSize: 12.sp,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      action: actionLabel == null || onAction == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: palette.accent,
              onPressed: onAction,
            ),
    );
  }

  /// The bar's height, its margin, and a gap — the same arithmetic
  /// `BulkrNavBar.contentInset` does for a scrolling list, without the extra
  /// breathing room a list wants and a snackbar does not.
  static double get _navBarLift =>
      BulkrNavBar.barHeight + BulkrNavBar.barMargin + 8.h;

  /// Whether a navigation bar is under this context.
  ///
  /// True on the shell route, which is the one the bar belongs to, and false
  /// on anything pushed over it. A context with no route at all — a widget
  /// test — reads as the shell, which is the safer of the two guesses: a
  /// message floating slightly high is a cosmetic complaint, one behind the
  /// navigation bar cannot be read.
  static bool _underNavBar(BuildContext context) =>
      ModalRoute.of(context)?.isFirst ?? true;

  static _Palette _paletteFor(SnackTone tone) {
    return switch (tone) {
      SnackTone.neutral => _Palette(
        background: const Color(0xFF1C1C1E),
        foreground: Colors.white,
        accent: AppColors.offWhiteMuted,
        border: Colors.white.withValues(alpha: 0.10),
        icon: Icons.info_outline_rounded,
      ),
      SnackTone.success => const _Palette(
        background: AppColors.primaryNeon,
        foreground: Colors.black,
        accent: Colors.black,
        border: Colors.transparent,
        icon: Icons.check_circle_rounded,
      ),
      SnackTone.danger => _Palette(
        background: const Color(0xFF2A1618),
        foreground: Colors.white,
        accent: const Color(0xFFFF6B6B),
        border: const Color(0xFFFF6B6B).withValues(alpha: 0.35),
        icon: Icons.error_outline_rounded,
      ),
      SnackTone.premium => _Palette(
        background: const Color(0xFF16190A),
        foreground: Colors.white,
        accent: AppColors.primaryNeon,
        border: AppColors.primaryNeon.withValues(alpha: 0.40),
        icon: Icons.workspace_premium_rounded,
      ),
    };
  }
}

class _Palette {
  const _Palette({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.border,
    required this.icon,
  });

  final Color background;
  final Color foreground;

  /// The icon, and the action label. One colour for both, so the two things
  /// that are not prose read as a pair.
  final Color accent;
  final Color border;
  final IconData icon;
}
