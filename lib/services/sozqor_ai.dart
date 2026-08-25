// lib/services/sozqor_ai.dart
//
// SozQor AI — translation, one layer at a time.
//
// A lookup walks four layers and stops at the first hit, so the model is only
// ever touched for a word nobody has asked for yet:
//
//   1. session memory     — instant, free
//   2. bundled dictionary — offline, free, ships with the app
//   3. shared dictionary  — every translation any user has ever made
//   4. server call        — several free models in turn, and a keyless
//                           translation service when they are all spent
//
// Layer 4's answers are written back into layer 3, so the same word is never
// paid for twice. None of this is surfaced to the learner — they type a word
// and get a translation.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../data/models/dict_entry.dart';
import '../data/repos/dictionary_repo.dart';
import '../data/supa.dart';
import 'local_dictionary.dart';
import '../core/i18n/l10n.dart';

enum AiSource {
  memory,   // already looked up in this session
  bundled,  // offline dictionary shipped with the app
  shared,   // dictionary rows other users have already produced
  llm,      // a language model
  basic,    // keyless translation used while the AI quota is spent
}

/// The translation gate refused every candidate for this word (EN-49 / KK-8).
///
/// Deliberately its own type rather than a generic Exception. "We could not
/// translate this word" and "your connection failed" call for different words
/// on screen and different behaviour from the learner — one is worth retrying
/// and the other never will be. Before the gate existed the second case did
/// not arise, because a transliteration was always available to hand back.
class TranslationRejected implements Exception {
  /// One of: script, identity, translit, length, disagree.
  final String reason;
  /// Already localised by the edge function, which knows the app language.
  final String message;
  const TranslationRejected(this.reason, this.message);

  @override
  String toString() => message;
}

class AiResult {
  final DictEntry entry;
  final AiSource source;
  const AiResult(this.entry, this.source);

  bool get fromCache => source != AiSource.llm && source != AiSource.basic;

  /// True when the entry is a bare word pair with no definition or example,
  /// so the UI can invite the learner to fill in the rest by hand.
  bool get isBasic => source == AiSource.basic;

  String get sourceLabel => switch (source) {
    AiSource.memory  => tr('жадтан'),
    AiSource.bundled => tr('офлайн сөздіктен'),
    AiSource.shared  => tr('сөздік базадан'),
    AiSource.llm     => tr('AI аудармасы'),
    AiSource.basic   => tr('жылдам аударма'),
  };
}

/// What a [SozQorAI.suggest] call produced, and — separately — what failed.
///
/// The two used to be one value: `catch (_) { return fresh; }` flattened a
/// busy model, an expired session and a genuinely exhausted dictionary into
/// the same empty list. The screen then had nothing to go on and said the
/// only thing an empty list can mean — "жаңа сөз табылмады, кейінірек көр" —
/// even when the true answer was "your token expired, tap again". Those are
/// different sentences and different next steps for the learner, so they
/// travel as different fields.
class SuggestResult {
  final List<DictEntry> entries;

  /// Already run through [humanError], so it is ready to put on screen. Null
  /// when nothing failed; it can also be non-null next to a full list, when
  /// one layer failed and the layer under it covered for it.
  final String? error;

  const SuggestResult(this.entries, {this.error});

  bool get isEmpty => entries.isEmpty;
}

class AiStats {
  int brainHits = 0;
  int llmHits = 0;
  int get total => brainHits + llmHits;
  double get brainShare => total == 0 ? 0 : brainHits / total;
}

class SozQorAI {
  SozQorAI._();
  static final SozQorAI instance = SozQorAI._();

  final _dictRepo = DictionaryRepo();
  final _memory = <String, DictEntry>{};
  final stats = AiStats();

  String _key(String s) => LocalDictionary.norm(s);

  Future<void> warmUp() => LocalDictionary.instance.load();

