import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import 'animations/motion.dart';

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
/// ## The drag
///
/// The highlight follows the finger continuously and settles when it is
/// lifted, rather than jumping a whole tab once the drag crosses a threshold.
/// That difference is the whole feel of it: a stepping indicator tells you what
/// happened, a tracking one shows you what is happening, and the second is what
/// makes a gesture feel attached to the thing it is moving.
///
/// The tabs are an [IndexedStack], so the content does not slide with the
/// highlight — it switches as the highlight passes each tab's centre. Sliding
/// the content too would mean a full-screen [PageView], and the Feed already
/// swipes between For You and Discover while Meals swipes between its two
/// tabs. The gesture lives on the bar precisely so it is not fighting those.
class BulkrNavBar extends StatefulWidget {
  const BulkrNavBar({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onSelected,
    this.visible = true,
  });

  final List<NavDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  /// False while the user is reading downwards.
  ///
  /// The bar slides out rather than shrinking or fading in place: a
  /// half-transparent bar is still something to look past, and a shorter one
  /// moves its own tap targets while a finger is on the way to them.
  ///
  /// It keeps its slot in the layout either way, so the space every screen
  /// reserves at the bottom does not change as it comes and goes — content
  /// that reflowed on every scroll direction change would be far worse than a
  /// bar that is briefly not there.
  final bool visible;

  /// The bar's own height, above whatever safe-area inset sits below it.
  static double get barHeight => 62.h;

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
  /// A tab's [Scaffold] is nested inside the shell's and places its button at
  /// the bottom of itself, which with `extendBody: true` is underneath the
  /// glass. Lifting it by [barHeight] + [barMargin] was not enough and the
  /// shortfall was exactly the home indicator: on a 390x844 screen with a
  /// 34px bottom inset the button's lower 18px sat under the bar.
  ///
  /// The shell already knows the right number. A [Scaffold] with
  /// `extendBody: true` and a bottom bar reports what its body must clear as
  /// `MediaQuery.padding.bottom` — here 62 + 12 + 34 = 108 — and the [Scaffold]
  /// below only lifts its button for the keyboard, so the padding is there to
  /// be read and nothing reads it. Note it is `padding`, not `viewPadding`:
  /// inside the shell's body that one is zero, which is why guessing at this
  /// rather than measuring it produces a fix that changes nothing.
  ///
  /// Falls back for a screen that is not inside the shell — a pushed route has
  /// no bar to clear, and its own safe-area inset is not a lift.
  static double fabInsetFor(BuildContext context) {
    final double reserved = MediaQuery.paddingOf(context).bottom;
    final double own = barHeight + barMargin;
    return reserved >= own ? reserved : own;
  }

  /// Where the highlight sits after a drag of [dx], in tab units.
  ///
  /// Continuous rather than stepped: 2.4 means the highlight is four tenths of
  /// the way from the third tab to the fourth, and it is drawn there. The
  /// selection is this rounded, so the content switches as the highlight
  /// crosses each centre.
  ///
  /// The highlight goes the way the finger goes — drag left and it moves left,
  /// to a lower index. That is the opposite of a [PageView], where dragging
  /// left advances a page, and it is right here for the same reason it is
  /// wrong there: on a page you are dragging the content past a fixed frame,
  /// and on this bar you have your finger on the highlight itself.
  ///
  /// Pure so it can be tested, and it is. The stepped version this replaces
  /// ran a `while` loop that consumed travel with the wrong sign and hung the
  /// UI thread — there is no loop here at all, which is the real fix.
  ///
  /// Clamped to the ends rather than wrapping, so dragging past the last tab
  /// cannot build up travel that fires the moment the finger turns round.
  static double positionAfterDrag({
    required double position,
    required double dx,
    required double slotWidth,
    required int count,
  }) {
    // A bar with no width is reachable during layout, and dividing by it would
    // put the highlight at infinity.
    if (slotWidth <= 0 || count <= 0) return position;

    return (position + dx / slotWidth).clamp(0.0, (count - 1).toDouble());
  }

  /// How strongly the tab at [index] is lit, 0 to 1.
  ///
  /// Fades between neighbours as the highlight passes, so mid-drag two tabs are
  /// partly lit rather than one being abruptly handed the colour.
  static double emphasisFor(double position, int index) =>
      (1 - (position - index).abs()).clamp(0.0, 1.0);

  @override
  State<BulkrNavBar> createState() => _BulkrNavBarState();
}

