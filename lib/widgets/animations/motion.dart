import 'package:flutter/material.dart';

/// Central motion tokens.
///
/// Durations and curves live here rather than scattered through widgets so the
/// whole flow moves at one tempo — the thing that separates "animated" from
/// "polished" is consistency, not the individual effects.
///
/// The house style is restrained: motion exists to show what changed and where
/// it came from, and has to still feel right on the tenth run, not just the
/// first.
class Motion {
  const Motion._();

  /// Press feedback, selection changes — should feel instant.
  static const Duration fast = Duration(milliseconds: 140);

  /// Page transitions and most state changes.
  static const Duration base = Duration(milliseconds: 280);

  /// Content sliding into place on first paint.
  static const Duration entrance = Duration(milliseconds: 320);

  /// The calorie count-up on the reveal screen. Long on purpose: a number has
  /// to be readable while it moves, and this is the one moment in the flow
  /// worth drawing out.
  static const Duration reveal = Duration(milliseconds: 850);

  /// Gap between successive items in a staggered group.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Decelerating — for things arriving.
  static const Curve enter = Curves.easeOutCubic;

  /// Accelerating — for things leaving.
  static const Curve exit = Curves.easeInCubic;

  /// Stronger deceleration, for the reveal.
  static const Curve emphasis = Curves.easeOutQuart;

  /// How far content travels on entrance, as a fraction of its own height.
  /// Small on purpose: a long slide reads as sluggish.
  static const Offset entranceOffset = Offset(0, 0.06);

  /// True when the OS asks for reduced motion.
  ///
  /// Every animated widget here honours it. Motion sickness and vestibular
  /// disorders are real, and an accessibility setting the app ignores is worse
  /// than no animation at all.
  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// Collapses a duration to zero when reduced motion is on.
  static Duration scaled(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}