  /// Translates in either direction and returns everything the app knows about
  /// the word. Throws only when every layer fails.
  Future<AiResult> translate(String term) async {
    final k = _key(term);
    if (k.isEmpty) throw Exception(tr('Сөз жазыңыз'));

    // 1 — session memory
    final mem = _memory[k];
    if (mem != null) {
      stats.brainHits++;
      return AiResult(mem, AiSource.memory);
    }

    // 2 — bundled offline dictionary (exact, then simple word forms)
    await LocalDictionary.instance.load();
    final local = LocalDictionary.instance.lookup(term) ?? _looseLocal(term);
    if (local != null) {
      _remember(local);
      stats.brainHits++;
      return AiResult(local, AiSource.bundled);
    }

    // 3 — shared dictionary grown by every user
    try {
      final shared = await _dictRepo.lookup(term);
      if (shared.isNotEmpty) {
        _remember(shared.first);
        stats.brainHits++;
        return AiResult(shared.first, AiSource.shared);
      }
    } catch (_) {
      // offline — fall through to the server call, which will also fail
      // and produce a network message
    }

    // 4 — ask the server. It walks several free models and, when they are all
    // out of quota, still answers with a plain translation.
    final (entry, basic) = await _askModel(term);
    _remember(entry);
    if (basic) {
      return AiResult(entry, AiSource.basic);
    }
    stats.llmHits++;
    return AiResult(entry, AiSource.llm);
  }

  /// Trailing "s", a missing "to " and other small differences should not
  /// send a lookup all the way to the model.
  DictEntry? _looseLocal(String term) {
    final t = _key(term);
    if (t.length < 3) return null;
    final dict = LocalDictionary.instance;
    final tries = <String>[
      if (t.endsWith('s')) t.substring(0, t.length - 1),
      if (t.endsWith('es')) t.substring(0, t.length - 2),
      if (!t.endsWith('s')) '${t}s',
      t.replaceAll(RegExp(r'[^\p{L}\s]', unicode: true), '').trim(),
    ];
    for (final candidate in tries) {
      if (candidate.length < 3) continue;
      final hit = dict.lookup(candidate);
      if (hit != null) return hit;
    }
    return null;
  }

  void _remember(DictEntry e) {
    _memory[_key(e.en)] = e;
    _memory[_key(e.kk)] = e;
  }

  /// Returns the entry plus whether it came back as a plain fallback
  /// translation rather than a full AI entry.
  Future<(DictEntry, bool)> _askModel(String term) async {
    final data = await _invoke({'task': 'translate', 'text': term});

    // The translation gate refused this candidate (EN-49 / KK-8): it was a
    // transliteration, the word echoed back, or two models that disagreed.
    // The distinction matters to the UI — "we could not translate this" is a
    // different thing to say than "check your connection", and saying the
    // wrong one is how a learner ends up retrying a word that will never
    // resolve.
    if ((data['source'] ?? '').toString() == 'rejected') {
      throw TranslationRejected(
        (data['reason'] ?? '').toString(),
        (data['message'] ?? '').toString().isEmpty
            ? tr('Аударма табылмады')
            : data['message'].toString(),
      );
    }

    final raw = data['entry'];
    if (raw == null) throw Exception(tr('Аударма табылмады'));
    final entry = DictEntry.fromMap(Map<String, dynamic>.from(raw as Map));
    final basic = (data['source'] ?? '').toString() == 'basic';
    return (entry, basic);
  }

  /// Fills in definition / synonyms / antonyms for a word the user already has.
  Future<DictEntry> enrich({required String en, required String kk}) async {
    await LocalDictionary.instance.load();
    final local = LocalDictionary.instance.lookup(en);
    if (local != null && local.hasDefinition && local.hasSynonyms) {
      stats.brainHits++;
      return local;
    }
    try {
      final shared = await _dictRepo.lookup(en);
      if (shared.isNotEmpty && shared.first.hasDefinition) {
        stats.brainHits++;
        return shared.first;
      }
    } catch (_) {/* fall through */}

    final data = await _invoke({'task': 'enrich', 'en': en, 'kk': kk});
    final raw = Map<String, dynamic>.from(data['entry'] as Map);
    stats.llmHits++;
    return DictEntry.fromMap({...raw, 'en': en, 'kk': kk});
  }

