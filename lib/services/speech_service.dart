import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper around speech_to_text for dictating into text fields.
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final SpeechToText _speech = SpeechToText();
  bool _available = false;

  bool get isListening => _speech.isListening;

  /// Initializes the engine and requests permission. Returns true if speech
  /// recognition is available on this device.
  Future<bool> init() async {
    try {
      _available = await _speech.initialize(
        onError: (e) => debugPrint('Speech error: ${e.errorMsg}'),
        onStatus: (s) => debugPrint('Speech status: $s'),
      );
    } catch (e) {
      debugPrint('Speech init failed: $e');
      _available = false;
    }
    return _available;
  }

  /// Starts listening. [onResult] is called with the (possibly partial)
  /// recognized text as the user speaks.
  Future<void> listen({
    required void Function(String text) onResult,
  }) async {
    if (!_available) {
      final ok = await init();
      if (!ok) return;
    }
    await _speech.listen(
      onResult: (result) => onResult(result.recognizedWords),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}
