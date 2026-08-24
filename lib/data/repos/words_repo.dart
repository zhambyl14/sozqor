// lib/data/repos/words_repo.dart
import 'package:supabase_flutter/supabase_flutter.dart' show CountOption;

import '../models/dict_entry.dart';
import '../models/question.dart';
import '../models/word.dart';
import '../supa.dart';
import '../../core/i18n/l10n.dart';

/// How many words one trip to the server carries (EN-36 / KK-5).
///
/// The bank used to select every row a learner owned and hand the whole list
/// to a ListView, so opening the tab on a mature account parsed hundreds of
/// rows on the UI thread before it drew anything. Twenty is roughly two
/// screens: enough that the first page never looks short, small enough that
/// it lands instantly.
const int kWordPageSize = 20;

class WordsRepo {
  /// One page of the learner's own words, newest first.
  ///
  /// [limit] deliberately has no "everything" value. Callers that genuinely
  /// need the whole bank — the round builders, which take a bounded sample
  /// anyway — ask for an explicit large limit and say why.
  Future<List<Word>> page({int limit = kWordPageSize, int offset = 0}) async {
    final uid = currentUid;
    if (uid == null) return [];
    final rows = await supa
        .from('words').select().eq('user_id', uid)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .map((r) => Word.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// The sample the question factory and the home feed build from. Bounded
  /// so a large bank cannot stall a round.
  Future<List<Word>> all({int limit = 200}) => page(limit: limit);

  Future<int> totalCount() async {
    final uid = currentUid;
    if (uid == null) return 0;
    return supa.from('words').count(CountOption.exact).eq('user_id', uid);
  }

  Stream<List<Word>> watch() {
    final uid = currentUid;
    if (uid == null) return Stream.value(const []);
    return supa
        .from('words')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .map((rows) => rows
            .map((r) => Word.fromMap(Map<String, dynamic>.from(r)))
            .toList());
  }

  /// Words whose review date has come, oldest first.
  Future<List<Word>> due({int limit = 30}) async {
    final uid = currentUid;
    if (uid == null) return [];
    final rows = await supa
        .from('words').select()
        .eq('user_id', uid)
        .lte('next_review', DateTime.now().toUtc().toIso8601String())
        .order('next_review')
        .limit(limit);
    return (rows as List)
        .map((r) => Word.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// A HEAD count rather than a download. This runs on every home-screen
  /// load, and it used to transfer one row per due word to call `.length` on
  /// the result.
  Future<int> dueCount() async {
    final uid = currentUid;
    if (uid == null) return 0;
    return supa
        .from('words').count(CountOption.exact)
        .eq('user_id', uid)
        .lte('next_review', DateTime.now().toUtc().toIso8601String());
  }

  /// Dictionary ids the learner already owns, so the explore list can leave
  /// them out instead of offering a word that is already saved (EN-39).
  Future<Set<int>> ownedDictionaryIds() async {
    final uid = currentUid;
    if (uid == null) return <int>{};
    final rows = await supa
        .from('words').select('dictionary_id')
        .eq('user_id', uid)
        .not('dictionary_id', 'is', null);
    return {
      for (final r in rows as List)
        if ((r as Map)['dictionary_id'] is int) r['dictionary_id'] as int,
    };
  }

  /// The English side of everything the learner owns, lower-cased. Words
  /// added by hand or by the AI carry no dictionary_id, so id matching alone
  /// would still show them again in the explore list.
  Future<Set<String>> ownedEnglish() async {
    final uid = currentUid;
    if (uid == null) return <String>{};
    final rows = await supa.from('words').select('en').eq('user_id', uid);
    return {
      for (final r in rows as List)
        ((r as Map)['en'] ?? '').toString().trim().toLowerCase(),
    }..remove('');
  }

  Future<bool> exists(String kk, String en) async {
    final uid = currentUid;
    if (uid == null) return false;
    final rows = await supa.from('words').select('id')
        .eq('user_id', uid)
        .ilike('kk', kk.trim())
        .ilike('en', en.trim())
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  Future<Word> add({
    required String kk,
    required String en,
    String? ru,
    String? pos,
    String? definitionEn,
    String? exampleEn,
    String? transcription,
    String? emoji,
    List<String> synonyms = const [],
    List<String> antonyms = const [],
    String cefr = 'A2',
    String topic = 'general',
    String source = 'manual',
    int? dictionaryId,
  }) async {
    final uid = currentUid;
    if (uid == null) throw Exception(tr('Авторизация қажет'));

    final row = await supa.from('words').insert({
      'user_id': uid,
      'kk': kk.trim(),
      'en': en.trim(),
      'ru': (ru ?? '').trim().isEmpty ? null : ru!.trim(),
      'pos': pos,
      'definition_en': definitionEn,
      'example_en': exampleEn,
      'transcription': transcription,
      'emoji': emoji,
      'synonyms': synonyms,
      'antonyms': antonyms,
      'cefr': cefr,
      'topic': topic,
      'source': source,
      'dictionary_id': dictionaryId,
    }).select().single();

    return Word.fromMap(row);
  }

  Future<Word> addFromDict(DictEntry e) => add(
    kk: e.kk, en: e.en, ru: e.ru, pos: e.pos,
    definitionEn: e.definitionEn, exampleEn: e.exampleEn,
    transcription: e.ipa, emoji: e.emoji,
    synonyms: e.synonyms, antonyms: e.antonyms,
    cefr: e.cefr, topic: e.topic,
    source: 'catalog', dictionaryId: e.id,
  );

  /// Adds several catalog entries, silently skipping ones already owned.
  Future<int> addManyFromDict(List<DictEntry> entries) async {
    var added = 0;
    for (final e in entries) {
      try {
        await addFromDict(e);
        added++;
      } catch (_) {
        // duplicate — ignore
      }
    }
    return added;
  }

  Future<void> update(String id, Map<String, dynamic> patch) async {
    await supa.from('words').update(patch).eq('id', id);
  }

  Future<void> remove(String id) async {
    await supa.from('words').delete().eq('id', id);
  }

  Future<void> toggleFavorite(String id, bool value) =>
      update(id, {'is_favorite': value});

  /// Posts a finished round: updates spaced repetition, logs, quests and XP.
  /// Returns (correct, total, xp).
  Future<(int, int, int)> recordQuiz(
    List<AnswerLog> answers, {
    String game = 'mixed',
    int xp = 0,
  }) async {
    final res = await supa.rpc('record_quiz', params: {
      'p_answers': answers.map((a) => a.toJson()).toList(),
      'p_game': game,
      'p_xp': xp,
    });
    final m = Map<String, dynamic>.from(res as Map);
    return ((m['correct'] ?? 0) as int,
            (m['total'] ?? 0) as int,
            (m['xp'] ?? 0) as int);
  }
}
