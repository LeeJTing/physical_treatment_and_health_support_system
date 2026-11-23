import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/biometric_reading.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/enums.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise_session.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/patient_treatment_plan.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/recovery_check_in.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/recovery_repository/fake_recovery_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/view/health_insights_view/health_insights_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/health_insights_view_model/health_insights_view_model.dart';
import 'plan_comparison_fixture.dart';

class HealthInsightsFixture {
  final PlanComparisonFixture base;
  final FakeTreatmentRepository treatments;
  final FakeRecoveryRepository recovery;
  final HealthInsightsViewModel vm;
  HealthInsightsFixture(this.base, this.treatments, this.recovery, this.vm);
  static Future<HealthInsightsFixture> create() async {
    final base = await PlanComparisonFixture.create();
    final treatments = FakeTreatmentRepository.fromJson(
      await rootBundle.loadString('assets/seed/catalogue.json'),
    );
    final catalogue = (await treatments.getCatalogue()).dataOrNull!;
    final plan = catalogue.first;
    await treatments.assignPlan(
      PatientTreatmentPlan(
        patientPlanId: 'assignment',
        accountId: base.account,
        plan: plan,
        status: PlanStatus.active,
        selectedAt: DateTime(2026, 11, 1),
        progressPercentage: 33.33,
      ),
    );
    for (var i = 0; i < 2; i++) {
      treatments.sessions.add(
        ExerciseSession(
          sessionId: 'exercise-$i',
          accountId: base.account,
          patientPlanId: 'assignment',
          exerciseId: plan.exercises.first.exerciseId,
          completedAt: DateTime(2026, 11, 17 + i * 2, 18),
          durationSec: 120,
          completionStatus: CompletionStatus.completed,
          postureAccuracy: 82 + i * 4,
        ),
      );
    }
    final recovery = FakeRecoveryRepository([
      for (var i = 0; i < 2; i++)
        RecoveryCheckIn(
          checkInId: 'check-$i',
          accountId: base.account,
          patientPlanId: 'assignment',
          date: DateTime(2026, 11, 16 + i * 3),
          updatedAt: DateTime(2026, 11, 19),
          pain: 4 + i * 2,
          stiffness: 3 + i,
          difficulty: 2 + i,
        ),
    ]);
    for (var i = 0; i < 12; i++) {
      base.readings.readings.add(
        BiometricReading(
          readingId: 'bp-$i',
          accountId: base.account,
          metricType: MetricType.bloodPressure,
          primaryValue: 120 + (i % 3) * 2,
          secondaryValue: 80,
          recordedAt: DateTime(2026, 11, 9 + i, 8),
          source: ReadingSource.imported,
          sourceDevice: i == 11
              ? 'Presentation demo (synthetic)'
              : 'Fixture watch',
          importedAt: DateTime(2026, 11, 20, 21),
        ),
      );
    }
    final vm = HealthInsightsViewModel(
      base.auth,
      base.readings,
      base.meals,
      treatments,
      recovery,
      now: () => PlanComparisonFixture.now,
    );
    await vm.load();
    return HealthInsightsFixture(base, treatments, recovery, vm);
  }

  Widget app({int tab = 0}) => ChangeNotifierProvider.value(
    value: vm,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF116C63),
      ),
      home: HealthInsightsView(initialTab: tab),
    ),
  );
  void dispose() {
    vm.dispose();
    base.vm.dispose();
  }
}
