// The Chapter 4 entity classes as the Supabase repositories read and write them: toJson then
// fromJson gives the same values back, missing columns take their defaults, and the small rules
// on each class. NFR_17 coverage (22 Oct); the business rules are in models_test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:physical_treatment_and_health_support_system/model/entity/account.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_message.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/chat_report.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/lookups.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/profile_model.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/reminder.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/safety_limit.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/terms_acceptance.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/users.dart';

/// Through a JSON string, as the rows come back from PostgREST.
Map<String, dynamic> _wire(Map<String, dynamic> m) =>
    jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

final _at = DateTime.utc(2026, 10, 22, 9, 30);

void main() {
  group('enums: every db value reads back, unknown values fall back', () {
    void roundTrip<T extends Enum>(
      List<T> values,
      String Function(T) db,
      T? Function(String?) fromDb,
      T? fallback,
    ) {
      for (final v in values) {
        expect(fromDb(db(v)), v);
      }
      expect(fromDb('NOT_A_VALUE'), fallback);
    }

    test('all of them', () {
      roundTrip(
        AuthProvider.values,
        (v) => v.db,
        AuthProvider.fromDb,
        AuthProvider.email,
      );
      roundTrip(Gender.values, (v) => v.db, Gender.fromDb, Gender.male);
      expect(Gender.fromDb(null), isNull);
      roundTrip(
        RiskLevel.values,
        (v) => v.db,
        RiskLevel.fromDb,
        RiskLevel.high,
      );
      roundTrip(
        ExerciseIntensity.values,
        (v) => v.db,
        ExerciseIntensity.fromDb,
        ExerciseIntensity.low,
      );
      roundTrip(
        RecoveryStage.values,
        (v) => v.db,
        RecoveryStage.fromDb,
        RecoveryStage.fromDb(null),
      );
      roundTrip(
        MobilityLevel.values,
        (v) => v.db,
        MobilityLevel.fromDb,
        MobilityLevel.low,
      );
      roundTrip(
        PlanStatus.values,
        (v) => v.db,
        PlanStatus.fromDb,
        PlanStatus.active,
      );
      roundTrip(
        CompletionStatus.values,
        (v) => v.db,
        CompletionStatus.fromDb,
        CompletionStatus.fromDb(null),
      );
      roundTrip(
        MessageSender.values,
        (v) => v.db,
        MessageSender.fromDb,
        MessageSender.fromDb(null),
      );
      roundTrip(
        ReminderType.values,
        (v) => v.db,
        ReminderType.fromDb,
        ReminderType.fromDb(null),
      );
      roundTrip(
        NotificationType.values,
        (v) => v.db,
        NotificationType.fromDb,
        NotificationType.fromDb(null),
      );
      roundTrip(
        DeliveryStatus.values,
        (v) => v.db,
        DeliveryStatus.fromDb,
        DeliveryStatus.fromDb(null),
      );
      roundTrip(
        ConditionCategory.values,
        (v) => v.db,
        ConditionCategory.fromDb,
        ConditionCategory.fromDb(null),
      );
      roundTrip(
        LimitationCategory.values,
        (v) => v.db,
        LimitationCategory.fromDb,
        LimitationCategory.fromDb(null),
      );
      roundTrip(
        RestrictionType.values,
        (v) => v.db,
        RestrictionType.fromDb,
        RestrictionType.fromDb(null),
      );
      roundTrip(
        TermsAgeGroup.values,
        (v) => v.db,
        TermsAgeGroup.fromDb,
        TermsAgeGroup.adult,
      );
    });
  });

  test('Account: row round trip, defaults, copyWith and the stale import', () {
    final a = Account(
      accountId: 'a1',
      email: 'p@x.test',
      username: 'pat',
      authProvider: AuthProvider.both,
      isEmailVerified: true,
      healthSourceConnected: true,
      healthSourceLastSync: _at,
      createdAt: _at,
    );
    final b = Account.fromJson(_wire(a.toJson()));
    expect(b.toJson(), a.toJson());
    expect(b.isActivated(), isTrue);
    expect(b.importIsStale(_at.add(const Duration(hours: 25))), isTrue);
    expect(b.importIsStale(_at.add(const Duration(hours: 1))), isFalse);
    final bare = Account.fromJson({
      'account_id': 'a2',
      'email': 'q@x.test',
      'created_at': _at.toIso8601String(),
    });
    expect(bare.username, '');
    expect(bare.authProvider, AuthProvider.email);
    expect(bare.healthSourceLastSync, isNull);
    expect(bare.importIsStale(), isFalse);
    final c = bare.copyWith(username: 'q', isEmailVerified: true);
    expect((c.username, c.isEmailVerified, c.email), ('q', true, 'q@x.test'));
  });

  test('TermsAcceptance: row round trip, with and without a guardian', () {
    final t = TermsAcceptance(
      acceptanceId: 't1',
      accountId: 'a1',
      termsVersion: '1.0',
      acceptedAt: _at,
      language: 'ms',
      healthDataConsent: true,
      ageGroup: TermsAgeGroup.minor,
      guardianName: 'Siti',
      guardianRelationship: 'PARENT',
    );
    expect(TermsAcceptance.fromJson(_wire(t.toJson())).toJson(), t.toJson());
    final bare = TermsAcceptance.fromJson({
      'acceptance_id': 't2',
      'account_id': 'a1',
      'terms_version': '1.0',
      'accepted_at': _at.toIso8601String(),
    });
    expect(bare.language, 'en');
    expect(bare.healthDataConsent, isFalse);
    expect(bare.ageGroup, TermsAgeGroup.adult);
    expect(bare.guardianName, isNull);
  });

  test('ChatMessage: row round trip and who sent it', () {
    final m = ChatMessage(
      messageId: 'm1',
      accountId: 'a1',
      patientPlanId: 'pp1',
      sender: MessageSender.patient,
      questionCategory: 'pain',
      messageText: 'my knee hurts',
      isMatched: false,
      createdAt: _at,
    );
    final b = ChatMessage.fromJson(_wire(m.toJson()));
    expect(b.toJson(), m.toJson());
    expect(b.fromPatient, isTrue);
    final bare = ChatMessage.fromJson({
      'message_id': 'm2',
      'account_id': 'a1',
      'message_text': 'hi',
      'created_at': _at.toIso8601String(),
    });
    expect(bare.isMatched, isTrue);
    expect(bare.patientPlanId, isNull);
  });

  test('SafetyLimit: row round trip and the remaining amounts', () {
    const s = SafetyLimit(
      safetyLimitId: 's1',
      profileId: 'p1',
      maxExerciseIntensity: ExerciseIntensity.moderate,
      maxSessionDurationMin: 30,
      dailyCalorieTarget: 1800,
      dailySodiumLimitMg: 2000,
      dailySugarLimitG: 50,
      isCurrent: false,
    );
    expect(SafetyLimit.fromJson(_wire(s.toJson())).toJson(), s.toJson());
    expect(s.sodiumRemaining(500), 1500);
    expect(s.sugarRemaining(20), 30);
    expect(s.energyRemaining(800), 1000);
    final bare = SafetyLimit.fromJson({
      'safety_limit_id': 's2',
      'max_session_duration_min': 15,
      'daily_calorie_target': 1600,
      'daily_sodium_limit_mg': 1500,
      'daily_sugar_limit_g': 25,
    });
    expect(bare.isCurrent, isTrue);
    expect(bare.maxExerciseIntensity, ExerciseIntensity.low);
  });

  test('ExerciseSession: row round trip and a change of status', () {
    final s = ExerciseSession(
      sessionId: 's1',
      accountId: 'a1',
      patientPlanId: 'pp1',
      exerciseId: 'e1',
      completedAt: _at,
      durationSec: 90,
      repetitionsCompleted: 8,
      completionStatus: CompletionStatus.completed,
      postureAccuracy: 87.5,
      postureFeedback: 'Good form.',
      modelVersion: 'rules-1.0',
    );
    final b = ExerciseSession.fromJson(_wire(s.toJson()));
    expect(b.toJson(), s.toJson());
    expect(b.durationMinutes(), 1.5);
    final skipped = b.withStatus(
      CompletionStatus.values.firstWhere(
        (v) => v != CompletionStatus.completed,
      ),
    );
    expect(skipped.completedAt, isNull);
    expect(skipped.postureAccuracy, 87.5);
    final again = skipped.withStatus(CompletionStatus.completed);
    expect(again.completedAt, isNotNull);
    final bare = ExerciseSession.fromJson({
      'session_id': 's2',
      'account_id': 'a1',
      'exercise_id': 'e1',
    });
    expect(bare.completedAt, isNull);
    expect(bare.durationMinutes(), 0);
  });

  test('Reminder and NotificationLog: rows round trip, copyWith', () {
    const r = Reminder(
      reminderId: 'r1',
      accountId: 'a1',
      patientPlanId: 'pp1',
      reminderType: ReminderType.exercise,
      title: 'Time for your exercise',
      hour: 7,
      minute: 5,
      repeatDays: '1010100',
      isEnabled: false,
    );
    final j = r.toJson();
    expect(j['scheduled_time'], '07:05:00');
    expect(Reminder.fromJson(_wire(j)).toJson(), j);
    final c = r.copyWith(
      isEnabled: true,
      hour: 18,
      minute: 30,
      repeatDays: '1111111',
    );
    expect(
      (c.isEnabled, c.hour, c.minute, c.repeatDays),
      (true, 18, 30, '1111111'),
    );
    expect(c.title, r.title);
    final bare = Reminder.fromJson({
      'reminder_id': 'r2',
      'account_id': 'a1',
      'title': 'x',
      'scheduled_time': '20:00:00',
    });
    expect((bare.repeatDays, bare.isEnabled), ('1111111', true));

    final n = NotificationLog(
      notificationId: 'n1',
      accountId: 'a1',
      reminderId: 'r1',
      notificationType: NotificationType.reminder,
      messageBody: 'Time for your exercise',
      deliveryStatus: DeliveryStatus.suppressed,
      isRead: true,
      issuedAt: _at,
    );
    expect(NotificationLog.fromJson(_wire(n.toJson())).toJson(), n.toJson());
  });

  test('PatientTreatmentPlan: row with its plan joined, round trip', () {
    final catalogue =
        jsonDecode(File('assets/seed/catalogue.json').readAsStringSync())
            as Map<String, dynamic>;
    final plan = TreatmentPlan.fromJson(
      (catalogue['plans'] as List).first as Map<String, dynamic>,
    );
    final p = PatientTreatmentPlan(
      patientPlanId: 'pp1',
      accountId: 'a1',
      plan: plan,
      suitabilityScore: 0.82,
      progressPercentage: 33.3,
      selectedAt: _at,
    );
    final row = {...p.toJson(), 'treatment_plan': plan.toJson()};
    final b = PatientTreatmentPlan.fromJson(_wire(row));
    expect(b.toJson(), p.toJson());
    expect(b.plan.planName, plan.planName);
    expect(b.isActive(), isTrue);
    expect(b.progress(), 33.3);
  });

  test('lookups: rows read, equality by id, blocked areas, hard blocks', () {
    final c = HealthCondition.fromJson({
      'condition_id': 1,
      'condition_code': 'HYPERTENSION',
      'condition_name': 'High blood pressure',
      'category': LookupSeed.conditions.first.category.db,
      'status_question': 'Is it under control with treatment?',
    });
    expect(c, LookupSeed.conditions.first);
    expect(c.hashCode, LookupSeed.conditions.first.hashCode);
    expect(c.needsClearance, isFalse);
    expect(c.withStatus(controlled: false, note: 'x').controlled, isFalse);

    final left = PhysicalLimitation.fromJson({
      'limitation_id': 1,
      'limitation_code': 'LEFT_ARM_MOBILITY',
      'limitation_name': 'Left Arm Mobility',
      'category': LookupSeed.limitations.first.category.db,
    });
    expect(left, LookupSeed.limitations.first);
    expect(left.hashCode, LookupSeed.limitations.first.hashCode);
    expect(left.blockedBodyArea(), 'LEFT_ARM');
    final balance = LookupSeed.limitations.firstWhere(
      (l) => l.affectsBalance(),
    );
    expect(balance.blockedBodyArea(), isNull);

    for (final t in RestrictionType.values) {
      final d = DietaryRestriction.fromJson({
        'restriction_id': t.index + 1,
        'restriction_code': 'R${t.index}',
        'restriction_name': t.name,
        'restriction_type': t.db,
      });
      expect(d.restrictionType, t);
      expect(d, DietaryRestriction(t.index + 1, 'other', 'other', t));
      expect(d.hashCode, (t.index + 1).hashCode);
      expect(d.isHardBlock(), t.db == 'ALLERGY' || t.db == 'INTOLERANCE');
    }
  });

  test('HealthProfile: row round trip, copyWith, staleness, codes', () {
    final p = HealthProfile(
      profileId: 'p1',
      accountId: 'a1',
      age: 50,
      gender: Gender.female,
      weightKg: 60,
      heightCm: 160,
      conditions: [LookupSeed.conditions.firstWhere((c) => !c.alwaysHighRisk)],
      restrictions: const [
        DietaryRestriction(1, 'PEANUT', 'Peanut', RestrictionType.allergy),
      ],
      version: 3,
      updatedAt: _at,
    );
    final j = p.toJson();
    expect(j['bmi'], 23.4);
    expect(j['risk_level'], 'Medium');
    expect(j['is_complete'], isTrue);
    final b = HealthProfile.fromJson(
      _wire(j),
      conditions: p.conditions,
      restrictions: p.restrictions,
    );
    expect(b.toJson(), j);
    expect(b.bmi, 23.4);
    expect(b.riskLevel, RiskLevel.medium);
    expect(b.restrictionCodes(), ['PEANUT']);
    expect(b.isStale(_at.add(const Duration(days: 200))), isTrue);
    expect(b.isStale(_at.add(const Duration(days: 10))), isFalse);
    final c = b.copyWith(age: 51, version: 4, updatedAt: _at);
    expect((c.age, c.version, c.weightKg), (51, 4, 60.0));
    final bare = HealthProfile.fromJson({
      'profile_id': 'p2',
      'account_id': 'a1',
      'updated_at': _at.toIso8601String(),
    });
    expect(bare.version, 0);
    expect(bare.gender, isNull);
    expect(bare.isComplete, isFalse);
    expect(bare.calculateBmi(), 0);
    expect(
      bare.generateSafetyLimit().dailyCalorieTarget,
      SafetyLimit.mostRestrictive().dailyCalorieTarget,
    );
  });

  test("the starter project's Users and ProfileModel", () {
    final u = Users.fromJSON(json: {'id': 'u1', 'user_name': 'pat'});
    expect(u.toJSON(), {'id': 'u1', 'user_name': 'pat'});
    expect(u.toString(), isNotEmpty);
    final m = ProfileModel(userName: 'pat', age: 30, email: 'p@x.test');
    expect(m.age, 30);
  });

  // The columns are timestamptz: a time without an offset is read as UTC by Supabase, so a
  // local time must be sent as UTC, and comes back as the same moment in local time (audit,
  // 23 Oct; before, a phone at UTC+8 stored them 8 hours late).
  test('times are written as UTC and read back as the same local moment', () {
    final local = DateTime(2026, 10, 23, 22, 15); // late evening on the phone
    String sent(Map<String, dynamic> row, String column) => row[column] as String;
    bool utc(String s) => s.endsWith('Z');

    final m = ChatMessage(
      messageId: 'm',
      accountId: 'a',
      sender: MessageSender.patient,
      messageText: 'hi',
      createdAt: local,
    );
    expect(utc(sent(m.toJson(), 'created_at')), isTrue);
    expect(ChatMessage.fromJson(_wire(m.toJson())).createdAt, local);

    final r = ChatReport(
      reportId: 'r',
      accountId: 'a',
      questionText: 'q',
      answerText: 'a',
      createdAt: local,
    );
    expect(utc(sent(r.toJson(), 'created_at')), isTrue);

    final n = NotificationLog(
      notificationId: 'n',
      accountId: 'a',
      notificationType: NotificationType.reminder,
      messageBody: 'Time for your exercise',
      deliveryStatus: DeliveryStatus.delivered,
      issuedAt: local,
    );
    expect(utc(sent(n.toJson(), 'issued_at')), isTrue);
    final back = NotificationLog.fromJson(_wire(n.toJson())).issuedAt;
    expect([back, back.hour], [local, 22]); // shown at 22:15, not 14:15

    final s = ExerciseSession(
      sessionId: 's',
      accountId: 'a',
      exerciseId: 'e',
      completionStatus: CompletionStatus.completed,
      completedAt: local,
    );
    expect(utc(sent(s.toJson(), 'completed_at')), isTrue);
    expect(ExerciseSession.fromJson(_wire(s.toJson())).completedAt, local);
  });
}
