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
