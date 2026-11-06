// Enumerations used by the Chapter 4 classes. `db` is the value stored in
// the matching Supabase CHECK constraint.

T _byDb<T extends Enum>(
  List<T> values,
  String? raw,
  String Function(T) db,
  T fallback,
) {
  for (final v in values) {
    if (db(v) == raw) return v;
  }
  return fallback;
}

enum AuthProvider {
  email('EMAIL'),
  google('GOOGLE'),
  both('BOTH');

  final String db;
  const AuthProvider(this.db);
  static AuthProvider fromDb(String? s) => _byDb(values, s, (v) => v.db, email);
}

enum Gender {
  male('Male'),
  female('Female');

  final String db;
  const Gender(this.db);
  static Gender? fromDb(String? s) =>
      s == null ? null : _byDb(values, s, (v) => v.db, male);
}

enum RiskLevel {
  low('Low'),
  medium('Medium'),
  high('High');

  final String db;
  const RiskLevel(this.db);
  static RiskLevel fromDb(String? s) => _byDb(values, s, (v) => v.db, high);
}

/// Ordered from least to most demanding so `index` can be compared.
enum ExerciseIntensity {
  low('LOW'),
  moderate('MODERATE'),
  vigorous('VIGOROUS');

  final String db;
  const ExerciseIntensity(this.db);
  static ExerciseIntensity fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, low);
}

enum RecoveryStage {
  early('EARLY'),
  intermediate('INTERMEDIATE'),
  advanced('ADVANCED');

  final String db;
  const RecoveryStage(this.db);
  static RecoveryStage fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, early);
}

enum MobilityLevel {
  low('LOW'),
  moderate('MODERATE'),
  high('HIGH');

  final String db;
  const MobilityLevel(this.db);
  static MobilityLevel fromDb(String? s) => _byDb(values, s, (v) => v.db, low);
}

enum PlanStatus {
  active('ACTIVE'),
  completed('COMPLETED'),
  abandoned('ABANDONED');

  final String db;
  const PlanStatus(this.db);
  static PlanStatus fromDb(String? s) => _byDb(values, s, (v) => v.db, active);
}

enum CompletionStatus {
  completed('COMPLETED'),
  retried('RETRIED'),
  abandoned('ABANDONED');

  final String db;
  const CompletionStatus(this.db);
  static CompletionStatus fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, abandoned);
}

enum MessageSender {
  patient('PATIENT'),
  system('SYSTEM');

  final String db;
  const MessageSender(this.db);
  static MessageSender fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, system);
}

enum ReminderType {
  exercise('EXERCISE'),
  healthLog('HEALTH_LOG'),
  meal('MEAL');

  final String db;
  const ReminderType(this.db);
  static ReminderType fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, exercise);
}

enum NotificationType {
  reminder('REMINDER'),
  alert('ALERT');

  final String db;
  const NotificationType(this.db);
  static NotificationType fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, reminder);
}

enum DeliveryStatus {
  delivered('DELIVERED'),
  failed('FAILED'),
  suppressed('SUPPRESSED');

  final String db;
  const DeliveryStatus(this.db);
  static DeliveryStatus fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, delivered);
}

enum ConditionCategory {
  cardiovascular('CARDIOVASCULAR'),
  metabolic('METABOLIC'),
  musculoskeletal('MUSCULOSKELETAL'),
  respiratory('RESPIRATORY'),
  // 11 Oct: the conditions added to the profile
  neurological('NEUROLOGICAL'),
  renal('RENAL'),
  oncology('ONCOLOGY'),
  reproductive('REPRODUCTIVE'),
  other('OTHER');

  final String db;
  const ConditionCategory(this.db);
  static ConditionCategory fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, metabolic);
}

enum LimitationCategory {
  mobility('MOBILITY'),
  balance('BALANCE');

  final String db;
  const LimitationCategory(this.db);
  static LimitationCategory fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, mobility);
}

enum RestrictionType {
  allergy('ALLERGY'),
  intolerance('INTOLERANCE'),
  diet('DIET'),
  religious('RELIGIOUS');

  final String db;
  const RestrictionType(this.db);
  static RestrictionType fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, diet);
}

/// Profile status returned by UC1000 Retrieve Profile Information.
enum ProfileStatus {
  complete,
  notConfigured,
  incomplete,
  stale,
  cached,
  error,
  unauthenticated,
}

// ---------------------------------------------------------------- M200 / M400 / M700 (Jun Ting)

/// biometric_reading.metric_type (FR200_001 to FR200_003).
enum MetricType {
  bloodPressure('BLOOD_PRESSURE', 'Blood pressure', 'mmHg'),
  bloodGlucose('BLOOD_GLUCOSE', 'Blood glucose', 'mmol/L'),
  bodyWeight('BODY_WEIGHT', 'Body weight', 'kg');

