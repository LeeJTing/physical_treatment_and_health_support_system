import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';

/// One detected abnormal reading or sustained trend (Table 4.41; FR400_012 to FR400_016).
class AnomalyEvent {
  final String anomalyId;
  final String accountId;
  final String? readingId;
  final MetricType metricType;
  final AnomalyType anomalyType;
  final Severity severity;

  /// Plain-language explanation (UC600 C9): metric, value, baseline range, direction, severity
  /// and the next step (FR400_015).
  final String explanationText;
  final DateTime detectedAt;

  const AnomalyEvent({
    required this.anomalyId,
    required this.accountId,
    this.readingId,
    required this.metricType,
    required this.anomalyType,
    required this.severity,
    required this.explanationText,
    required this.detectedAt,
  });

  /// Forces the full-screen warning and the consult-a-professional advice (FR600_010, FR600_012).
  bool isHighSeverity() => severity == Severity.high;

  String explain() => explanationText;

  /// Same reading, same kind: already recorded, so not alerted twice.
  String dedupeKey() => '${readingId ?? metricType.db}|${anomalyType.db}';

  /// The alert passed to M600 (FR400_017, FR600_009).
  NotificationLog toNotification({
    DeliveryStatus status = DeliveryStatus.delivered,
  }) => NotificationLog(
    notificationId: newId(),
    accountId: accountId,
    anomalyId: anomalyId,
    notificationType: NotificationType.alert,
    severity: severity,
    messageBody: explanationText,
    deliveryStatus: status,
    issuedAt: DateTime.now(),
  );

  /// From one item of the /analyse "anomalies" list.
  factory AnomalyEvent.fromServer(
    Map<String, dynamic> j,
    String accountId, [
    DateTime? detectedAt,
  ]) =>
      AnomalyEvent(
        anomalyId: newId(),
        accountId: accountId,
        readingId: j['reading_id'] as String?,
        metricType: MetricType.fromDb(j['metric_type'] as String?),
        anomalyType: AnomalyType.fromDb(j['anomaly_type'] as String?),
        severity: Severity.fromDb(j['severity'] as String?),
        explanationText: j['explanation_text'] as String,
        detectedAt: detectedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
    'anomaly_id': anomalyId,
    'account_id': accountId,
    'reading_id': readingId,
    'metric_type': metricType.db,
    'anomaly_type': anomalyType.db,
    'severity': severity.db,
    'explanation_text': explanationText,
    'detected_at': detectedAt.toUtc().toIso8601String(),
  };

  factory AnomalyEvent.fromJson(Map<String, dynamic> j) => AnomalyEvent(
    anomalyId: j['anomaly_id'] as String,
    accountId: j['account_id'] as String,
    readingId: j['reading_id'] as String?,
    metricType: MetricType.fromDb(j['metric_type'] as String?),
    anomalyType: AnomalyType.fromDb(j['anomaly_type'] as String?),
    severity: Severity.fromDb(j['severity'] as String?),
    explanationText: j['explanation_text'] as String,
    detectedAt: DateTime.parse(j['detected_at'] as String).toLocal(),
  );
}
