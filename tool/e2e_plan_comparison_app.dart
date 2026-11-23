import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../integration_test/support/plan_comparison_fixture.dart';

Future<void> main() async {
  if (!kDebugMode || !const bool.fromEnvironment('E2E_TESTING')) {
    throw StateError('Build this isolated demo with E2E_TESTING=true.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = await PlanComparisonFixture.create();
  runApp(fixture.app);
}
