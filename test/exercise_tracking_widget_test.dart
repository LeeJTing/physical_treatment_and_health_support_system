import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../integration_test/scenarios/exercise_tracking_flows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_EXERCISE_EVIDENCE')) return;
    final sdk = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
    for (final (family, file) in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'materialicons-regular.otf'),
    ]) {
      final data = await File(
        '$sdk/bin/cache/artifacts/material_fonts/$file',
      ).readAsBytes();
      await (FontLoader(
        family,
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
  });
  runExerciseTrackingFlows(
    capture: (t, name) async {
      if (!const bool.fromEnvironment('CAPTURE_EXERCISE_EVIDENCE')) return;
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('exercise-tracking-evidence')),
      );
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/exercise-tracking-evidence/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    },
  );
}
