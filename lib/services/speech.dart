// lib/services/speech.dart
import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around the platform text-to-speech engine, used by the
/// listening game and the word detail screen. Every call is best-effort: a
/// device without a voice installed simply stays silent instead of crashing.
class Speech {
  Speech._();
  static final Speech instance = Speech._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _available = true;

  Future<void> _init() async {
    if (_ready) return;
    _ready = true;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {
      _available = false;
    }
  }

  bool get available => _available;

  Future<void> say(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _init();
    if (!_available) return;
    try {
      await _tts.stop();
      await _tts.speak(t);
    } catch (_) {
      _available = false;
    }
  }

  Future<void> slow(String text) async {
    await _init();
    if (!_available) return;
    try {
      await _tts.stop();
      await _tts.setSpeechRate(0.28);
      await _tts.speak(text.trim());
      await _tts.setSpeechRate(0.42);
    } catch (_) {/* ignore */}
  }

  Future<void> stop() async {
    if (!_ready || !_available) return;
    try { await _tts.stop(); } catch (_) {/* ignore */}
  }
}
