import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/core/constants/app_constants.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_animation.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_coaching.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/guide/guide_view.dart';
import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/analysing_view.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/widgets/treatment_widgets.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/guide_view_model/guide_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

/// "Record exercise" (UI Design, Recording Screen; FR300_05, FR300_06, FR300_15, FR300_18, FR300_24):
/// camera preview with a full-body frame, record (auto-stops at 30 s) or upload a video.
///
/// Guided recording (Elwin, 23 Oct): Record first counts the patient in (time to walk to their
/// place), then the guide animation sets the pace, with the repetition count and what to do
/// now on screen and, when spoken cues are on, aloud. Recording stops by itself when the
/// paced repetitions are done (never before 10 s; 30 s at the latest). The cues are guidance
/// only: the server still counts and scores the repetitions in the clip.
class RecordingView extends StatefulWidget {
  /// How many times the patient is asked to do the exercise.
  final int reps;
  const RecordingView({super.key, this.reps = 10});
  static const routeName = '/treatment/recording';

  /// The guide plays this much slower while recording: an easy pace to follow.
  static const pace = 1.4;

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

  /// Seconds left before recording starts, while the patient gets into place; null otherwise.
  int? _countdown;
  Timer? _countTimer;
  ExerciseCoaching? _coaching;
  GuideAnimationData? _guide;

