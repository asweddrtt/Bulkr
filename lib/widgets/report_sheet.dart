import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/post_repository.dart';
import '../models/post.dart';
import '../models/post_report.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';
import 'sheet_action_row.dart';

/// What the user chose to report a post for.
class ReportChoice {
  const ReportChoice({required this.reason, this.note});

  final PostReportReason reason;

  /// The optional free-text note, only ever collected for
  /// [PostReportReason.other].
  final String? note;
}

/// Why are you reporting this.
///
/// A list of reasons rather than a confirm dialog, because the reason is the
/// only part of a report that carries information — "reported" alone tells
/// whoever reads it nothing, and nobody reads these anyway: the threshold acts
/// on the count.
///
/// The sheet also says what a report does, in one line. A user who expects
/// their report to summon a moderator and instead sees nothing happen
/// concludes the button is fake; a user told that enough reports hide a post
/// understands both what they did and why nothing visible changed.
class ReportSheet extends StatelessWidget {
  const ReportSheet({super.key});

  /// Resolves to the chosen reason, or null when dismissed.
  static Future<ReportChoice?> show(BuildContext context) {
    return showModalBottomSheet<ReportChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const ReportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: 'report_title'.tr(),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: Text(
            'report_explainer'.tr(),
            style: GoogleFonts.inter(
              color: AppColors.textGray,
              fontSize: 11.sp,
              height: 1.45,
            ),
          ),
        ),
        for (final PostReportReason reason in PostReportReason.values)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: SheetActionRow(
              icon: _iconFor(reason),
              label: reason.labelKey.tr(),
              helper: reason.helperKey.tr(),
              isDestructive: true,
              onTap: () => _choose(context, reason),
            ),
          ),
      ],
    );
  }

  Future<void> _choose(BuildContext context, PostReportReason reason) async {
    final NavigatorState navigator = Navigator.of(context);

    if (!reason.wantsNote) {
      navigator.pop(ReportChoice(reason: reason));
      return;
    }

    // "Other" is the one reason that cannot speak for itself, so it is the one
    // that asks. Skipping the note is allowed — a report with no explanation
    // still counts towards the threshold, and refusing to accept one would
    // lose reports from people who cannot put it into words.
    final String? note = await _NoteSheet.show(context);
    if (!navigator.mounted) return;

    navigator.pop(ReportChoice(reason: reason, note: note));
  }

  static IconData _iconFor(PostReportReason reason) => switch (reason) {
        PostReportReason.spam => Icons.block,
        PostReportReason.harassment => Icons.report_gmailerrorred,
        PostReportReason.misinformation => Icons.fact_check_outlined,
        PostReportReason.inappropriate => Icons.visibility_off_outlined,
        PostReportReason.other => Icons.more_horiz,
      };
}

/// The note field, for "other".
class _NoteSheet extends StatefulWidget {
  const _NoteSheet();

  /// Resolves to the typed note, or null when skipped or dismissed.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _NoteSheet(),
    );
  }

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final TextEditingController _controller = TextEditingController();

  /// Matches the CHECK constraint on `post_reports.note`, so the field refuses
  /// what the database would.
  static const int _maxLength = 500;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SheetShell(
        title: 'report_note_title'.tr(),
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1C),
              borderRadius: BorderRadius.circular(5.r),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 3,
              maxLength: _maxLength,
              autofocus: true,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
              decoration: InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: 'report_note_hint'.tr(),
                hintStyle: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 13.sp,
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: PressScale(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(
                      _controller.text.trim().isEmpty
                          ? null
                          : _controller.text.trim(),
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(vertical: 12.h),
                      decoration: BoxDecoration(
                        color: AppColors.buttonNeon,
                        borderRadius: BorderRadius.circular(5.r),
                      ),
                      child: Text(
                        'report_submit'.tr().toUpperCase(),
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
        ],
      ),
    );
  }
}


/// Asks why, files the report, and says what happened.
///
/// A free function rather than a method on a cubit, and deliberately: every
/// screen that shows a post can reach it, none of them hold report state, and
/// a report changes nothing on screen — the post stays where it is until
/// enough other people agree.
///
/// The confirmation is worth showing precisely because nothing visible
/// happens. Silence after a report reads as a button that did not work.
Future<void> reportPostFlow(BuildContext context, Post post) async {
  final PostRepository posts = context.read<PostRepository>();
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final ReportChoice? choice = await ReportSheet.show(context);
  if (choice == null) return;

  String message;
  try {
    await posts.reportPost(
      postId: post.id,
      reason: choice.reason,
      note: choice.note,
    );
    message = 'report_thanks'.tr();
  } catch (error) {
    message = '$error';
  }

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2A2A2A),
        duration: const Duration(seconds: 4),
        content: Text(
          message,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
        ),
      ),
    );
}
