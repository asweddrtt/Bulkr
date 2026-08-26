import 'package:flutter/material.dart';

import 'motion.dart';

/// A number that counts up to its value instead of simply appearing.
///
/// Used for the calorie target on the reveal screen. The whole flow builds
/// towards that one figure, and watching it climb reads as a result being
/// computed rather than a value being displayed.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    this.style,
    this.formatter,
    this.textAlign,
    this.duration = Motion.reveal,
    this.curve = Motion.emphasis,
  });

  final int value;
  final TextStyle? style;

  /// Formats each intermediate value. Without one, the raw integer is shown.
  final String Function(int value)? formatter;

  final TextAlign? textAlign;
  final Duration duration;
  final Curve curve;

  String _format(int value) => formatter?.call(value) ?? '$value';

  @override
  Widget build(BuildContext context) {
    // Reduced motion gets the final number immediately — the information
    // matters, the theatre doesn't.
    if (Motion.reduced(context)) {
      return Text(_format(value), style: style, textAlign: textAlign);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: curve,
      builder: (context, animatedValue, _) => Text(
        _format(animatedValue.round()),
        style: style,
        textAlign: textAlign,
      ),
    );
  }
}
