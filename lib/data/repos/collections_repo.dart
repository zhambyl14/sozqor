// lib/data/repos/collections_repo.dart
//
// Word collections (EN-32 / EN-34 / EN-38 / KK-5), talking to the RPCs in
// supabase/sql/v5_collections.sql.
//
// The named bug this replaces: "IELTS 6.5+" said 120 words and produced about
// fourteen questions. Both numbers were true. The 120 was a literal typed into
// kWordPacks and compiled into the app; the words were whatever the shared
// dictionary happened to hold at that topic and level, which was fourteen. A
// pack was never a set of words — it was a filter with a wish written next to
// it, and no moderator could add to it without an app-store release.
//
// A pack is a list of rows now, and [WordCollection.wordCount] is count(*),
// which cannot disagree with what a round can find.
//
// Until the SQL is applied every call here raises, and the screens fall back
// to the compiled-in packs. [CollectionsUnavailable] is how they tell.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/collection.dart';
import '../models/dict_entry.dart';
import '../supa.dart';

/// Thrown when the collection RPCs are not on the server yet.
class CollectionsUnavailable implements Exception {
  const CollectionsUnavailable();
}

class CollectionsRepo {
  static bool _isMissing(Object e) {
    if (e is! PostgrestException) return false;
    final code = e.code ?? '';
    if (code == 'PGRST202' || code == 'PGRST203' || code == '42883') return true;
    final m = e.message.toLowerCase();
    return m.contains('could not find the function') ||
        m.contains('does not exist');
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      if (_isMissing(e)) throw const CollectionsUnavailable();
      rethrow;
    }
  }

  /// Every pack the learner can see: the official ones plus their own.
  Future<List<WordCollection>> catalogue() => _guard(() async {
    final rows = await supa.rpc('pack_catalogue');
    return [
      for (final r in (rows as List? ?? const []))
        WordCollection.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  });

  /// One page of a pack. Twenty at a time — a pack a moderator can top up is
  /// exactly the kind of list that grows without a ceiling (EN-54).
  Future<List<DictEntry>> words(int packId,
      {int limit = 20, int offset = 0}) => _guard(() async {
    final rows = await supa.rpc('pack_words', params: {
      'p_pack': packId, 'p_limit': limit, 'p_offset': offset,
    });
    return [
      for (final r in (rows as List? ?? const []))
        DictEntry.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  });

  /// The whole pack, not the first page of it.
  ///
  /// `pack_words` caps a page at 100 rows on the server, so anything that
  /// needs the real set — building a round, or marking which dictionary rows
  /// are already in — has to walk the pages. Callers used to ask for 100 and
  /// treat that as "everything", which was the same shape of lie this whole
  /// feature exists to end: once a pack passes a hundred words, the round is
  /// quietly drawn from the first hundred only.
  Future<List<DictEntry>> allWords(int packId, {int max = 600}) async {
    const page = 100;
    final out = <DictEntry>[];
    while (out.length < max) {
      final chunk = await words(packId, limit: page, offset: out.length);
      out.addAll(chunk);
      if (chunk.length < page) break;
    }
    return out;
  }

  // ── The learner's own (EN-34) ──────────────────────────
  Future<int> create({
    required String title,
    String emoji = '📚',
    String colour = '#7C5CFF',
  }) => _guard(() async => ((await supa.rpc('create_my_pack', params: {
        'p_title': title.trim(),
        'p_emoji': emoji,
        'p_colour': colour,
      }) ?? 0) as num).toInt());

  Future<void> rename(int packId, String title) => _guard(() async {
    await supa.rpc('rename_my_pack',
        params: {'p_pack': packId, 'p_title': title.trim()});
  });

  Future<void> remove(int packId) => _guard(() async {
    await supa.rpc('delete_my_pack', params: {'p_pack': packId});
  });

  /// Adds a word the learner already has. EN-34's actual point is that this
  /// takes one tap and no retyping of something the dictionary already holds.
  Future<int> addWord(int packId, int dictionaryId) =>
      _guard(() async => ((await supa.rpc('add_word_to_pack', params: {
            'p_pack': packId, 'p_dictionary_id': dictionaryId,
          }) ?? 0) as num).toInt());

  Future<int> removeWord(int packId, int dictionaryId) =>
      _guard(() async => ((await supa.rpc('remove_word_from_pack', params: {
            'p_pack': packId, 'p_dictionary_id': dictionaryId,
          }) ?? 0) as num).toInt());

  // ── Moderator (EN-38 / KK-7) ───────────────────────────
  /// Tops a pack up from the dictionary. This is the thing that was
  /// impossible before: expanding a collection meant editing a Dart constant
  /// and shipping a release.
  Future<int> fillFromDictionary(int packId, {
    String? topic,
    List<String>? levels,
    int limit = 200,
  }) => _guard(() async => ((await supa.rpc('admin_fill_pack', params: {
        'p_pack': packId,
        'p_topic': topic,
        'p_levels': levels,
        'p_limit': limit,
      }) ?? 0) as num).toInt());

  Future<int> addWords(int packId, List<int> dictionaryIds) =>
      _guard(() async => ((await supa.rpc('admin_pack_add_words', params: {
            'p_pack': packId, 'p_ids': dictionaryIds,
          }) ?? 0) as num).toInt());

  Future<int> adminRemoveWord(int packId, int dictionaryId) =>
      _guard(() async => ((await supa.rpc('admin_pack_remove_word', params: {
            'p_pack': packId, 'p_dictionary_id': dictionaryId,
          }) ?? 0) as num).toInt());

  /// Creates or renames an official pack.
  ///
  /// `is_active` is not a parameter here on purpose: `pack_catalogue` only
  /// returns active packs, and this repository is the only way the console
  /// lists them — a pack switched off from the editor would vanish from the
  /// one screen that could switch it back on.
  Future<int> savePack({
    int? id,
    required String titleKk,
    String titleRu = '',
    String subtitleKk = '',
    String subtitleRu = '',
    String emoji = '📚',
    String colour = '#7C5CFF',
    String? topic,
    List<String> levels = const [],
    int sort = 0,
  }) => _guard(() async {
    final slug = await _freeSlug(_slugify(titleKk), exceptId: id);
    return ((await supa.rpc('admin_upsert_pack', params: {
      'p_id': id,
      'p_slug': slug,
      'p_title_kk': titleKk.trim(),
      'p_title_ru': titleRu.trim(),
      'p_subtitle_kk': subtitleKk.trim(),
      'p_subtitle_ru': subtitleRu.trim(),
      'p_emoji': emoji,
      'p_colour': colour,
      'p_topic': topic,
      'p_levels': levels,
      'p_sort': sort,
      'p_is_active': true,
    }) ?? 0) as num).toInt();
  });

  /// `word_packs.slug` is unique and nothing on screen ever shows it, so it is
  /// derived rather than typed — one less field that can fail a save.
  static String _slugify(String title) {
    final buf = StringBuffer();
    for (final ch in title.toLowerCase().split('')) {
      final mapped = _packTranslit[ch];
      if (mapped != null) {
        buf.write(mapped);
      } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        buf.write(ch);
      } else {
        buf.write('-');
      }
    }
    var slug = buf
        .toString()
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.length > 40) slug = slug.substring(0, 40);
    slug = slug.replaceAll(RegExp(r'-+$'), '');
    return slug.isEmpty ? 'pack' : slug;
  }

  /// The first free variant of [base]. Two packs may legitimately be called
  /// the same thing, and a unique-violation from Postgres is not an answer a
  /// moderator can act on.
  Future<String> _freeSlug(String base, {int? exceptId}) async {
    final rows =
        await supa.from('word_packs').select('id, slug').like('slug', '$base%');
    final taken = <String>{
      for (final r in rows as List)
        if (((r as Map)['id'] as num?)?.toInt() != exceptId)
          ((r)['slug'] ?? '').toString(),
    };
    if (!taken.contains(base)) return base;
    for (var i = 2; i < 500; i++) {
      if (!taken.contains('$base-$i')) return '$base-$i';
    }
    return '$base-${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// Kazakh and Russian Cyrillic to latin, for [CollectionsRepo._slugify].
const Map<String, String> _packTranslit = {
  'а': 'a', 'ә': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ғ': 'g', 'д': 'd',
  'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k',
  'қ': 'q', 'л': 'l', 'м': 'm', 'н': 'n', 'ң': 'ng', 'о': 'o', 'ө': 'o',
  'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ұ': 'u', 'ү': 'u',
  'ф': 'f', 'х': 'h', 'һ': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch',
  'ъ': '', 'ы': 'y', 'і': 'i', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
};
