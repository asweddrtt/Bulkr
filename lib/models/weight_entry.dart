import 'package:equatable/equatable.dart';

/// A row from `public.weight_logs` — one weigh-in.
///
/// Onboarding seeds the first of these with the user's starting weight, so the
/// progress chart has a day-one anchor rather than being empty until they log
/// manually.
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

  @override
  List<Object?> get props => [weightKg, loggedAt];
}
