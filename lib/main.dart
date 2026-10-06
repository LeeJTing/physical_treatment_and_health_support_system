import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/app.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
import 'package:physical_treatment_and_health_support_system/core/services/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/profile_info_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/utils/id_utils.dart';
import 'package:physical_treatment_and_health_support_system/data/models/enums.dart';
import 'package:physical_treatment_and_health_support_system/data/models/health_profile.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_treatment_repository.dart';

/// Composition root. This is the ONLY file that names a concrete repository
/// class (ASR_02); everything else depends on the interfaces.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final IAuthRepository authRepo;
  final IProfileRepository profileRepo;
  final ITreatmentRepository treatmentRepo;
  final INotificationRepository notificationRepo;
  final String? Function() tokenProvider;

  if (AppConstants.useFakes) {
    final catalogue = await rootBundle.loadString('assets/seed/catalogue.json');
    authRepo = FakeAuthRepository();
    profileRepo = FakeProfileRepository();
    treatmentRepo = FakeTreatmentRepository.fromJson(catalogue);
    notificationRepo = FakeNotificationRepository();
    tokenProvider = () => 'dev-token';
    await _signInDemoPatient(authRepo, profileRepo);
  } else {
    // Wired once the Supabase project is ready: SupabaseProvider.initialise(...)
    // and the Supabase*Repository classes.
    throw UnimplementedError('Supabase repositories are not wired yet. Run with USE_FAKES=true.');
  }

  final api = ApiClient(baseUrl: AppConstants.aiBaseUrl, tokenProvider: tokenProvider);

  runApp(
    MultiProvider(
      providers: [
        Provider<IAuthRepository>.value(value: authRepo),
        Provider<IProfileRepository>.value(value: profileRepo),
        Provider<ITreatmentRepository>.value(value: treatmentRepo),
        Provider<INotificationRepository>.value(value: notificationRepo),
        Provider<ApiClient>.value(value: api),
        // Services are added here module by module; ViewModels are created per route in app.dart.
        Provider<ProfileInfoService>.value(value: ProfileInfoService(authRepo, profileRepo)),
        Provider<RecommendationService>.value(value: RecommendationService(api)),
        Provider<ChatbotService>.value(value: ChatbotService(api)),
      ],
      child: const MainApp(),
    ),
  );
}

/// Fake mode only: signs in the seeded demo account and gives it a complete
/// profile, so the planning screens can be used before the Phase 2 login
/// and profile screens exist. Remove once those are built.
Future<void> _signInDemoPatient(IAuthRepository auth, IProfileRepository profiles) async {
  final account = (await auth.login('demo@apths.test', 'password123')).dataOrNull;
  if (account == null) return;
  final profile = HealthProfile(
    profileId: newId(),
    accountId: account.accountId,
    age: 58,
    gender: Gender.male,
    weightKg: 72,
    heightCm: 170,
    updatedAt: DateTime.now(),
  );
  await profiles.saveProfile(profile, profile.generateSafetyLimit());
}
