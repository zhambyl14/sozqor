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
}