  /// Fresh words at the learner's level: the model first, and under it the
  /// shared dictionary as a floor that cannot be rate limited or run out of
  /// quota. Failures come back in [SuggestResult.error] rather than being
  /// flattened into an empty list.
  ///
  /// [exclude] must carry everything the learner OWNS, not just what happens
  /// to be on screen. It is forwarded whole to `dict_discover` on the server,
  /// and the owned words are precisely the ones that must not come back.
  ///
  /// The old version returned early whenever the first 60 shared rows yielded
  /// `count` survivors. Those survivors were filtered against the screen only,
  /// so "enough" routinely meant a dozen words already sitting in the bank,
  /// and the model — the one layer that can produce a word nobody has stored
  /// yet — was never reached at all.
  Future<SuggestResult> suggest({
    required String cefr,
    String topic = 'general',
    int count = 8,
    Set<String> exclude = const {},
  }) async {
    final have = exclude.map(_key).toSet();
    final out = <DictEntry>[];
    final taken = <String>{};
    String? failure;

    void keep(Iterable<DictEntry> rows) {
      for (final e in rows) {
        if (out.length >= count) return;
        final k = _key(e.en);
        if (k.isEmpty || have.contains(k) || have.contains(_key(e.kk))) continue;
        if (!taken.add(k)) continue;
        out.add(e);
      }
    }

    try {
      final data = await _invoke({
        'task': 'suggest',
        'cefr': cefr,
        'topic': topic,
        'count': count,
        // The whole owned set travels, not a screenful of it: the edge
        // function hands it to dict_discover, and forty entries was small
        // enough that a learner with a real bank kept being offered words
        // they had already saved.
        'exclude': exclude.take(200).toList(),
      });
      final before = out.length;
      keep((data['entries'] as List? ?? const [])
          .map((e) => DictEntry.fromMap(Map<String, dynamic>.from(e as Map))));
      if (out.length > before) stats.llmHits++;
    } catch (e) {
      // Kept, not swallowed. Whether the model was busy or the dictionary is
      // genuinely empty decides what the learner is told next.
      failure = humanError(e);
    }

    // The floor. Even with every model down, the dictionary still holds words
    // at this level this learner has never added, and reading them costs one
    // query and no quota — which is the entire point of dict_discover.
    if (out.length < count) {
      try {
        final pool = await _dictRepo.discover(
          cefr: cefr,
          topic: topic,
          exclude: [...exclude, ...taken].take(200).toList(),
          limit: (count - out.length + 20).clamp(1, 50),
        );
        final before = out.length;
        keep(pool);
        if (out.length > before) stats.brainHits++;
      } catch (e) {
        failure ??= humanError(e);
      }
    }

    return SuggestResult(out, error: failure);
  }

  /// A short explanation of an English word, written in [studyLang] — the
  /// language the learner is training against (their "Оқу тілі" setting),
  /// not necessarily the interface language they happen to be reading the
  /// app in right now. Those two can differ on purpose.
  Future<String> explain(String en, {required String studyLang}) async {
    final data = await _invoke(
        {'task': 'explain', 'en': en, 'study_lang': studyLang});
    stats.llmHits++;
    return (data['text'] ?? '').toString().trim();
  }

  // ── Conversation practice ────────────────────────────────

  /// One turn of a role-play conversation. The reply itself always stays
  /// English by design — that is the point of the drill — but [studyLang]
  /// tells the model which language the learner's own is, the same "Оқу
  /// тілі" setting that picks a word's translation elsewhere, so it can
  /// calibrate vocabulary the way a real tutor who spoke that language would.
  ///
  /// The edge function is asked first. When it has no `chat` task deployed, or
  /// every free model is out of quota, [_scriptedReply] answers instead — the
  /// exercise is worth more offline than an error message is, and the learner
  /// never sees which of the two replied.
  Future<String> chat({
    required String scenario,
    required String cefr,
    required String message,
    required String studyLang,
    List<String> history = const [],
  }) async {
    try {
      final data = await _invoke({
        'task': 'chat',
        'scenario': scenario,
        'message': message,
        'cefr': cefr,
        'study_lang': studyLang,
        'history': history.take(8).toList(),
      });
      final text = (data['text'] ?? data['reply'] ?? '').toString().trim();
      if (text.isNotEmpty) {
        stats.llmHits++;
        return text;
      }
    } catch (_) {
      // fall through to the scripted tutor
    }
    stats.brainHits++;
    return _scriptedReply(scenario: scenario, turn: history.length ~/ 2);
  }

