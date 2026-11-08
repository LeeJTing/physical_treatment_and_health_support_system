import 'package:physical_treatment_and_health_support_system/model/business_logic/speech_service/speech_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

/// The exercise guide's voice (Elwin, 23 Oct): whether spoken cues are on, and saying them. One
/// for the whole app, so the switch keeps its place between the guide and the recorder. On by
/// default each time the app starts.
class GuideViewModel extends BaseViewModel {
  final SpeechService _speech;

  GuideViewModel(this._speech);

  bool _speechOn = true;
  bool get speechOn => _speechOn;

  void setSpeechOn(bool on) {
    _speechOn = on;
    if (!on) _speech.stop();
    notifyListeners();
  }

  /// Says [text] when spoken cues are on.
  Future<void> say(String text) async {
    if (_speechOn) await _speech.say(text);
  }

  Future<void> quiet() async => _speech.stop();
import 'package:physical_treatment_and_health_support_system/model/business_logic/user_guide_service/user_guide_service.dart';
import 'package:physical_treatment_and_health_support_system/viewmodel/base_view_model.dart';

/// First-visit picture guides: a screen asks [shouldShow] when it opens; the guide is shown once
/// per phone and can always be opened again from the screen's help button.
class GuideViewModel extends BaseViewModel {
  final UserGuideService _service;

  GuideViewModel(this._service);

  /// Asked once per app session at most, so a screen that is opened again does not ask twice.
  final Set<String> _asked = {};

  Future<bool> shouldShow(String key) async {
    if (!_asked.add(key)) return false;
    final seen = (await _service.hasSeen(key)).dataOrNull ?? true;
    return !seen;
  }

  Future<void> markSeen(String key) async {
    await _service.markSeen(key);
  }

  /// Every guide opens by itself again the next time its screen is used.
  Future<void> showAllAgain(Iterable<String> keys) async {
    _asked.clear();
    await _service.resetAll(keys);
    notifyListeners();
  }
}
