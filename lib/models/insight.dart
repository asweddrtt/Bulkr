import 'package:equatable/equatable.dart';

/// How an insight should read: a nudge, a warning, or a well done.
enum InsightTone { neutral, positive, warning }

/// What tapping an insight does. The screen owns the implementation — the
/// engine only says which action the advice implies.
enum InsightAction { none, logWeight, recalculate }

/// Chooses the icon. Kept as a domain concept rather than an [IconData] so the
/// engine stays free of Flutter imports and testable on its own.
enum InsightKind { weighIn, plan, pace, nutrition, hydration, habit, milestone }

/// A single piece of advice on the profile screen.
///
/// Carries translation keys rather than sentences: the engine decides *what*
/// to say from the user's data, the widget decides how it reads.
class Insight extends Equatable {
  const Insight({
    required this.id,
    required this.kind,
    required this.titleKey,
    required this.bodyKey,
    this.args = const {},
    this.tone = InsightTone.neutral,
    this.action = InsightAction.none,
  });

  /// Stable across rebuilds, so list keys and tests don't depend on ordering.
  final String id;

  final InsightKind kind;
  final String titleKey;
  final String bodyKey;

  /// Named arguments for [bodyKey] and [titleKey].
  final Map<String, String> args;

  final InsightTone tone;
  final InsightAction action;

  @override
  List<Object?> get props => [id, kind, titleKey, bodyKey, args, tone, action];
}
