import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/app.dart';
import 'package:physical_treatment_and_health_support_system/shared_client/api_client/api_client.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/test_mode_view_model/test_mode_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/guide_view_model/guide_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/user_guide_view_model/user_guide_view_model.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/speech_service/speech_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/chatbot_service/chatbot_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/pose_estimation_service/pose_estimation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/local_notification_service/local_notification_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/risk_assessment_service/risk_assessment_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/recommendation_service/recommendation_service.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/auth_repository/i_auth_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/notification_repository/i_notification_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/profile_repository/i_profile_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/treatment_repository/i_treatment_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/terms_repository/i_terms_repository.dart';
import 'package:physical_treatment_and_health_support_system/device_platform/camera_gallery/meal_image_picker.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/anomaly_detection_service/anomaly_detection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/diet_planner_service/diet_planner_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/food_recognition_service/food_recognition_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/forecast_service/forecast_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/health_connect_service/health_connect_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/suitability_service/suitability_service.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/analysis_repository/i_analysis_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/biometric_repository/i_biometric_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/food_repository/i_food_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/repository/meal_repository/i_meal_repository.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/server_connection_service/server_connection_service.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/user_guide_service/user_guide_service.dart';

import 'demo_environment.dart';

/// Composition for the actual production MainApp, with disposable test dependencies.
Future<DemoEnvironment> startDemo({bool signedIn = true}) async {
  if (!kDebugMode || !const bool.fromEnvironment('E2E_TESTING')) {
    throw StateError('Use --dart-define=E2E_TESTING=true for this isolated test entry point.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final env = await DemoEnvironment.create(signedIn: signedIn);
  final authRepo = env.auth, profileRepo = env.profiles;
  final treatmentRepo = env.treatments;
  final notificationRepo = env.notifications;
  final termsRepo = env.terms;
  final biometricRepo = env.biometrics;
  final analysisRepo = env.analysis;
  final foodRepo = env.foods;
  final mealRepo = env.meals;
  final api = ApiClient(baseUrl: 'http://isolated.test', tokenProvider: () => 'e2e-token', httpClient: env.ai);
  final localSettings = env.settings;
  final serverConnection = ServerConnectionService(api, localSettings, defaultAddress: 'http://isolated.test');
  final risk = RiskAssessmentService(authRepo, profileRepo);
  final healthSource = env.health;
  runApp(
    MultiProvider(
      providers: [
        Provider<IAuthRepository>.value(value: authRepo),
        Provider<IProfileRepository>.value(value: profileRepo),
        Provider<ITreatmentRepository>.value(value: treatmentRepo),
        Provider<INotificationRepository>.value(value: notificationRepo),
        Provider<ITermsRepository>.value(value: termsRepo),
        Provider<IBiometricRepository>.value(value: biometricRepo),
        Provider<IAnalysisRepository>.value(value: analysisRepo),
        Provider<IFoodRepository>.value(value: foodRepo),
        Provider<IMealRepository>.value(value: mealRepo),
        Provider<ApiClient>.value(value: api),
        // Testing mode (Profile, debug builds only): any exercise, nothing saved.
        ChangeNotifierProvider<TestModeViewModel>(create: (_) => TestModeViewModel()),
        // Exercise guide (23 Oct): spoken cues, on / off kept while the app runs.
        ChangeNotifierProvider<GuideViewModel>(create: (_) => GuideViewModel(SpeechService())),
        Provider<ServerConnectionService>.value(value: serverConnection),
        // Services are added here module by module; ViewModels are created per route in app.dart.
        Provider<RiskAssessmentService>.value(value: risk),
        Provider<RecommendationService>.value(value: RecommendationService(api)),
        Provider<ChatbotService>.value(value: ChatbotService(api)),
        Provider<PoseEstimationService>.value(value: PoseEstimationService(api)),
        // M200, M400, M700 services (Jun Ting)
        Provider<HealthConnectService>.value(value: HealthConnectService(healthSource)),
        Provider<ForecastService>.value(value: ForecastService(api)),
        Provider<AnomalyDetectionService>.value(value: AnomalyDetectionService(api, analysisRepo)),
        Provider<FoodRecognitionService>.value(value: FoodRecognitionService(api, foodRepo)),
        Provider<SuitabilityService>.value(value: const SuitabilityService()),
        Provider<DietPlannerService>.value(value: DietPlannerService(api, foodRepo)),
        Provider<MealImageSource>.value(value: env.photos),
        // First-visit picture guides (usability): remembered on this phone only.
        ChangeNotifierProvider<UserGuideViewModel>(create: (_) => UserGuideViewModel(UserGuideService(localSettings))),
        Provider<LocalNotificationService>.value(
          value: LocalNotificationService(
            notificationRepo,
            treatmentRepo,
            scheduler: env.scheduler,
            // Exercise reminders stop from 65, when plans are paused.
            profileAge: () async => (await risk.retrieve()).dataOrNull?.profile?.age,
          ),
        ),
      ],
      child: const MainApp(),
    ),
  );
  return env;
}
