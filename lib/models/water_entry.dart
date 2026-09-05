import 'package:equatable/equatable.dart';

/// One drink — a row of `water_logs`.
///
/// Rows rather than a running total on the user's row, because a total cannot
/// be undone and cannot be browsed. The tap that adds 250 ml by mistake has a
/// row to delete; yesterday's water still exists tomorrow.
class WaterEntry extends Equatable {
  const WaterEntry({
    required this.id,
    required this.millilitres,
    required this.loggedAt,
  });

  final String id;

  /// Always positive — the column has a CHECK saying so. A drink of zero is
  /// not a drink, and taking one back is a delete, not a negative row.
  final int millilitres;

  final DateTime loggedAt;

  factory WaterEntry.fromRow(Map<String, dynamic> row) => WaterEntry(
        id: '${row['id']}',
        millilitres: _asInt(row['ml']),
        loggedAt:
            DateTime.tryParse('${row['logged_at']}')?.toLocal() ?? DateTime.now(),
      );

  /// `integer` normally arrives as an int, but the same column read through a
  /// different code path can come back as a string — the rest of the app has
  /// `parseGrams` for exactly this, and this is its integer counterpart.
  static int _asInt(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse('${raw ?? ''}'.trim()) ?? 0;
  }

  @override
  List<Object?> get props => [id, millilitres, loggedAt];
}
