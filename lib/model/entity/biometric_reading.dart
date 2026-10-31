import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';

/// One vital-sign reading, typed in by the patient or imported from the health data source
/// (Table 4.35). Blood pressure, blood glucose and body weight share one table, so a new metric
/// needs no new table (ASR_04).
class BiometricReading {
  final String readingId;
  final String accountId;
  final MetricType metricType;

  /// Systolic pressure, glucose (mmol/L) or weight (kg).
  final double primaryValue;

  /// Diastolic pressure; blood pressure only.
  final double? secondaryValue;

  /// Required with a glucose reading (FR200_002).
  final MeasurementContext? measurementContext;
  final ReadingSource source;
  final DateTime recordedAt;

  const BiometricReading({
    required this.readingId,
    required this.accountId,
    required this.metricType,
    required this.primaryValue,
    this.secondaryValue,
    this.measurementContext,
    this.source = ReadingSource.manual,
    required this.recordedAt,
  });

  /// Whether every value falls inside the plausible range for its metric (UC700 C7, FR200_004).
  bool isPlausible() {
    final (lo, hi) = AppConstants.plausibleRange(metricType);
    if (primaryValue < lo || primaryValue > hi) return false;
    if (metricType == MetricType.bloodPressure) {
      final d = secondaryValue;
      if (d == null) return false;
      if (d < AppConstants.diastolicMin || d > AppConstants.diastolicMax) {
        return false;
      }
    }
    return true;
  }

  /// Systolic greater than diastolic (FR200_005). True for the other metrics.
  bool isValidBloodPressure() =>
      metricType != MetricType.bloodPressure ||
      (secondaryValue != null && primaryValue > secondaryValue!);

  /// Later than the device clock (FR200_006). One minute of slack for the time picker.
  bool isFutureDated([DateTime? now]) =>
      recordedAt.isAfter((now ?? DateTime.now()).add(const Duration(minutes: 1)));

  /// Account, metric and timestamp: an import with the same key is a duplicate (FR200_011).
  String duplicateKey() =>
      '$accountId|${metricType.db}|${recordedAt.toUtc().millisecondsSinceEpoch}';

  /// Within 5 minutes of [other] for the same metric (UC700 C11).
  bool duplicates(BiometricReading other) =>
      other.metricType == metricType &&
      other.recordedAt.difference(recordedAt).abs() <=
          AppConstants.duplicateWindow;

  /// Formatted value with units, e.g. "128/82 mmHg".
  String display() => switch (metricType) {
    MetricType.bloodPressure =>
      '${primaryValue.round()}/${(secondaryValue ?? 0).round()} mmHg',
    MetricType.bloodGlucose => '${primaryValue.toStringAsFixed(1)} mmol/L',
    MetricType.bodyWeight => '${primaryValue.toStringAsFixed(1)} kg',
  };

  /// What [display] shows without the unit.
  String valueText() => switch (metricType) {
    MetricType.bloodPressure =>
      '${primaryValue.round()}/${(secondaryValue ?? 0).round()}',
    _ => primaryValue.toStringAsFixed(1),
  };

  Map<String, dynamic> toJson() => {
    'reading_id': readingId,
    'account_id': accountId,
    'metric_type': metricType.db,
    'primary_value': primaryValue,
    'secondary_value': secondaryValue,
    'measurement_context': measurementContext?.db,
    'source': source.db,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };

  /// The pseudonymous form sent to the AI server: no account id (FR400_036, NFR_15).
  Map<String, dynamic> toAnalysisJson() => {
    'reading_id': readingId,
    'metric_type': metricType.db,
    'primary_value': primaryValue,
    'secondary_value': secondaryValue,
    'measurement_context': measurementContext?.db,
    'recorded_at': recordedAt.toLocal().toIso8601String(),
  };

  factory BiometricReading.fromJson(Map<String, dynamic> j) => BiometricReading(
    readingId: j['reading_id'] as String,
    accountId: j['account_id'] as String,
    metricType: MetricType.fromDb(j['metric_type'] as String?),
    primaryValue: (j['primary_value'] as num).toDouble(),
    secondaryValue: (j['secondary_value'] as num?)?.toDouble(),
    measurementContext: MeasurementContext.fromDb(
      j['measurement_context'] as String?,
    ),
    source: ReadingSource.fromDb(j['source'] as String?),
    recordedAt: DateTime.parse(j['recorded_at'] as String).toLocal(),
  );
}

/// One completed exercise session as M200 shows it (FR200_015, FR200_016, UC700 C14).
class ActivityRecord {
  final String sessionId;
  final String exerciseName;
  final int durationSec;
  final DateTime completedAt;

  const ActivityRecord({
    required this.sessionId,
    required this.exerciseName,
    required this.durationSec,
    required this.completedAt,
  });

  Map<String, dynamic> toAnalysisJson() => {
    'completed_at': completedAt.toLocal().toIso8601String(),
    'duration_sec': durationSec,
  };
}

/// Aggregate of the selected period (UC700 C2, FR200_019).
class PeriodSummary {
  final int sessions;
  final int exerciseMinutes;
  final int readings;

  /// Mean of each metric; blood pressure as "systolic/diastolic".
  final Map<MetricType, String> means;

  const PeriodSummary({
    required this.sessions,
    required this.exerciseMinutes,
    required this.readings,
    required this.means,
  });

  static PeriodSummary of(
    List<BiometricReading> readings,
    List<ActivityRecord> sessions,
  ) {
    final means = <MetricType, String>{};
    for (final m in MetricType.values) {
      final rs = readings.where((r) => r.metricType == m).toList();
      if (rs.isEmpty) continue;
      final p = rs.map((r) => r.primaryValue).reduce((a, b) => a + b) / rs.length;
      if (m == MetricType.bloodPressure) {
        final ds = rs.where((r) => r.secondaryValue != null).toList();
        final d = ds.isEmpty
            ? 0
            : ds.map((r) => r.secondaryValue!).reduce((a, b) => a + b) /
                  ds.length;
        means[m] = '${p.round()}/${d.round()} ${m.unit}';
      } else {
        means[m] = '${p.toStringAsFixed(1)} ${m.unit}';
      }
    }
    return PeriodSummary(
      sessions: sessions.length,
      exerciseMinutes: (sessions.fold<int>(0, (a, s) => a + s.durationSec) / 60)
          .round(),
      readings: readings.length,
      means: means,
    );
  }
}
