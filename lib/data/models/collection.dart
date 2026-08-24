// lib/data/models/collection.dart
//
// A word collection (EN-32 / EN-34 / KK-5).
//
// The count here comes from the server as `count(*)` over the pack's actual
// rows. That is the whole reason this model exists: `WordPack` in
// lib/services/meta_store.dart carried a `size` typed in by hand — 120 for
// "IELTS 6.5+" — while the words themselves were whatever the shared
// dictionary happened to hold at that topic and level, which was fourteen.
// A number nobody could verify is a number that will eventually be wrong.

import '../../core/i18n/l10n.dart';

class WordCollection {
  final int id;
  final String slug, emoji, colour;
  final String titleKk, titleRu, subtitleKk, subtitleRu;
  final String? topic;
  final List<String> levels;
  /// True for a curated pack everyone sees; false for one the learner made.
  final bool isOfficial;
  /// True when this learner owns it, and may therefore rename or delete it.
  final bool isMine;
  /// How many words are actually in it. Not a wish.
  final int wordCount;
  /// How many of those the learner already has in their own bank — the only
  /// honest basis for a progress bar on a pack.
  final int ownedCount;

  const WordCollection({
    required this.id,
    required this.titleKk,
    this.slug = '',
    this.titleRu = '',
    this.subtitleKk = '',
    this.subtitleRu = '',
    this.emoji = '📚',
    this.colour = '#7C5CFF',
    this.topic,
    this.levels = const [],
    this.isOfficial = true,
    this.isMine = false,
    this.wordCount = 0,
    this.ownedCount = 0,
  });

  factory WordCollection.fromMap(Map<String, dynamic> m) => WordCollection(
    id:         ((m['id'] ?? 0) as num).toInt(),
    slug:       (m['slug'] ?? '').toString(),
    titleKk:    (m['title_kk'] ?? '').toString(),
    titleRu:    (m['title_ru'] ?? '').toString(),
    subtitleKk: (m['subtitle_kk'] ?? '').toString(),
    subtitleRu: (m['subtitle_ru'] ?? '').toString(),
    emoji:      (m['emoji'] ?? '📚').toString(),
    colour:     (m['colour'] ?? '#7C5CFF').toString(),
    topic:      m['topic']?.toString(),
    levels: [
      for (final l in (m['levels'] as List? ?? const [])) l.toString(),
    ],
    isOfficial: (m['is_official'] ?? true) as bool,
    isMine:     (m['is_mine'] ?? false) as bool,
    wordCount:  ((m['word_count'] ?? 0) as num).toInt(),
    ownedCount: ((m['owned_count'] ?? 0) as num).toInt(),
  );

  /// Falls back to the Kazakh when a pack has no Russian title — a personal
  /// collection is stored with the learner's own words on both sides, and a
  /// blank title would be worse than an untranslated one.
  String get title =>
      AppLang.isRu && titleRu.trim().isNotEmpty ? titleRu : titleKk;

  String get subtitle =>
      AppLang.isRu && subtitleRu.trim().isNotEmpty ? subtitleRu : subtitleKk;

  double get progress =>
      wordCount == 0 ? 0 : (ownedCount / wordCount).clamp(0.0, 1.0);

  /// A pack with nothing in it cannot build a round, and saying so up front is
  /// better than starting one that fails.
  bool get isEmpty => wordCount == 0;
}
