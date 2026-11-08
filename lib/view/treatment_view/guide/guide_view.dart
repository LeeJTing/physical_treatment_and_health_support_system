import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:physical_treatment_and_health_support_system/view/planning_view/widgets/planning_widgets.dart';
import 'package:physical_treatment_and_health_support_system/core/themes/design_tokens.dart';
import 'package:physical_treatment_and_health_support_system/model/entity/exercise.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_animation.dart';
import 'package:physical_treatment_and_health_support_system/view/common/exercise_coaching.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/guide/setup_scene.dart';
import 'package:physical_treatment_and_health_support_system/view/treatment_view/recording_view.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/guide_view_model/guide_view_model.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/treatment_view_model/treatment_view_model.dart';

/// Opens the guide for the exercise just started ([TreatmentViewModel.current]); its last page
/// opens the recorder. [reps]: how many times the patient is asked to do it.
Future<void> openExerciseGuide(BuildContext context, {required int reps}) {
  final vm = context.read<TreatmentViewModel>();
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: GuideView.routeName),
      builder: (_) => ChangeNotifierProvider.value(
        value: vm,
        child: GuideView(reps: reps),
      ),
    ),
  );
}

/// The exercise guide (Elwin, 23 Oct): before every recording, a first-time user is walked
/// through it one page at a time. Watch it, each step with its still, staying safe and the
/// common mistakes, then where to put the phone. Every page can be read aloud; Skip goes
/// straight to the camera.
class GuideView extends StatefulWidget {
  final int reps;
  const GuideView({super.key, required this.reps});
  static const routeName = '/treatment/guide';

