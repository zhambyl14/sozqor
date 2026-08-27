// lib/services/listen.dart
//
// The microphone.
//
// The pronunciation drill has always been self-marked, and said so on screen,
// because scoring speech needed a recognition engine nobody wanted to ship.
// It turns out the model already answering translations can do it over an
// ordinary HTTPS request: send a couple of seconds of audio, get back what it
// heard. So the drill can stop asking the learner to grade themselves, and
// the chat partner can be spoken to instead of typed at.
//
// Recording goes through `startStream`, not `start(path:)`, on purpose: a
// stream needs no temporary file and therefore no path_provider, works the
// same on every platform, and hands over raw PCM that this file wraps in a
// WAV header itself. Forty-four bytes of header is the whole difference
// between "unsupported media type" and a transcript.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:record/record.dart';

/// 16 kHz mono is what speech recognition wants and no more.
///
/// At 44.1 kHz stereo — the package default — three seconds of speech is over
/// half a megabyte before base64 inflates it by a third, for no gain at all:
/// nothing above 8 kHz carries a consonant.
const int kSampleRate = 16000;

/// A recording longer than this is not a word and not a sentence, and the
/// button is held down by a thumb that may have forgotten it.
const Duration kMaxRecording = Duration(seconds: 12);

class Listen {
  Listen._();
  static final Listen instance = Listen._();

  final AudioRecorder _rec = AudioRecorder();
  final List<int> _pcm = [];
  StreamSubscription<Uint8List>? _sub;
  Timer? _cap;
  bool _recording = false;

  bool get isRecording => _recording;

  /// Whether the platform will let us listen at all.
  ///
  /// Asks for the permission if it has not been granted, which is the only
  /// moment it is honest to ask: the learner has just pressed a microphone.
  Future<bool> ready() async {
    try {
      return await _rec.hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// Starts recording. Returns false when the microphone is unavailable —
  /// no permission, no device, a platform that does not support it — and the
  /// caller falls back to whatever it did before there was a microphone.
  Future<bool> start() async {
    if (_recording) return true;
    try {
      if (!await _rec.hasPermission()) return false;
      final stream = await _rec.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: kSampleRate,
        numChannels: 1,
        // A phone held at arm's length in a room with other people is the
        // normal case, not the exception.
        echoCancel: true,
        noiseSuppress: true,
      ));
      _pcm.clear();
      _recording = true;
      _sub = stream.listen(_pcm.addAll, onError: (_) => stop());
      // A thumb that never lifts must not fill memory for ever.
      _cap = Timer(kMaxRecording, () { if (_recording) stop(); });
      return true;
    } catch (_) {
      _recording = false;
      return false;
    }
  }

  /// Stops, and returns the recording as base64 WAV — or null when there was
  /// nothing usable in it.
  Future<String?> stop() async {
    if (!_recording) return null;
    _recording = false;
    _cap?.cancel();
    _cap = null;
    try {
      await _rec.stop();
    } catch (_) {
      // Already stopped, or the platform lost the session. Whatever arrived
      // before that is still worth sending.
    }
    await _sub?.cancel();
    _sub = null;

    final bytes = Uint8List.fromList(_pcm);
    _pcm.clear();
    // Under a fifth of a second is a mis-tap, not a word.
    if (bytes.length < kSampleRate ~/ 5 * 2) return null;
    return base64Encode(_wav(bytes));
  }

  /// Throws the recording away without asking anybody about it.
  Future<void> cancel() async {
    _recording = false;
    _cap?.cancel();
    _cap = null;
    try { await _rec.stop(); } catch (_) {/* nothing to stop */}
    await _sub?.cancel();
    _sub = null;
    _pcm.clear();
  }

  Future<void> dispose() async {
    await cancel();
    await _rec.dispose();
  }

  /// The 44-byte RIFF header the recogniser needs in front of raw PCM.
  static Uint8List _wav(Uint8List pcm, {int rate = kSampleRate}) {
    final out = Uint8List(44 + pcm.length);
    final dv = ByteData.view(out.buffer);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        out[at + i] = s.codeUnitAt(i);
      }
    }

    ascii(0, 'RIFF');
    dv.setUint32(4, 36 + pcm.length, Endian.little);
    ascii(8, 'WAVEfmt ');
    dv.setUint32(16, 16, Endian.little);   // header length
    dv.setUint16(20, 1, Endian.little);    // PCM
    dv.setUint16(22, 1, Endian.little);    // mono
    dv.setUint32(24, rate, Endian.little);
    dv.setUint32(28, rate * 2, Endian.little);
    dv.setUint16(32, 2, Endian.little);
    dv.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    dv.setUint32(40, pcm.length, Endian.little);
    out.setRange(44, out.length, pcm);
    return out;
  }
}

/// What came back from one attempt at saying a word.
class Heard {
  /// What the model actually heard, in English.
  final String heard;

  /// Whether that counts as the word the learner was asked for. An accent is
  /// fine; a different word is not.
  final bool ok;

  /// 0 nothing usable, 1 wrong word, 2 recognisable but off, 3 clear.
  final int score;

  /// One short line, in the learner's own language, naming the sound to fix.
  /// Empty when there is nothing to fix.
  final String tip;

  const Heard({
    required this.heard,
    required this.ok,
    required this.score,
    required this.tip,
  });

  factory Heard.fromMap(Map<String, dynamic> m) => Heard(
    heard: (m['heard'] ?? '').toString().trim(),
    ok: m['ok'] == true,
    score: switch (m['score']) {
      final num n => n.round().clamp(0, 3),
      _ => 0,
    },
    tip: (m['tip'] ?? '').toString().trim(),
  );
}