class _BulkrNavBarState extends State<BulkrNavBar>
    with SingleTickerProviderStateMixin {
  /// Where the highlight is, in tab units. Fractional while dragging.
  late double _position = widget.currentIndex.toDouble();

  /// Ends of the settle animation, read every frame by the controller's
  /// listener — so the highlight can be driven by a finger or by a curve
  /// without the build method needing to know which.
  late double _from = _position;
  late double _to = _position;

  late final AnimationController _controller;
  late final CurvedAnimation _curve;

  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.base);
    _curve = CurvedAnimation(parent: _controller, curve: Motion.emphasis);
    _controller.addListener(() {
      setState(() => _position = lerpDouble(_from, _to, _curve.value)!);
    });
  }

  @override
  void didUpdateWidget(BulkrNavBar old) {
    super.didUpdateWidget(old);

    // A tap, or a selection made anywhere else, glides rather than jumps.
    // Skipped mid-drag: the drag is already moving the highlight, and it is the
    // drag that caused this index to change — animating to it would be the bar
    // fighting the finger.
    if (!_isDragging && widget.currentIndex != old.currentIndex) {
      _animateTo(widget.currentIndex.toDouble());
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target) {
    _from = _position;
    _to = target;
    _controller.forward(from: 0);
  }

  void _onDragStart() {
    _isDragging = true;
    // Whatever settle was in flight is now the finger's business.
    _controller.stop();
  }

  void _onDragUpdate(DragUpdateDetails details, double slotWidth) {
    setState(() {
      _position = BulkrNavBar.positionAfterDrag(
        position: _position,
        dx: details.delta.dx,
        slotWidth: slotWidth,
        count: widget.destinations.length,
      );
    });

    // Live, as the highlight passes each centre — so the screen behind the
    // glass is already the one the finger is over by the time it lifts, and
    // lifting confirms rather than commits.
    final int nearest = _position.round();
    if (nearest != widget.currentIndex) widget.onSelected(nearest);
  }

  void _onDragEnd() {
    _isDragging = false;
    // Settles onto whichever tab it is nearest, which is the one already
    // selected — so this is the highlight catching up with the content, never
    // a second change of screen.
    _animateTo(widget.currentIndex.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final int count = widget.destinations.length;

    return AnimatedSlide(
      // 1.35 rather than 1: its own height clears the bar but not the margin
      // below it, which leaves a sliver of glass along the bottom edge.
      offset: Offset(0, widget.visible ? 0 : 1.35),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        // Mid-slide the bar is still on screen and still hit-testable, and a
        // tab that answers a tap aimed at the content underneath it is worse
        // than one that is slow to leave.
        ignoring: !widget.visible,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, BulkrNavBar.barMargin),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26.r),
              child: BackdropFilter(
                // The blur is the whole effect, and it is not free: it forces a
                // saveLayer over the bar's bounds every frame. Bounded to the pill
                // by the ClipRRect above, which keeps it to a strip rather than the
                // whole screen.
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  height: BulkrNavBar.barHeight,
                  decoration: BoxDecoration(
                    // Translucent rather than opaque — an opaque bar over a blur is
                    // just an opaque bar.
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(26.r),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final double slotWidth = constraints.maxWidth / count;

                      return GestureDetector(
                        // Opaque so the whole bar drags, including the gaps between
                        // icons.
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragStart: (_) => _onDragStart(),
                        onHorizontalDragUpdate: (d) =>
                            _onDragUpdate(d, slotWidth),
                        onHorizontalDragEnd: (_) => _onDragEnd(),
                        onHorizontalDragCancel: _onDragEnd,
                        child: Stack(
                          children: [
                            // Under the icons, so it reads as a highlight moving
                            // beneath them rather than a card sliding over them.
                            Positioned(
                              left: _position * slotWidth,
                              top: 6.h,
                              bottom: 6.h,
                              width: slotWidth,
                              child: Center(
                                child: Container(
                                  width: slotWidth - 8.w,
                                  height: double.infinity,
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryNeon,
                                    borderRadius: BorderRadius.circular(18.r),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (int i = 0; i < count; i++)
                                  SizedBox(
                                    width: slotWidth,
                                    child: _NavItem(
                                      destination: widget.destinations[i],
                                      emphasis: BulkrNavBar.emphasisFor(
                                        _position,
                                        i,
                                      ),
                                      // Taps still work while the bar drags: a
                                      // horizontal drag recogniser and a tap
                                      // recogniser do not compete, because a tap
                                      // has no horizontal travel to claim.
                                      onTap: () => widget.onSelected(i),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.emphasis,
    required this.onTap,
  });

  final NavDestination destination;

  /// 0 when the highlight is elsewhere, 1 when it is centred here, and in
  /// between while it passes.
  final double emphasis;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Lerped rather than switched, so a tab being passed over does not blink
    // black and back. The colours have to cross while the pill does.
    final Color tint = Color.lerp(Colors.white70, Colors.black, emphasis)!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(destination.icon, color: tint, size: 20.sp),
          SizedBox(height: 3.h),
          Text(
            destination.labelKey.tr(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: tint,
              fontSize: 9.sp,
              // Weight follows the highlight too. Subtle, and it is what stops
              // a label looking like it belongs to the tab next door halfway
              // through a drag.
              fontWeight: emphasis > 0.5 ? FontWeight.bold : FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
