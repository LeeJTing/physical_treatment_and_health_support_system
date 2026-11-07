import 'package:flutter_tts/flutter_tts.dart';

/// The phone's text-to-speech, for spoken exercise cues (Elwin, 23 Oct). Behind an interface so
/// tests use a fake and no view calls the plugin directly.
abstract interface class SpeechOutput {
  /// Says [text], cutting off anything still being said.
  Future<void> speak(String text);

  Future<void> stop();
}

/// [SpeechOutput] on flutter_tts: British English when the phone has it, else US English, a
/// little slower than normal so cues are easy to follow from a few metres away.
class PluginSpeechOutput implements SpeechOutput {
  final FlutterTts _tts = FlutterTts();
  Future<void>? _ready;

  Future<void> _init() async {
    final gb = await _tts.isLanguageAvailable('en-GB');
    await _tts.setLanguage(gb == true ? 'en-GB' : 'en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.awaitSpeakCompletion(false);
  }

  @override
  Future<void> speak(String text) async {
    await (_ready ??= _init());
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async => _tts.stop();
}
