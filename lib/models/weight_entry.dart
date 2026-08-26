import 'package:equatable/equatable.dart';

/// A row from `public.weight_logs` — one weigh-in.
///
/// Onboarding seeds the first of these with the user's starting weight, so the
/// progress chart has a day-one anchor rather than being empty until they log
/// manually.
///
/// One entry per calendar day is the rule: weighing yourself twice on a Tuesday
/// is one Tuesday measurement, not two data points. [latestPerDay] enforces
/// that on the way out of the repository, so rows written before the rule
/// existed read the same way as rows written after it.
class WeightEntry extends Equatable {
  const WeightEntry({required this.weightKg, required this.loggedAt});

  final double weightKg;
  final DateTime loggedAt;

  factory WeightEntry.fromMap(Map<String, dynamic> map) {
    final raw = map['weight_kg'];
    final weight = raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? ''}') ?? 0;

    return WeightEntry(
      weightKg: weight,
      loggedAt: DateTime.tryParse('${map['logged_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// The calendar day this weigh-in belongs to, in the user's local time.
  ///
  /// Local rather than UTC deliberately: "today" is the day the user was
  /// standing on the scale, so a 1 AM weigh-in in UTC+3 belongs to that
  /// morning, not to the previous day.
  DateTime get loggedOn =>
      DateTime(loggedAt.year, loggedAt.month, loggedAt.day);

  /// Collapses [entries] to one weigh-in per calendar day — the last one
  /// logged that day — sorted oldest first.
  ///
  /// The last log wins because it is the correction: someone who logs 88.0 and
  /// then 88.4 an hour later is fixing a misread scale or a fat thumb, and the
  /// figure they typed most recently is the one they meant to keep.
  static List<WeightEntry> latestPerDay(Iterable<WeightEntry> entries) {
    final Map<DateTime, WeightEntry> byDay = <DateTime, WeightEntry>{};

    for (final WeightEntry entry in entries) {
      final WeightEntry? kept = byDay[entry.loggedOn];
      if (kept == null || !entry.loggedAt.isBefore(kept.loggedAt)) {
        byDay[entry.loggedOn] = entry;
      }
    }

    return byDay.values.toList()
      ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));
  }

  @override
  List<Object?> get props => [weightKg, loggedAt];
}
