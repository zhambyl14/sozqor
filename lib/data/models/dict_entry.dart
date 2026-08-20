// lib/data/models/dict_entry.dart

/// One row of the shared `dictionary` table — the "SozQor brain".
/// Also used for the bundled offline starter dictionary.
class DictEntry {
  final int?   id;
  final String en, kk;
  final String? ru;
  final String? pos, definitionEn, exampleEn, exampleKk, ipa, emoji;
  final List<String> synonyms, antonyms;
  final String cefr, topic, source;
  final int    hits;

  const DictEntry({
    this.id,
    required this.en,
    required this.kk,
    this.ru,
    this.pos,
    this.definitionEn,
    this.exampleEn,
    this.exampleKk,
    this.ipa,
    this.emoji,
    this.synonyms = const [],
    this.antonyms = const [],
    this.cefr   = 'A2',
    this.topic  = 'general',
    this.source = 'ai',
    this.hits   = 0,
  });

  static List<String> _strList(dynamic v) {
    if (v is List) {
      return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    }
    return const [];
  }

  factory DictEntry.fromMap(Map<String, dynamic> m) => DictEntry(
    id:           m['id'] is int ? m['id'] as int : int.tryParse('${m['id']}'),
    en:           (m['en'] ?? '').toString(),
    kk:           (m['kk'] ?? '').toString(),
    ru:           m['ru']?.toString(),
    pos:          m['pos']?.toString(),
    definitionEn: m['definition_en']?.toString(),
    exampleEn:    m['example_en']?.toString(),
    exampleKk:    m['example_kk']?.toString(),
    ipa:          m['ipa']?.toString(),
    emoji:        m['emoji']?.toString(),
    synonyms:     _strList(m['synonyms']),
    antonyms:     _strList(m['antonyms']),
    cefr:         (m['cefr']  ?? 'A2').toString(),
    topic:        (m['topic'] ?? 'general').toString(),
    source:       (m['source'] ?? 'ai').toString(),
    hits:         (m['hits'] ?? 0) is int ? (m['hits'] ?? 0) as int : 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'en': en, 'kk': kk, 'ru': ru, 'pos': pos,
    'definition_en': definitionEn, 'example_en': exampleEn,
    'example_kk': exampleKk, 'ipa': ipa, 'emoji': emoji,
    'synonyms': synonyms, 'antonyms': antonyms,
    'cefr': cefr, 'topic': topic, 'source': source,
  };

  /// Own-language side for the chosen study language, falling back to Kazakh.
  String native(String lang) =>
      lang == 'ru' && (ru ?? '').trim().isNotEmpty ? ru!.trim() : kk;

  bool get hasDefinition => (definitionEn ?? '').trim().isNotEmpty;
  bool get hasSynonyms   => synonyms.isNotEmpty;
  bool get hasAntonyms   => antonyms.isNotEmpty;
  String get display     => '${emoji ?? ''} $en'.trim();
}
