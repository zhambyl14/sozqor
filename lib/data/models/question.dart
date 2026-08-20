// lib/data/models/question.dart
import '../../core/constants/game_meta.dart';

/// One playable question. Built locally from words / dictionary entries so a
/// round never needs a network call once the content is in hand.
class Question {
  final QKind  kind;
  final String? wordId;        // personal word this trains, when there is one
  final String  prompt;        // the thing shown big
  final String? subPrompt;     // transcription, part of speech, hint
  final String  answer;
  final List<String> options;  // includes [answer]; empty for spelling
  final List<String> letters;  // scrambled letters for QKind.spelling
  final String? speakText;     // what TTS should read for listening rounds

  const Question({
    required this.kind,
    required this.prompt,
    required this.answer,
    this.options   = const [],
    this.letters   = const [],
    this.wordId,
    this.subPrompt,
    this.speakText,
  });

  /// What a spelling round actually has to be built out of. Letters are handed
  /// out without spaces, so a two-word answer is compared without them too —
  /// otherwise "post office" could never be assembled correctly.
  String get spellTarget => answer.trim().replaceAll(RegExp(r'\s+'), '');

  bool isCorrect(String given) {
    final a = given.trim().toLowerCase();
    final b = answer.trim().toLowerCase();
    if (a == b) return true;
    if (kind == QKind.spelling) {
      return a.replaceAll(RegExp(r'\s+'), '') ==
             b.replaceAll(RegExp(r'\s+'), '');
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'word_id': wordId,
    'prompt': prompt,
    'sub': subPrompt,
    'answer': answer,
    'options': options,
    'letters': letters,
    'speak': speakText,
  };

  factory Question.fromJson(Map<String, dynamic> m) => Question(
    kind:      QKindMeta.fromId((m['kind'] ?? 'kkEn').toString()),
    wordId:    m['word_id']?.toString(),
    prompt:    (m['prompt'] ?? '').toString(),
    subPrompt: m['sub']?.toString(),
    answer:    (m['answer'] ?? '').toString(),
    options:   (m['options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    letters:   (m['letters'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    speakText: m['speak']?.toString(),
  );
}

/// A single answered question, ready to be posted to `record_quiz`.
class AnswerLog {
  final String? wordId;
  final bool correct;
  final int ms;
  final QKind kind;
  const AnswerLog({
    required this.correct,
    required this.ms,
    required this.kind,
    this.wordId,
  });

  Map<String, dynamic> toJson() => {
    'word_id': wordId,
    'correct': correct,
    'ms': ms,
    'game': kind.name,
  };
}
