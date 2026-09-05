import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';

/// One destination in the bar.
class NavDestination {
  const NavDestination(this.icon, this.labelKey);

  final IconData icon;
  final String labelKey;
}

/// The floating, blurred navigation bar.
///
/// Sits over the content rather than under it — the screen behind is what the
/// blur is blurring, so the bar has to have something to sit on top of.
/// [MainScreen] sets `extendBody: true` for that, and screens that scroll
/// reserve [contentInset] at the bottom of their list so the last item can
/// still be read once it has travelled under the glass.
///
/// Dragging across the bar moves between tabs. Only across the bar: the Feed
/// swipes between For You and Discover, and Meals between its two tabs, so a
/// full-screen swipe would be fighting two gestures that already exist and
/// mean something.
class BulkrNavBar extends StatefulWidget {
  const BulkrNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// The bar's own height, above whatever safe-area inset sits below it.
  static double get barHeight => 56.h;

  /// The gap between the bar and the bottom of the screen.
  static double get barMargin => 12.h;

  /// What a scrolling screen should leave clear at the bottom.
  ///
  /// The bar, its margin, and a little air so the last row is not touching the
  /// glass. Not measured from a LayoutBuilder because a scroll view needs the
  /// number before the bar has laid out.
  static double get contentInset => barHeight + barMargin + 36.h;

  /// What a floating action button inside the shell must be lifted by.
  ///
  /// A tab's [Scaffold] is nested inside this one and knows nothing about the
  /// bar, so it puts its button at the bottom of itself — which, now that the
  /// shell sets `extendBody: true`, is underneath the glass.
  static double get fabInset => barHeight + barMargin;

  /// Where a drag lands, and what travel is left over.
  ///
  /// Pure and separate from the widget so it can be tested, which it is:
  /// the first version of this shipped an infinite loop. It consumed travel
  /// with the wrong sign, so each pass round the loop made `travel` larger
  /// instead of smaller and the condition could never become false — a hard
  /// freeze on the UI thread the moment a drag crossed one step.
  ///
  /// Reads [current] once and walks a local copy. Calling back per step would
  /// re-read a `widget.currentIndex` that cannot have changed yet — `setState`
  /// schedules a rebuild rather than performing one — so a long drag would
  /// select the same neighbour repeatedly instead of travelling.
  @visibleForTesting
  static ({int index, double remaining}) resolveDrag({
    required int current,
    required int count,
    required double travel,
    required double step,
  }) {
    // A zero-width bar would make every amount of travel "at least one step"
    // and the loop below unbounded. Reachable during layout, so it is checked
    // rather than assumed.
    if (step <= 0 || count <= 0) return (index: current, remaining: 0);

    int index = current;
    double remaining = travel;

    while (remaining.abs() >= step) {
      // Dragging left moves forward, the way a page does.
      final int direction = remaining < 0 ? 1 : -1;
      final int next = index + direction;

      if (next < 0 || next >= count) {
        // At either end. Drop the travel so pushing further does not build up
        // a charge that fires the moment the finger turns round.
        remaining = 0;
        break;
      }

      index = next;
      // Toward zero. This is the line that was inverted.
      remaining += direction * step;
    }

    return (index: index, remaining: remaining);
  }

  @override
  State<BulkrNavBar> createState() => _BulkrNavBarState();
}

class _BulkrNavBarState extends State<BulkrNavBar> {
  /// Drag travelled since the last tab change, in logical pixels.
  ///
  /// Accumulated rather than acted on per-event so a slow drag walks the tabs
  /// one at a time instead of firing on every frame, and reset on each change
  /// so a long drag keeps going rather than needing to be lifted.
  double _dragged = 0;

  void _onDragUpdate(DragUpdateDetails details, double barWidth) {
    _dragged += details.delta.dx;

    // A fifth of the bar per tab, so the gesture travels at the speed it looks
    // like it should.
    final double step = barWidth / widget.destinations.length;

    final ({int index, double remaining}) result = BulkrNavBar.resolveDrag(
      current: widget.currentIndex,
      count: widget.destinations.length,
      travel: _dragged,
      step: step,
    );

    _dragged = result.remaining;

    // One call for the whole gesture frame, not one per step: each is a
    // setState on the shell, and a fast drag across four tabs should rebuild
    // once.
    if (result.index != widget.currentIndex) widget.onSelected(result.index);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double width = constraints.maxWidth;

            return GestureDetector(
              onHorizontalDragStart: (_) => _dragged = 0,
              onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
              onHorizontalDragEnd: (_) => _dragged = 0,
              onHorizontalDragCancel: () => _dragged = 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26.r),
                child: BackdropFilter(
                  // The blur is the whole effect, and it is not free: it forces
                  // a saveLayer over the bar's bounds every frame. Bounded to
                  // the pill by the ClipRRect above, which is what keeps it to
                  // a strip rather than the screen.
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    decoration: BoxDecoration(
                      // Translucent rather than opaque — an opaque bar over a
                      // blur is just an opaque bar.
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(26.r),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (int i = 0; i < widget.destinations.length; i++)
                          _NavItem(
                            destination: widget.destinations[i],
                            isSelected: i == widget.currentIndex,
                            onTap: () => widget.onSelected(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.enter,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 14.w : 10.w,
            vertical: 8.h,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNeon : Colors.transparent,
            borderRadius: BorderRadius.circular(18.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                destination.icon,
                color: isSelected ? Colors.black : Colors.white70,
                size: 20.sp,
              ),
              // The label only on the selected item, so the bar stays a row of
              // icons and the current tab is the one that says its name. It is
              // also what makes room for the pill without the bar growing.
              if (isSelected) ...[
                SizedBox(width: 6.w),
                Text(
                  destination.labelKey.tr(),
                  style: GoogleFonts.inter(
                    color: Colors.black,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
