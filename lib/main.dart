import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/app.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
import 'package:physical_treatment_and_health_support_system/core/services/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/core/services/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/fake/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/interfaces/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/supabase/supabase_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/supabase/supabase_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/supabase/supabase_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/data/repository/supabase/supabase_treatment_repository.dart';

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
  } else {
    if (AppConstants.supabaseUrl.isEmpty ||
        AppConstants.supabaseAnonKey.isEmpty) {
      runApp(const _MissingConfigApp());
      return;
    }
    final provider = await SupabaseProvider.initialise(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
    );
    authRepo = SupabaseAuthRepository(provider);
    profileRepo = SupabaseProfileRepository(provider);
    treatmentRepo = SupabaseTreatmentRepository(provider);
    notificationRepo = SupabaseNotificationRepository(provider);
    // The AI server checks this Supabase token (JWKS) on every call.
    tokenProvider = () => provider.accessToken;
  }

  final api = ApiClient(
    baseUrl: AppConstants.aiBaseUrl,
    tokenProvider: tokenProvider,
  );

  runApp(
    MultiProvider(
      providers: [
        Provider<IAuthRepository>.value(value: authRepo),
        Provider<IProfileRepository>.value(value: profileRepo),
        Provider<ITreatmentRepository>.value(value: treatmentRepo),
        Provider<INotificationRepository>.value(value: notificationRepo),
        Provider<ApiClient>.value(value: api),
        // Services are added here module by module; ViewModels are created per route in app.dart.
        Provider<RiskAssessmentService>.value(
          value: RiskAssessmentService(authRepo, profileRepo),
        ),
        Provider<RecommendationService>.value(
          value: RecommendationService(api),
        ),
        Provider<ChatbotService>.value(value: ChatbotService(api)),
        Provider<PoseEstimationService>.value(
          value: PoseEstimationService(api),
        ),
        Provider<LocalNotificationService>.value(
          value: LocalNotificationService(notificationRepo, treatmentRepo),
        ),
      ],
      child: const MainApp(),
    ),
  );
}

/// Shown instead of the app when it was started in Supabase mode without the
/// project keys, so the cause is obvious instead of a crash.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Supabase is not configured',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 12),
              Text(
                'USE_FAKES is false but SUPABASE_URL or SUPABASE_ANON_KEY is empty.\n\n'
                'Copy config/dev.example.json to config/dev.json, fill in the project URL and the '
                'publishable (anon) key, then run:\n\n'
                'flutter run --dart-define-from-file=config/dev.json\n\n'
                'Or run on in-memory data: flutter run --dart-define=USE_FAKES=true',
                style: TextStyle(fontSize: 15, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
