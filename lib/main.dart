import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:physical_treatment_and_health_support_system/app.dart';
import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/services/api_client.dart';
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
        // Services and ViewModels are added here module by module.
      ],
      child: const MainApp(),
    ),
  );
}