  /// The repetition the guide is on, and what to do now, while recording.
  int _rep = 0;
  String? _cue;
  bool _repsDone = false;
  int _take = 0; // restarts the guide when a recording starts

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  /// Kept from didChangeDependencies: dispose must not look up the tree.
  GuideViewModel? _voice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _voice = context.read<GuideViewModel>();
    if (_coaching == null) _loadGuide();
  }

  Future<void> _loadGuide() async {
    final e = context.read<TreatmentViewModel>().current;
    if (e == null) return;
    final bundle = DefaultAssetBundle.of(context);
    final coaching = await ExerciseCoaching.forExercise(bundle, e);
    final key = e.poseKey;
    final guide = key == null
        ? null
        : await GuideAnimationData.load(bundle, key);
    if (mounted) {
      setState(() {
        _coaching = coaching;
        _guide = guide;
      });
    }
  }

  /// The repetitions that fit in one clip at the guide's pace, at most [RecordingView.reps].
  int get _targetReps {
    final g = _guide;
    if (g == null || g.hold) return widget.reps;
    final loop =
        (g.durationSec + 0.6) * RecordingView.pace; // one paced repetition
    final fit = ((AppConstants.maxVideoSeconds - 1) / loop).floor();
    return fit.clamp(1, widget.reps);
  }

  void _say(String text) => _voice?.say(text);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _countTimer?.cancel();
    // A count-in or cue still being spoken stops when the patient leaves (audit, 23 Oct).
    _voice?.quiet();
    _release(_controller, wasRecording: _recording);
    super.dispose();
  }

  /// Stops a clip still being recorded (and deletes it) before closing the
  /// camera. Closing it mid-recording left CameraX's recorder broken, so the
  /// next recording never stopped (Android 15 emulator, 10 Oct).
  static void _release(CameraController? c, {required bool wasRecording}) {
    if (c == null) return;
    if (!wasRecording) {
      c.dispose();
      return;
    }
    c
        .stopVideoRecording()
        .timeout(_stopTimeout)
        .then((f) => File(f.path).delete())
        .then<void>((_) {}, onError: (Object _) {})
        .whenComplete(c.dispose);
  }

  /// How long stopping a clip may take before it counts as failed.
  static const _stopTimeout = Duration(seconds: 5);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      if (c == null || !c.value.isInitialized) return;
      _stopTimer();
      _cancelCountdown();
      _voice?.quiet();
      _release(c, wasRecording: _recording);
      setState(() {
        _recording = false;
        _controller = null;
      });
    } else if (state == AppLifecycleState.resumed && c == null) {
      // The camera was released when the app left the screen (photo picker,
      // notification shade, Home): open it again. Before, this returned early
      // because the controller was already null, so Record did nothing after
      // "Upload video" or a trip to Home (Android 15 emulator, 10 Oct).
      _initCamera();
    }
  }

  /// True while a camera is being opened: the permission dialog sends the app
  /// through inactive / resumed, which must not open a second one.
  bool _opening = false;

  Future<void> _initCamera() async {
    if (_opening) return;
    _opening = true;
    try {
      final firstTime = _cameras.isEmpty;
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('none', 'No camera');
      // Start on the back camera; the switch button flips to the front one.
      // Only the first time: a re-open keeps the camera the patient chose.
      if (firstTime) {
        final back = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = back < 0 ? 0 : back;
      }
      final c = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        videoBitrate:
            AppConstants.recordingBitrate, // smaller upload, same result
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
    } finally {
      _opening = false;
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

  /// Record: count the patient in first, so they can walk to their place (10 s; 5 s at a
  /// table). Tapping again during the count cancels it.
  void _startCountdown() {
    if (_countdown != null) {
      _cancelCountdown();
      _say('Cancelled.');
      return;
    }
    final hands =
        context.read<TreatmentViewModel>().current?.recordsHands ?? false;
    final start = hands ? 5 : 10;
    setState(() => _countdown = start);
    _say('Get into position. Recording starts in $start seconds.');
    _countTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (_countdown ?? 1) - 1;
      if (left <= 0) {
        _cancelCountdown();
        _toggleRecording();
        return;
      }
      setState(() => _countdown = left);
      if (left <= 3) _say('$left');
    });
  }

  void _cancelCountdown() {
    _countTimer?.cancel();
    _countTimer = null;
    if (mounted && _countdown != null) setState(() => _countdown = null);
  }

  /// The guide moved to another part of the repetition while recording: show it, say it, and
  /// stop once the paced repetitions are done.
  void _onPhase(String phase, int rep) {
    if (!_recording) return;
    if (rep > _targetReps) {
      if (!_repsDone) {
        setState(() {
          _repsDone = true;
          _cue = 'Well done. Stay still for a moment.';
        });
        _say('Well done.');
        if (_seconds >= AppConstants.minVideoSeconds) _toggleRecording();
      }
      return;
    }
    final c = _coaching;
    setState(() {
      _rep = rep;
      _cue = c?.captions[phase] ?? _cue;
    });
    final go = c?.say['go'], back = c?.say['back'];
    if (phase == 'go') {
      _say(go == null ? '$rep.' : '$rep. $go.');
    } else if (phase == 'back' && back != null) {
      _say('$back.');
    }
  }

  Future<void> _toggleRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (!_recording) {
      try {
        await c.startVideoRecording();
      } on CameraException {
        _showProblem(Messages.recordingFailed);
        return;
      }
      if (!mounted) return;
      final hold = _guide?.hold ?? false;
      setState(() {
        _recording = true;
        _seconds = 0;
        _rep = 1;
        _repsDone = false;
        _take++;
        _cue = hold ? 'Hold the position' : _coaching?.captions['start'];
      });
      _say(hold ? 'Start. Hold the position.' : 'Start.');
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _seconds++);
        if (_seconds >= AppConstants.maxVideoSeconds ||
            (_repsDone && _seconds >= AppConstants.minVideoSeconds)) {
          _toggleRecording(); // done, or auto-stop at 30 s
        }
      });
      return;
    }
    _stopTimer();
    final XFile file;
    try {
      // Never wait for ever: a stop that does not finish leaves the screen
      // stuck on "Stop" with the timer frozen.
      file = await c.stopVideoRecording().timeout(_stopTimeout);
    } on Object {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _controller = null;
      });
      _showProblem(Messages.recordingFailed);
      // A fresh camera, so the next try starts clean.
      _release(c, wasRecording: false);
      await _initCamera();
      return;
    }
    final seconds = _seconds;
    if (!mounted) return;
    // Back at 00:00 for "Record again", not the last clip's length.
    setState(() {
      _recording = false;
      _seconds = 0;
      _cue = null;
    });
    _say('Recording stopped.');
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
    // Where the phone goes: the guide's own rule (audit, 24 Oct: the help said waist height for
    // every exercise while the guide puts it on the floor for bird dog and glute bridge).
    final place = current == null
        ? (floor: false, metres: null)
        : GuideView.phonePlace(current);
    final away = place.metres == null
        ? '2.5 to 3 metres'
        : 'about ${place.metres} metres';
    final phone = place.floor
        ? 'Put the phone on the floor, propped up so it looks at you, $away away.'
        : 'Put the phone on a stand at about waist height, $away away.';
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
                  : '• $phone\n'
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
    final page = Scaffold(
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
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: SpeechToggle(),
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
                        // Only the dashed frame: the animation below shows the person.
                        const _FrameGuide(),
                        // The exercise moving inside the frame (11 Oct): where to stand
                        // and what to do; fainter while recording.
                        IgnorePointer(
                          child: Align(
                            child: FractionallySizedBox(
                              widthFactor: 0.6,
                              heightFactor: 0.86,
                              child: ExerciseAnimation(
                                poseKey: vm.current?.poseKey,
                                color: Colors.white.withValues(
                                  alpha: _recording ? 0.5 : 0.8,
                                ),
                                strokeShare: 0.03,
                                coaching: _coaching,
                                pace: _recording ? RecordingView.pace : 1,
                                restartToken: _take,
                                onPhase: _onPhase,
                              ),
                            ),
                          ),
                        ),
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
                        if (_recording && !(_guide?.hold ?? true))
                          Positioned(
                            top: 12,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _Pill(
                                key: const Key('rep_counter'),
                                text:
                                    'Rep ${_rep.clamp(1, _targetReps)} of $_targetReps',
                              ),
                            ),
                          ),
                        if (_countdown case final left?)
                          Positioned.fill(
                            child: Container(
                              key: const Key('countdown'),
                              color: Colors.black54,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Get into position',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '$left',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 96,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Text(
                                    'Recording starts when the count ends',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
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
                                  (_recording ? _cue : null) ??
                                  (_countdown == null && !_recording
                                      ? 'Tap Record, then go to your place: you have '
                                            '${hands ? 5 : 10} seconds.'
                                      : null) ??
                                  // The set-up of this exercise (side view, on the floor, ...).
                                  vm.current?.cameraTip ??
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
                          label: _recording
                              ? 'Stop'
                              : _countdown != null
                              ? 'Cancel'
                              : 'Record',
                          onTap: (c != null && _cameraError == null)
                              ? (_recording
                                    ? _toggleRecording
                                    : _startCountdown)
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
                          onTap: _recording || _countdown != null
                              ? null
                              : _upload,
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
    // The phone's Back and the arrow (23 Oct): during the count-in they cancel it; while
    // recording they ask first, as Exit does, instead of dropping the clip without a word.
    return PopScope(
      canPop: !_recording && _countdown == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_countdown != null) {
          _cancelCountdown();
          return;
        }
        final stop = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            content: const Text(
              'Stop recording and go back? This recording will not be saved.',
              style: TextStyle(fontSize: 17),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep recording'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text(
                  'Stop',
                  style: TextStyle(color: AppTokens.cta),
                ),
              ),
            ],
          ),
        );
        if (stop == true && context.mounted) Navigator.of(context).pop();
      },
      child: page,
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

/// Dashed frame, as in the design. The exercise's own animation is drawn
/// inside it (ExerciseAnimation, 11 Oct), so the fixed stick figure is gone.
class _FrameGuide extends StatelessWidget {
  const _FrameGuide();

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _GuidePainter()));
}

class _GuidePainter extends CustomPainter {
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
  }

  @override
  bool shouldRepaint(_GuidePainter old) => false;
}

/// A rounded label on the camera picture (the repetition count).
class _Pill extends StatelessWidget {
  final String text;
  const _Pill({super.key, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
