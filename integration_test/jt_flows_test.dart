import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'scenarios/jt_flows.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Maestro separately exercises the Android IME. Flutter assertions use controlled input.
  tearDown(binding.testTextInput.unregister);
  runJtFlows();
}
