import 'package:physical_treatment_and_health_support_system/device_platform/speech/speech_output.dart';
import 'package:physical_treatment_and_health_support_system/model/result.dart';

/// Spoken exercise cues (Elwin, 23 Oct): the guide reads its pages aloud and the recorder
/// counts the patient in and calls each movement. Not in the report's service list
/// (PROJECT_STATE §11). Like every service it never throws: a phone without a speech engine
/// simply stays quiet.
class SpeechService {
  final SpeechOutput _out;

  SpeechService([SpeechOutput? out]) : _out = out ?? PluginSpeechOutput();

  Future<Result<void>> say(String text) => guard(
    () => _out.speak(text),
    message: 'Spoken cues are not available on this phone.',
    code: 'no_speech',
  );

  Future<Result<void>> stop() => guard(_out.stop, code: 'no_speech');
}