  final String db;
  final String label;
  final String unit;
  const MetricType(this.db, this.label, this.unit);
  static MetricType fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, bloodPressure);
}

/// biometric_reading.measurement_context, required with a glucose reading (FR200_002).
/// The label is the full name shown to the patient (UI Design, Monitoring Screen).
enum MeasurementContext {
  fasting('FASTING', 'Fasting (before a meal)'),
  postMeal('POST_MEAL', 'After a meal'),
  random('RANDOM', 'Random (any time)');

  final String db;
  final String label;
  const MeasurementContext(this.db, this.label);
  static MeasurementContext? fromDb(String? s) =>
      s == null ? null : _byDb(values, s, (v) => v.db, random);
}

/// biometric_reading.source (UC700 C8, FR200_010).
enum ReadingSource {
  manual('MANUAL', 'Manual'),
  imported('IMPORT', 'Imported');

  final String db;
  final String label;
  const ReadingSource(this.db, this.label);
  static ReadingSource fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, manual);
}

enum AnomalyType {
  deviation('DEVIATION'),
  sustainedTrend('SUSTAINED_TREND');

  final String db;
  const AnomalyType(this.db);
  static AnomalyType fromDb(String? s) =>
      _byDb(values, s, (v) => v.db, deviation);
}

/// Severity of an anomaly and of its alert (UC600 C7, C8). Ordered: index compares.
enum Severity {
  low('Low'),
  medium('Medium'),
  high('High');

  final String db;
  const Severity(this.db);
  static Severity fromDb(String? s) => _byDb(values, s, (v) => v.db, low);
  static Severity? tryDb(String? s) => s == null ? null : fromDb(s);
}

/// Health Score bands (UC600 C12).
enum ScoreBand {
  good('GOOD', 'Good', 80),
  fair('FAIR', 'Fair', 65),
  needsAttention('NEEDS_ATTENTION', 'Needs attention', 50),
  atRisk('AT_RISK', 'At risk', 0);

  final String db;
  final String label;
  final int from;
  const ScoreBand(this.db, this.label, this.from);
  static ScoreBand? fromDb(String? s) =>
      s == null ? null : _byDb(values, s, (v) => v.db, atRisk);
  static ScoreBand forScore(int score) =>
      values.firstWhere((b) => score >= b.from, orElse: () => atRisk);
}

enum PeriodComparison {
  better('BETTER', 'Better'),
  unchanged('UNCHANGED', 'Unchanged'),
  worse('WORSE', 'Worse');

  final String db;
  final String label;
  const PeriodComparison(this.db, this.label);
  static PeriodComparison? fromDb(String? s) =>
      s == null ? null : _byDb(values, s, (v) => v.db, unchanged);
}

/// meal_log.meal_type and planned_meal.meal_slot (FR700_029).
enum MealSlot {
  breakfast('BREAKFAST', 'Breakfast'),
  lunch('LUNCH', 'Lunch'),
  dinner('DINNER', 'Dinner'),
  snack('SNACK', 'Snack');

  final String db;
  final String label;
  const MealSlot(this.db, this.label);
  static MealSlot fromDb(String? s) => _byDb(values, s, (v) => v.db, snack);

  /// The slot a meal eaten at [t] most likely fills.
  static MealSlot forTime(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 11) return breakfast;
    if (h >= 11 && h < 15) return lunch;
    if (h >= 18 && h < 22) return dinner;
    return snack;
  }
}

/// meal_log.entry_method (FR700_050).
enum EntryMethod {
  recognition('RECOGNITION'),
  manual('MANUAL');

  final String db;
  const EntryMethod(this.db);
  static EntryMethod fromDb(String? s) => _byDb(values, s, (v) => v.db, manual);
}

/// suitability_verdict.verdict (UC900 C8). Ordered: index compares, so max = most restrictive.
enum Verdict {
  suitable('SUITABLE', 'Suitable'),
  caution('CAUTION', 'Caution'),
  notSuitable('NOT_SUITABLE', 'Not suitable');

  final String db;
  final String label;
  const Verdict(this.db, this.label);
  static Verdict fromDb(String? s) => _byDb(values, s, (v) => v.db, suitable);
}

/// diet_plan.plan_type (FR700_029, FR700_030).
enum PlanType {
  daily('DAILY'),
  weekly('WEEKLY');

  final String db;
  const PlanType(this.db);
  static PlanType fromDb(String? s) => _byDb(values, s, (v) => v.db, daily);
}
