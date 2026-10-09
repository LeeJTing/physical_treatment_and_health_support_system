import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/analysing_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/treatment_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

/// "Record exercise" (UI Design, Recording Screen; FR300_05, FR300_06, FR300_15, FR300_18, FR300_24):
/// camera preview with a full-body frame, record (auto-stops at 30 s) or upload a video.
class RecordingView extends StatefulWidget {
  const RecordingView({super.key});
  static const routeName = '/treatment/recording';

  @override
  State<RecordingView> createState() => _RecordingViewState();
}

class _RecordingViewState extends State<RecordingView>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  String? _cameraError;
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _stopTimer();
      _recording = false;
      c.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'No camera');
      // Start on the back camera; the switch button flips to the front one.
      if (_controller == null) {
        final back = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = back < 0 ? 0 : back;
      }
      final c = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        videoBitrate: AppConstants.recordingBitrate, // smaller upload, same result
      );
      await c.initialize();
      // FR300_15: at least 720p.
      final size = c.value.previewSize;
      if (size != null && size.shortestSide < AppConstants.minVideoHeightPx) {
        await c.dispose();
        setState(() => _cameraError = Messages.deviceCompatibility);
        return;
      }
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _cameraError = null;
      });
    } on CameraException {
      if (mounted) {
        setState(() => _cameraError = Messages.cameraFailed); // FR300_24
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording) return;
    final old = _controller;
    setState(() {
      _controller = null;
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    });
    await old?.dispose();
    await _initCamera();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _toggleRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!_recording) {
      await c.startVideoRecording();
      setState(() {
        _recording = true;
        _seconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _seconds++);
        if (_seconds >= AppConstants.maxVideoSeconds) {
          _toggleRecording(); // auto-stop at 30 s
        }
      });
      return;
    }
    _stopTimer();
    final file = await c.stopVideoRecording();
    final seconds = _seconds;
    setState(() => _recording = false);
    if (seconds < AppConstants.minVideoSeconds) {
      _showProblem(Messages.videoInvalid); // FR300_16, before any upload
      return;
    }
    await _analyse(File(file.path), seconds);
  }

  Future<void> _upload() async {
    if (_recording) return;
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: AppConstants.maxVideoSeconds),
    );
    if (picked == null) return;
    await _analyse(File(picked.path), null);
  }

  Future<void> _analyse(File file, int? seconds) async {
    if (!mounted) return;
    final vm = context.read<TreatmentViewModel>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: AnalysingView(file: file, clipSeconds: seconds),
        ),
      ),
    );
  }

  void _showProblem(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );

  void _help() {
    final current = context.read<TreatmentViewModel>().current;
    final tip = current?.cameraTip;
    final hands = current?.recordsHands ?? false;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How to record'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (tip != null) ...[
              Text(
                'Camera: $tip',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              hands
                  ? '• Sit at a table. Put the phone on a stand at table height, about half a metre to 1 metre away.\n'
                        '• Keep your forearm and your whole hand inside the frame.\n'
                        '• Use good light in front of you.\n'
                  : '• Put the phone on a stand at about waist height, 2.5 to 3 metres away.\n'
                        '• Keep your whole body, head to feet, inside the frame.\n'
                        '• Use good light in front of you.\n'
                        '• Record 10 to 30 seconds: do the repetitions slowly.\n'
                        '• If the upload fails, check the video is MP4 or MOV, 10 to 30 seconds and under 100 MB.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TreatmentViewModel>();
    final name = vm.current?.exerciseName ?? '';
    final hands = vm.current?.recordsHands ?? false;
    final c = _controller;
    return Scaffold(
      backgroundColor: AppTokens.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, AppTokens.gutter, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: PlanningHeader(
                      title: 'Record exercise',
                      subtitle: name,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  ExitExerciseButton(
                    confirm: _recording
                        ? 'Stop recording and leave this exercise? This recording will not be saved.'
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: IconButton.filled(
                      onPressed: _help,
                      tooltip: 'Recording instructions',
                      style: IconButton.styleFrom(
                        backgroundColor: AppTokens.primary,
                      ),
                      icon: const Icon(
                        Icons.question_mark_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.gutter,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                  child: Container(
                    color: AppTokens.primary,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (c != null && c.value.isInitialized)
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: c.value.previewSize?.height ?? 720,
                              height: c.value.previewSize?.width ?? 1280,
                              child: CameraPreview(c),
                            ),
                          )
                        else if (_cameraError == null)
                          const Center(
                            child: CircularProgressIndicator(
                              color: AppTokens.onPrimaryMuted,
                            ),
                          ),
                        _FrameGuide(hands: hands),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _recording
                                  ? AppTokens.danger
                                  : Colors.black45,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        if (_cameras.length > 1)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: IconButton(
                              onPressed: _recording ? null : _switchCamera,
                              tooltip: 'Switch camera',
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                              ),
                              icon: const Icon(
                                Icons.cameraswitch_outlined,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 16,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _cameraError ??
                                  (hands
                                      ? 'Keep your forearm and your whole hand inside the frame.'
                                      : 'Step back until your whole body, head to feet, fits inside the frame.'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTokens.gutter),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppTokens.surface,
                  borderRadius: BorderRadius.circular(AppTokens.radiusCard + 4),
                  border: Border.all(color: AppTokens.border),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: _BigAction(
                          label: _recording ? 'Stop' : 'Record',
                          onTap: (c != null && _cameraError == null)
                              ? _toggleRecording
                              : null,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                              color: AppTokens.action,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: _recording
                                  ? Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    )
                                  : Container(
                                      width: 28,
                                      height: 28,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(
                        color: AppTokens.border,
                        width: 1,
                        indent: 8,
                        endIndent: 8,
                      ),
                      Expanded(
                        child: _BigAction(
                          label: 'Upload video',
                          onTap: _recording ? null : _upload,
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: const BoxDecoration(
                              color: AppTokens.accentContainer,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.upload_rounded,
                              color: AppTokens.accent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  const _BigAction({
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    enabled: onTap != null,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTokens.text,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Dashed full-body frame with a faint stick figure, as in the design. For
/// the hand exercises only the frame is drawn: no whole body is needed.
class _FrameGuide extends StatelessWidget {
  final bool hands;
  const _FrameGuide({this.hands = false});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _GuidePainter(hands)));
}

class _GuidePainter extends CustomPainter {
  final bool hands;
  _GuidePainter(this.hands);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(
      size.width * 0.18,
      size.height * 0.04,
      size.width * 0.64,
      size.height * 0.92,
    );
    final dash = Paint()
      ..color = AppTokens.highlight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(14)));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        canvas.drawPath(metric.extractPath(d, d + 8), dash);
      }
    }
    if (hands) return;
    final body = Paint()
      ..color = AppTokens.highlight.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final cx = frame.center.dx;
    final top = frame.top + frame.height * 0.08;
    final h = frame.height * 0.82;
    final head = h * 0.07;
    canvas.drawCircle(Offset(cx, top + head), head, body);
    final neck = Offset(cx, top + head * 2);
    final hip = Offset(cx, top + h * 0.5);
    canvas.drawLine(neck, hip, body);
    canvas.drawLine(
      Offset(cx, top + h * 0.2),
      Offset(cx - h * 0.14, top + h * 0.38),
      body,
    );
    canvas.drawLine(
      Offset(cx, top + h * 0.2),
      Offset(cx + h * 0.14, top + h * 0.38),
      body,
    );
    canvas.drawLine(hip, Offset(cx - h * 0.1, top + h), body);
    canvas.drawLine(hip, Offset(cx + h * 0.1, top + h), body);
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.hands != hands;
}