  /// Where the phone goes, from the exercise's own camera tip (23 Oct): floor exercises (bird
  /// dog, glute bridge) put it on the floor about 2 m away, not at waist height.
  static ({bool floor, String? metres}) phonePlace(Exercise e) {
    final tip = (e.cameraTip ?? '').toLowerCase();
    return (
      floor: tip.contains('on the floor'),
      metres: RegExp(r'about ([\d.]+) m').firstMatch(tip)?.group(1),
    );
  }

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> {
  final _pages = PageController();
  int _page = 0;
  ExerciseCoaching? _coaching;
  GuideAnimationData? _data;

  Exercise? get _exercise => context.read<TreatmentViewModel>().current;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_coaching == null) _load();
  }

  Future<void> _load() async {
    final e = _exercise;
    if (e == null) return;
    final bundle = DefaultAssetBundle.of(context);
    final coaching = await ExerciseCoaching.forExercise(bundle, e);
    final key = e.poseKey;
    final data = key == null
        ? null
        : await GuideAnimationData.load(bundle, key);
    if (!mounted) return;
    setState(() {
      _coaching = coaching;
      _data = data;
    });
    _readAloud(0);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// What each page says aloud, in order.
  List<String> _spoken(Exercise e, ExerciseCoaching c) => [
    'Watch how to do ${e.exerciseName}. You will do it ${widget.reps} times.',
    for (var i = 0; i < c.steps.length; i++)
      'Step ${i + 1}. ${c.steps[i].text}',
    [
      'Stay safe.',
      ...(c.safety.isEmpty ? const [_defaultSafety] : c.safety),
      for (final m in c.mistakes) 'Do this: ${m.right}',
    ].join(' '),
    [..._setupLines(e, c)].join(' '),
  ];

  /// Said and shown when an exercise has no safety points of its own (the voice used to skip it,
  /// audit 24 Oct).
  static const _defaultSafety =
      'Stop if you feel pain, dizziness or shortness of breath.';

  List<String> _setupLines(Exercise e, ExerciseCoaching c) {
    final side = (_data?.view ?? 'front') == 'side';
    final place = GuideView.phonePlace(e);
    final away = place.metres == null
        ? '2.5 to 3 metres'
        : 'about ${place.metres} metres';
    return [
      ...c.setup,
      if (e.recordsHands) ...[
        'Sit at a table. Prop the phone up at table height, half a metre to one metre away.',
        'Keep your forearm and your whole hand inside the box on the screen.',
      ] else ...[
        place.floor
            ? 'Put the phone on the floor, propped up so it looks at you.'
            : 'Prop the phone up at about waist height, on a stand or against something steady.',
        '${place.floor ? 'Be' : 'Stand'} $away away, ${side ? 'with your side towards the phone, not your back' : 'facing the phone'}.',
        'Your whole body, head to feet, must fit inside the box on the screen.',
      ],
      'Have good light in front of you, not behind you.',
      'After you tap Record you have ${e.recordsHands ? 5 : 10} seconds to get into place.',
    ];
  }

  void _readAloud(int page) {
    final e = _exercise, c = _coaching;
    if (e == null || c == null) return;
    final lines = _spoken(e, c);
    context.read<GuideViewModel>().say(lines[page.clamp(0, lines.length - 1)]);
  }

  void _openCamera() {
    final vm = context.read<TreatmentViewModel>();
    context.read<GuideViewModel>().quiet();
    // On top of the guide (23 Oct): Back from the camera returns here; Exit leaves the exercise.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: RecordingView.routeName),
        builder: (_) => ChangeNotifierProvider.value(
          value: vm,
          child: RecordingView(reps: widget.reps),
        ),
      ),
    );
  }

  void _go(int page, int count) {
    if (page >= count) {
      _openCamera();
      return;
    }
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _exercise;
    final c = _coaching;
    if (e == null || c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final pages = <Widget>[
      _watchPage(e, c),
      for (var i = 0; i < c.steps.length; i++) _stepPage(e, c, i),
      _safetyPage(c),
      _setupPage(e, c),
    ];
    final last = _page == pages.length - 1;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) context.read<GuideViewModel>().quiet();
      },
      child: Scaffold(
        backgroundColor: AppTokens.background,
        body: SafeArea(
          child: Column(
            children: [
              HeaderBar(
                title: 'How to do it',
                subtitle: e.exerciseName,
                actions: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: SpeechToggle(),
                  ),
                  TextButton(
                    key: const Key('guide_skip'),
                    onPressed: _openCamera,
                    child: const Text(
                      'Skip',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Semantics(
                  label: 'Page ${_page + 1} of ${pages.length}',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i <= _page
                                ? AppTokens.primary
                                : AppTokens.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pages,
                  onPageChanged: (p) {
                    setState(() => _page = p);
                    _readAloud(p);
                  },
                  children: pages,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTokens.gutter,
                  8,
                  AppTokens.gutter,
                  AppTokens.gutter,
                ),
                child: Row(
                  children: [
                    if (_page > 0) ...[
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: AppTokens.minTarget + 4),
                          child: OutlinedButton(
                            onPressed: () => _go(_page - 1, pages.length),
                            child: const Text(
                              'Back',
                              style: TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: 2,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: AppTokens.minTarget + 4),
                        child: FilledButton(
                          key: const Key('guide_next'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTokens.action,
                          ),
                          onPressed: () => _go(_page + 1, pages.length),
                          // One line that shrinks to fit: with large phone text "Open the camera"
                          // wrapped and spilled out of the button (emulator at 2x, 24 Oct).
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              last ? 'Open the camera' : 'Next',
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageOf(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(
      AppTokens.gutter,
      8,
      AppTokens.gutter,
      8,
    ),
    children: children,
  );

  static const _title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: AppTokens.text,
  );
  static const _body = TextStyle(
    fontSize: 19,
    height: 1.45,
    color: AppTokens.text,
  );

  Widget _figure(Exercise e, ExerciseCoaching c, {String? still}) => SizedBox(
    height: 300,
    child: ExerciseAnimation(
      poseKey: e.poseKey,
      coaching: c,
      still: still,
      showCaption: still == null,
      strokeShare: 0.026,
      placeholder: const SizedBox.shrink(),
    ),
  );

  Widget _watchPage(Exercise e, ExerciseCoaching c) => _pageOf([
    Text('Watch how it is done', style: _title),
    const SizedBox(height: 6),
    Text(
      'You will do it ${widget.reps} times. The orange ring shows the part to watch; '
      'the arrow shows which way to move.',
      style: _body.copyWith(fontSize: 17, color: AppTokens.textBody),
    ),
    const SizedBox(height: 12),
    _figure(e, c),
  ]);

  Widget _stepPage(Exercise e, ExerciseCoaching c, int i) {
    final s = c.steps[i];
    return _pageOf([
      Text('Step ${i + 1} of ${c.steps.length}', style: _title),
      const SizedBox(height: 12),
      if (s.phase != null) ...[
        _figure(e, c, still: s.phase),
        const SizedBox(height: 16),
      ],
      Text(s.text, style: _body.copyWith(fontSize: 21)),
    ]);
  }

  Widget _safetyPage(ExerciseCoaching c) => _pageOf([
    const Text('Stay safe', style: _title),
    const SizedBox(height: 10),
    for (final s in c.safety)
      _Line(icon: Icons.health_and_safety_outlined, text: s),
    if (c.safety.isEmpty)
      const _Line(icon: Icons.health_and_safety_outlined, text: _defaultSafety),
    if (c.mistakes.isNotEmpty) ...[
      const SizedBox(height: 18),
      const Text('Common mistakes', style: _title),
      const SizedBox(height: 10),
      for (final m in c.mistakes) _MistakeCard(m),
    ],
  ]);

  Widget _setupPage(Exercise e, ExerciseCoaching c) => _pageOf([
    const Text('Set up your phone', style: _title),
    const SizedBox(height: 12),
    SetupScene(
      data: _data,
      hands: e.recordsHands,
      floor: GuideView.phonePlace(e).floor,
      distance: GuideView.phonePlace(e).metres == null
          ? null
          : 'about ${GuideView.phonePlace(e).metres} m',
    ),
    const SizedBox(height: 12),
    for (final l in _setupLines(e, c))
      _Line(icon: Icons.check_circle_outline, text: l),
  ]);
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTokens.primary, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 18,
              height: 1.4,
              color: AppTokens.text,
            ),
          ),
        ),
      ],
    ),
  );
}

/// ✗ what the mistake looks like, ✓ the server's own sentence for fixing it.
class _MistakeCard extends StatelessWidget {
  final CoachMistake m;
  const _MistakeCard(this.m);

  @override
  Widget build(BuildContext context) {
    final wrong = '${m.wrong[0].toUpperCase()}${m.wrong.substring(1)}.';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        border: Border.all(color: AppTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _mark(Icons.close_rounded, AppTokens.danger, 'Not this: $wrong'),
          const SizedBox(height: 8),
          _mark(Icons.check_rounded, AppTokens.good, 'Do this: ${m.right}'),
        ],
      ),
    );
  }

  Widget _mark(IconData icon, Color color, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 26),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 17,
            height: 1.4,
            color: AppTokens.text,
          ),
        ),
      ),
    ],
  );
}

/// Spoken cues on or off (the guide and the recorder share it).
class SpeechToggle extends StatelessWidget {
  final Color? color;
  const SpeechToggle({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final g = context.watch<GuideViewModel>();
    return IconButton(
      key: const Key('speech_toggle'),
      tooltip: g.speechOn ? 'Turn spoken cues off' : 'Turn spoken cues on',
      icon: Icon(
        g.speechOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
        color: color ?? AppTokens.primary,
      ),
      onPressed: () => g.setSpeechOn(!g.speechOn),
    );
  }
}
