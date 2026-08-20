// lib/data/repos/words_repo.dart
import '../models/dict_entry.dart';
import '../models/question.dart';
import '../models/word.dart';
import '../supa.dart';
import '../../core/i18n/l10n.dart';

class WordsRepo {
  Future<List<Word>> all() async {
    final uid = currentUid;
    if (uid == null) return [];
    final rows = await supa
        .from('words').select().eq('user_id', uid)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Word.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
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

  Future<int> dueCount() async {
    final uid = currentUid;
    if (uid == null) return 0;
    final rows = await supa
        .from('words').select('id')
        .eq('user_id', uid)
        .lte('next_review', DateTime.now().toUtc().toIso8601String());
    return (rows as List).length;
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