  /// A small hand-written script per scenario. Short, level-appropriate lines
  /// that always end in a question, so the learner always has something to
  /// answer.
  String _scriptedReply({required String scenario, required int turn}) {
    const scripts = <String, List<String>>{
      'Кофеханада': [
        'Hi! Welcome. What would you like to drink today?',
        'Good choice. Would you like it black or with milk?',
        'We also have a delicious cheesecake. Shall I add one?',
        'That will be 1,200 tenge. Are you paying by card?',
        'Thank you! Your order will be ready in five minutes. Anything else?',
      ],
      'Әуежайда': [
        'Good morning. May I see your passport and ticket, please?',
        'Thank you. Do you have any bags to check in?',
        'Your seat is 14A. Would you prefer a window or an aisle seat?',
        'Boarding starts at gate 7 in forty minutes. Do you know the way?',
        'Have a pleasant flight! Is there anything else I can help with?',
      ],
      'Жұмыс сұхбаты': [
        'Thanks for coming. Could you tell me a little about yourself?',
        'Interesting. What would you say is your greatest strength?',
        'Can you describe a difficult problem you solved recently?',
        'Where do you see yourself in three years?',
        'Great. Do you have any questions for me?',
      ],
      'Дүкенде': [
        'Hello! Are you looking for anything in particular?',
        'We have that in three colours. Which one do you prefer?',
        'What size do you need? We have small, medium and large.',
        'It costs 8,500 tenge. Would you like to try it on?',
        'Perfect. Will you pay in cash or by card?',
      ],
      'Дәрігерде': [
        'Good afternoon. What seems to be the problem?',
        'I see. How long have you been feeling like this?',
        'Do you have a fever or a headache as well?',
        'I will write you a prescription. Are you allergic to anything?',
        'Take it twice a day after meals. Do you have any questions?',
      ],
    };
    final lines = scripts[scenario] ?? scripts['Кофеханада']!;
    return lines[turn.clamp(0, lines.length - 1)];
  }

  /// The scene's very first line. Always hand-written and scene-perfect,
  /// unlike an AI-generated opener: with no learner message yet to react to,
  /// a weaker fallback model tends to skip the scene description entirely and
  /// produce generic small talk ("What a lovely day!") regardless of whether
  /// the scene is a coffee shop or a doctor's office. Returning the scripted
  /// line directly also means picking a scenario never waits on the network.
  String openingLine(String scenario) => _scriptedReply(scenario: scenario, turn: 0);

  // ── Catalogue growth ─────────────────────────────────────

  /// Pulls a fresh batch of vocabulary out of the LLM and stores it in the
  /// shared dictionary forever. Server-side throttled to one run per hour
  /// across all clients, so calling it on launch is safe and cheap.
  /// Returns how many words were added (0 when the run was skipped).
  Future<int> growBrain({String? cefr, String? topic, bool force = false}) async {
    try {
      final res = await supa.functions.invoke('sozqor-grow', body: {
        if (cefr != null) 'cefr': cefr,
        if (topic != null) 'topic': topic,
        'force': force,
      });
      final data = res.data;
      if (data is Map) return ((data['added'] ?? 0) as num).toInt();
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Fire-and-forget growth tick, safe to call on every app launch.
  void growInBackground() {
    growBrain().catchError((_) => 0);
  }

  // ── transport ────────────────────────────────────────────
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async =>
      _send(body, allowRetry: true);

  /// [allowRetry] is spent on the one thing worth retrying: a 401.
  ///
  /// The access token is only good for an hour, and it is the client that has
  /// to notice and rotate it. When the app has been sitting in a background
  /// tab the refresh timer gets throttled, so the first lookup after coming
  /// back can go out holding a token the server has already stopped
  /// accepting — the edge function then legitimately answers 401
  /// "Авторизация қажет" even though the learner is perfectly well signed in.
  /// Refreshing and sending once more turns that into a normal answer instead
  /// of an error the learner can only fix by restarting the app.
  Future<Map<String, dynamic>> _send(
    Map<String, dynamic> body, {
    required bool allowRetry,
  }) async {
    try {
      final res = await supa.functions.invoke(
        AppConfig.aiFunction,
        body: {...body, 'lang': AppLang.current},
      );
      final data = res.data;
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        if (map['error'] != null) throw Exception(map['error'].toString());
        return map;
      }
      throw Exception(tr('AI жауап бермеді'));
    } on FunctionException catch (e) {
      if (e.status == 401 && allowRetry) {
        try {
          await supa.auth.refreshSession();
          return _send(body, allowRetry: false);
        } catch (_) {
          // The session is genuinely gone; fall through to the normal
          // message rather than hiding it behind a refresh failure.
        }
      }
      final details = e.details;
      final msg = details is Map && details['error'] != null
          ? details['error'].toString()
          : tr('AI қызметі қолжетімсіз');
      if (e.status == 503) {
        throw Exception(
          tr('AI кілттері әлі бапталмаған. Офлайн сөздік істеп тұр.'));
      }
      if (e.status == 429) {
        throw Exception(
          tr('AI қазір бос емес. Сөзді қолмен жазып сақтай бересің.'));
      }
      if (e.status == 401) {
        throw Exception(
          tr('Сессия жаңартылмады. Қосымшаны қайта ашып көр.'));
      }
      throw Exception(msg);
    } catch (e) {
      throw Exception(humanError(e));
    }
  }
}
