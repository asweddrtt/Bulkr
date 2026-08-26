import 'dart:math' as math;

import '../models/weight_entry.dart';

/// Trend figures derived from the user's own `weight_logs` rows.
///
/// Pure like [CalorieEngine]: no Flutter imports, so the arithmetic behind
/// "+4.2 kg this month" can be unit tested directly. Everything is nullable
/// rather than zero — one weigh-in is a dot, not a trend, and showing 0.0 kg
/// implies a measurement that was never taken.
class ProgressStats {
  ProgressStats({
    required List<WeightEntry> history,
    required this.targetWeightKg,
    DateTime? asOf,
  })  : _history = _sorted(history),
        _asOf = asOf ?? DateTime.now();

  /// Oldest first.
  final List<WeightEntry> _history;
  final DateTime _asOf;
  final double targetWeightKg;

  /// Beyond this a projection is arithmetic, not information.
  static const int _maxProjectionDays = 5 * 365;

  static List<WeightEntry> _sorted(List<WeightEntry> history) {
    final List<WeightEntry> copy = List<WeightEntry>.of(history);
    copy.sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
    return copy;
  }

  int get logCount => _history.length;

  /// A rate needs two points at different times.
  bool get hasTrend => _history.length >= 2;

  double? get startWeightKg => _history.isEmpty ? null : _history.first.weightKg;

  double? get latestWeightKg => _history.isEmpty ? null : _history.last.weightKg;

  DateTime? get lastLoggedAt =>
      _history.isEmpty ? null : _history.last.loggedAt;

  int? get daysSinceLastWeighIn {
    final DateTime? last = lastLoggedAt;
    return last == null ? null : _asOf.difference(last).inDays;
  }

  /// Change between the first and last weigh-in on record.
  double? get totalChangeKg {
    if (!hasTrend) return null;
    return _history.last.weightKg - _history.first.weightKg;
  }

  /// Change across the last [days] days — the "this month" figure at 30.
  ///
  /// Anchored on the earliest weigh-in inside the window, so a user who logs
  /// twice a week and one who logs daily read the same period the same way.
  double? changeOverDays(int days) {
    final DateTime cutoff = _asOf.subtract(Duration(days: days));
    final List<WeightEntry> window = _history
        .where((e) => !e.loggedAt.isBefore(cutoff))
        .toList();
    if (window.length < 2) return null;
    return window.last.weightKg - window.first.weightKg;
  }

  double? get monthlyChangeKg => changeOverDays(30);

  /// Observed kg per week, from the last 30 days when that window holds two
  /// weigh-ins, otherwise across the whole history. Recent behaviour predicts
  /// the next month better than an average dragged back by month one.
  double? get weeklyRateKg {
    final List<WeightEntry> window = _windowForRate();
    if (window.length < 2) return null;

    final double days = window.last.loggedAt
        .difference(window.first.loggedAt)
        .inMinutes /
        (60 * 24);
    // Two entries the same day describe a scale, not a week.
    if (days < 1) return null;

    final double change = window.last.weightKg - window.first.weightKg;
    return change / days * 7;
  }

  List<WeightEntry> _windowForRate() {
    final DateTime cutoff = _asOf.subtract(const Duration(days: 30));
    final List<WeightEntry> recent = _history
        .where((e) => !e.loggedAt.isBefore(cutoff))
        .toList();
    return recent.length >= 2 ? recent : _history;
  }

  /// Kilograms still to go. Negative once the target is passed.
  double? get remainingKg {
    final double? current = latestWeightKg;
    return current == null ? null : targetWeightKg - current;
  }

  bool get isTargetReached {
    final double? current = latestWeightKg;
    final double? start = startWeightKg;
    if (current == null || start == null) return false;
    // Direction-aware: a cut reaches its target from above.
    return targetWeightKg >= start
        ? current >= targetWeightKg
        : current <= targetWeightKg;
  }

  /// How far along the journey from the starting weight to the target, 0-1.
  ///
  /// Null when the target was already met at the starting weight, where there
  /// is no distance to be a fraction of.
  double? get fractionToTarget {
    final double? start = startWeightKg;
    final double? current = latestWeightKg;
    if (start == null || current == null) return null;

    final double distance = targetWeightKg - start;
    if (distance.abs() < 0.05) return null;
    return ((current - start) / distance).clamp(0.0, 1.0);
  }

  /// When the target is reached if the observed rate holds.
  ///
  /// Null when there is no trend, when the rate points away from the target,
  /// or when the answer is years out and therefore meaningless.
  DateTime? get projectedTargetDate {
    final double? rate = weeklyRateKg;
    final double? remaining = remainingKg;
    if (rate == null || remaining == null || isTargetReached) return null;

    // Gaining towards a higher target, or losing towards a lower one.
    final bool movingTowardsTarget = remaining > 0 ? rate > 0 : rate < 0;
    if (!movingTowardsTarget) return null;

    final double weeks = remaining / rate;
    final int days = (weeks * 7).ceil();
    if (days <= 0 || days > _maxProjectionDays) return null;
    return _asOf.add(Duration(days: days));
  }

  /// Body mass index from the latest weigh-in, for the body stats card.
  double? bmi(double heightCm) {
    final double? weight = latestWeightKg;
    if (weight == null || heightCm <= 0) return null;
    final double metres = heightCm / 100;
    return weight / math.pow(metres, 2);
  }
}
