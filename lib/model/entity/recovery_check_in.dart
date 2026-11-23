/// Patient-reported symptoms, separate from measured posture and plan progress.
class RecoveryCheckIn {
  final String checkInId, accountId, patientPlanId, notes;
  final DateTime date, updatedAt;
  final int pain, stiffness, difficulty;
  final bool isDemo;
  const RecoveryCheckIn({
    required this.checkInId,
    required this.accountId,
    required this.patientPlanId,
    required this.date,
    required this.updatedAt,
    required this.pain,
    required this.stiffness,
    required this.difficulty,
    this.notes = '',
    this.isDemo = false,
  });

  bool valid(DateTime now) =>
      pain >= 0 &&
      pain <= 10 &&
      stiffness >= 0 &&
      stiffness <= 10 &&
      difficulty >= 1 &&
      difficulty <= 5 &&
      notes.length <= 500 &&
      !DateTime(
        date.year,
        date.month,
        date.day,
      ).isAfter(DateTime(now.year, now.month, now.day));
  Map<String, dynamic> toJson() => {
    'check_in_id': checkInId,
    'account_id': accountId,
    'patient_plan_id': patientPlanId,
    'check_in_date': date.toIso8601String().substring(0, 10),
    'pain': pain,
    'stiffness': stiffness,
    'difficulty': difficulty,
    'notes': notes,
    'is_demo': isDemo,
  };
  factory RecoveryCheckIn.fromJson(Map<String, dynamic> j) => RecoveryCheckIn(
    checkInId: j['check_in_id'] as String,
    accountId: j['account_id'] as String,
    patientPlanId: j['patient_plan_id'] as String,
    date: DateTime.parse(j['check_in_date'] as String),
    updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
    pain: (j['pain'] as num).toInt(),
    stiffness: (j['stiffness'] as num).toInt(),
    difficulty: (j['difficulty'] as num).toInt(),
    notes: j['notes'] as String? ?? '',
    isDemo: j['is_demo'] == true,
  );
}
