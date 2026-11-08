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
}
