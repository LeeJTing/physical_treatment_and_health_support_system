import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/app.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/supabase_provider/supabase_provider.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/fake_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/fake_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/fake_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/fake_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/supabase_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/supabase_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/supabase_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/supabase_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/i_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/fake_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/supabase_terms_repository.dart';

/// Composition root. This is the ONLY file that names a concrete repository
/// class (ASR_02); everything else depends on the interfaces.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final IAuthRepository authRepo;
  final IProfileRepository profileRepo;
  final ITreatmentRepository treatmentRepo;
  final INotificationRepository notificationRepo;
  final ITermsRepository termsRepo;
  final String? Function() tokenProvider;

  if (AppConstants.useFakes) {
    final catalogue = await rootBundle.loadString('assets/seed/catalogue.json');
    authRepo = FakeAuthRepository();
    profileRepo = FakeProfileRepository();
    treatmentRepo = FakeTreatmentRepository.fromJson(catalogue);
    notificationRepo = FakeNotificationRepository();
    termsRepo = FakeTermsRepository();
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
    termsRepo = SupabaseTermsRepository(provider);
    // The AI server checks this Supabase token (JWKS) on every call.
    tokenProvider = () => provider.accessToken;
  }

  final api = ApiClient(
    baseUrl: AppConstants.aiBaseUrl,
    tokenProvider: tokenProvider,
  );

  final risk = RiskAssessmentService(authRepo, profileRepo);
  runApp(
    MultiProvider(
      providers: [
        Provider<IAuthRepository>.value(value: authRepo),
        Provider<IProfileRepository>.value(value: profileRepo),
        Provider<ITreatmentRepository>.value(value: treatmentRepo),
        Provider<INotificationRepository>.value(value: notificationRepo),
        Provider<ITermsRepository>.value(value: termsRepo),
        Provider<ApiClient>.value(value: api),
        // Testing mode (Profile, debug builds only): any exercise, nothing saved.
        ChangeNotifierProvider<TestModeViewModel>(create: (_) => TestModeViewModel()),
        // Services are added here module by module; ViewModels are created per route in app.dart.
        Provider<RiskAssessmentService>.value(value: risk),
        Provider<RecommendationService>.value(
          value: RecommendationService(api),
        ),
        Provider<ChatbotService>.value(value: ChatbotService(api)),
        Provider<PoseEstimationService>.value(
          value: PoseEstimationService(api),
        ),
        Provider<LocalNotificationService>.value(
          value: LocalNotificationService(
            notificationRepo,
            treatmentRepo,
            // Exercise reminders stop from 65, when plans are paused.
            profileAge: () async =>
                (await risk.retrieve()).dataOrNull?.profile?.age,
          ),
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
