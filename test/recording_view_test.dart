// RecordingView (Record Exercise screen) with fake camera and gallery plugins (audit, 24 Oct;
// asked for by the PC on 22 Oct): no camera shows the FR300_24 message and Upload still works,
// a camera under 720p shows the FR300_15 message, and a chosen video goes on to the check.
import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/model/business_logic/speech_service/speech_service.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/analysing_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/recording_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/guide_view_model/guide_view_model.dart';

import 'guide_test.dart' show FakeSpeech;
import 'treatment_test.dart' show Harness;

/// The phone's camera: [cameras] to offer, opened at [preview] size.
class _FakeCamera extends CameraPlatform {
  List<CameraDescription> cameras = const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  Size preview = const Size(1280, 720);

  @override
  Future<List<CameraDescription>> availableCameras() async => cameras;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => 1;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          preview.width,
          preview.height,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  /// No error ever comes (the controller waits for the first one, so it must not close).
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);

  @override
  Future<void> dispose(int cameraId) async {}
}

/// The phone's gallery: returns [video] (null = the patient cancelled).
class _FakeGallery extends ImagePickerPlatform {
  String? video;
  int asked = 0;

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async {
    asked++;
    return video == null ? null : XFile(video!);
  }
}

void main() {
  late Directory tmp;
  late _FakeCamera camera;
  late _FakeGallery gallery;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('apths');
    camera = _FakeCamera();
    gallery = _FakeGallery();
    CameraPlatform.instance = camera;
    ImagePickerPlatform.instance = gallery;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Harness> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final h = Harness();
    await tester.runAsync(() async {
      await h.setUp(tmp);
      await h.vm.startExercise(h.vm.pathway.first.item.exercise);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: h.vm),
          ChangeNotifierProvider(
            create: (_) => GuideViewModel(SpeechService(FakeSpeech())),
          ),
        ],
        child: const MaterialApp(home: RecordingView()),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    return h;
  }

  testWidgets('no camera: the camera message, and Upload still works (FR300_24)', (
    tester,
  ) async {
    camera.cameras = const [];
    await open(tester);
    expect(find.text(Messages.cameraFailed), findsOneWidget);
    await tester.tap(find.text('Upload video'));
    await tester.pump();
    expect(gallery.asked, 1);
  });

  testWidgets('a camera under 720p says the phone cannot record (FR300_15)', (
    tester,
  ) async {
    camera.preview = const Size(640, 480);
    await open(tester);
    expect(find.text(Messages.deviceCompatibility), findsOneWidget);
  });

  testWidgets('a camera of 720p or more shows no camera message', (tester) async {
    await open(tester);
    expect(find.text(Messages.cameraFailed), findsNothing);
    expect(find.text(Messages.deviceCompatibility), findsNothing);
  });

  testWidgets('a chosen video goes on to the check; a cancelled choice stays', (
    tester,
  ) async {
    final h = await open(tester);
    await tester.tap(find.text('Upload video'));
    await tester.pump();
    expect(find.byType(AnalysingView), findsNothing); // cancelled: still recording screen
    gallery.video = h.clip.path;
    await tester.tap(find.text('Upload video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AnalysingView), findsOneWidget);
  });
}
