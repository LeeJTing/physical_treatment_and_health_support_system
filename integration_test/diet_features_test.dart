import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'scenarios/diet_features.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDown(binding.testTextInput.unregister);
  runDietFeatureTests();
}
