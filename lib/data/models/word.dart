// lib/data/models/word.dart
import 'dict_entry.dart';
import '../../core/i18n/l10n.dart';

/// A word in the learner's personal bank.
class Word {
  final String id, userId, kk, en;
  final String? ru;
  final String? pos, definitionEn, exampleEn, transcription, emoji;
  final List<String> synonyms, antonyms;
  final String cefr, topic, source;
  final int    mastery, correct, attempts, streakCorrect;
  final bool   isFavorite, isLearned;
  final DateTime? nextReview, lastReviewed;
  final DateTime createdAt;

  /// The shared-dictionary row this word came from, when it came from one.
  ///
  /// Null for a word typed by hand or produced by the AI, which is why a word
  /// collection can only hold some of the bank: a pack entry points at a
  /// dictionary row, and there is nothing for a hand-typed word to point at.
  final int? dictionaryId;

  const Word({
    required this.id,
    required this.userId,
    required this.kk,
    required this.en,
    this.ru,
    this.pos,
    this.definitionEn,
    this.exampleEn,
    this.transcription,
    this.emoji,
    this.synonyms = const [],
    this.antonyms = const [],
    this.cefr    = 'A2',
    this.topic   = 'general',
    this.source  = 'manual',
    this.mastery = 0,
    this.correct = 0,
    this.attempts = 0,
    this.streakCorrect = 0,
    this.isFavorite = false,
    this.isLearned  = false,
    this.nextReview,
    this.lastReviewed,
    this.dictionaryId,
    required this.createdAt,
  });

  static List<String> _strList(dynamic v) => v is List
      ? v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
      : const [];

  factory Word.fromMap(Map<String, dynamic> m) => Word(
    id:            m['id'].toString(),
    userId:        (m['user_id'] ?? '').toString(),
    kk:            (m['kk'] ?? '').toString(),
    en:            (m['en'] ?? '').toString(),
    ru:            m['ru']?.toString(),
    pos:           m['pos']?.toString(),
    definitionEn:  m['definition_en']?.toString(),
    exampleEn:     m['example_en']?.toString(),
    transcription: m['transcription']?.toString(),
    emoji:         m['emoji']?.toString(),
    synonyms:      _strList(m['synonyms']),
    antonyms:      _strList(m['antonyms']),
    dictionaryId:  m['dictionary_id'] == null
                     ? null : (m['dictionary_id'] as num).toInt(),
    cefr:          (m['cefr']   ?? 'A2').toString(),
    topic:         (m['topic']  ?? 'general').toString(),
    source:        (m['source'] ?? 'manual').toString(),
    mastery:       (m['mastery'] ?? 0) as int,
    correct:       (m['correct'] ?? 0) as int,
    attempts:      (m['attempts'] ?? 0) as int,
    streakCorrect: (m['streak_correct'] ?? 0) as int,
    isFavorite:    (m['is_favorite'] ?? false) as bool,
    isLearned:     (m['is_learned'] ?? false) as bool,
    nextReview:    m['next_review'] == null
        ? null : DateTime.tryParse(m['next_review'].toString()),
    lastReviewed:  m['last_reviewed'] == null
        ? null : DateTime.tryParse(m['last_reviewed'].toString()),
    createdAt:     DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
  );

  DictEntry toDictEntry() => DictEntry(
    en: en, kk: kk, ru: ru, pos: pos, definitionEn: definitionEn,
    exampleEn: exampleEn, ipa: transcription, emoji: emoji,
    synonyms: synonyms, antonyms: antonyms, cefr: cefr, topic: topic,
  );

  /// The learner's own-language side. Study language is chosen in settings
  /// and is independent of the interface language; Russian falls back to
  /// Kazakh when a word has no Russian entry yet.
  String native(String lang) =>
      lang == 'ru' && (ru ?? '').trim().isNotEmpty ? ru!.trim() : kk;

  bool get isDue =>
      nextReview == null || DateTime.now().isAfter(nextReview!);

  double get accuracy => attempts == 0 ? 0 : correct / attempts;

  String get masteryLabel => switch (mastery) {
    0 => tr('Жаңа'),
    1 => tr('Танысу'),
    2 => tr('Үйренуде'),
    3 => tr('Жақсы'),
    4 => tr('Мықты'),
    _ => tr('Меңгерілді'),
  };

  /// Progress ring value 0..1 for the word card.
  double get masteryProgress => (mastery / 5).clamp(0.0, 1.0);

  Word copyWith({
    String? kk, String? en, String? pos, String? definitionEn,
    String? exampleEn, String? transcription, String? emoji,
    List<String>? synonyms, List<String>? antonyms,
    String? cefr, String? topic,
    int? mastery, bool? isFavorite, bool? isLearned,
  }) => Word(
    id: id, userId: userId, ru: ru,
    kk:            kk            ?? this.kk,
    en:            en            ?? this.en,
    pos:           pos           ?? this.pos,
    definitionEn:  definitionEn  ?? this.definitionEn,
    exampleEn:     exampleEn     ?? this.exampleEn,
    transcription: transcription ?? this.transcription,
    emoji:         emoji         ?? this.emoji,
    synonyms:      synonyms      ?? this.synonyms,
    antonyms:      antonyms      ?? this.antonyms,
    cefr:          cefr          ?? this.cefr,
    topic:         topic         ?? this.topic,
    source:        source,
    mastery:       mastery       ?? this.mastery,
    correct:       correct,
    attempts:      attempts,
    streakCorrect: streakCorrect,
    isFavorite:    isFavorite    ?? this.isFavorite,
    isLearned:     isLearned     ?? this.isLearned,
    nextReview:    nextReview,
    lastReviewed:  lastReviewed,
    createdAt:     createdAt,
  );
}
