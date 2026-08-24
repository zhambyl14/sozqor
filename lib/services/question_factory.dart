// lib/services/question_factory.dart
//
// Builds playable rounds locally from whatever content is in hand — the
// learner's own words plus a pool drawn from the shared dictionary. Nothing
// here touches the network, so a round starts instantly and works offline.

import 'dart:math';

import '../core/constants/game_meta.dart';
import '../data/models/dict_entry.dart';
import '../data/models/question.dart';
import '../data/models/word.dart';

/// One quizzable unit: a dictionary entry, plus the personal word id when the
/// learner owns it (so spaced repetition can be updated).
class PlayItem {
  final DictEntry entry;
  final String? wordId;
  const PlayItem(this.entry, {this.wordId});

  factory PlayItem.fromWord(Word w) => PlayItem(w.toDictEntry(), wordId: w.id);
  factory PlayItem.fromDict(DictEntry e) => PlayItem(e);
}

class QuestionFactory {
  QuestionFactory._();

  static const int _minOptions = 4;

  /// Builds up to [count] questions. Never throws — if the content cannot
  /// support a kind it silently falls back to translation questions, and if
  /// there is not enough content at all it returns a shorter list.
  static List<Question> build({
    required List<PlayItem> items,
    required List<DictEntry> pool,
    required List<QKind> kinds,
    int count = 10,
    int? seed,
    String nativeLang = 'kk',
    /// Kinds this round must never ask (EN-22 / KK-3).
    ///
    /// Ranked play passes [QKind.listening]: an audio question is unplayable
    /// on a bus or in a lesson, and a rated match is exactly the round nobody
    /// can afford to skip. It is a parameter rather than a mode check because
    /// this factory has no idea which mode called it.
    Set<QKind> exclude = const {},
  }) {
    final rng = Random(seed ?? DateTime.now().microsecondsSinceEpoch);

    final usable = items
        .where((i) => i.entry.en.trim().isNotEmpty && i.entry.kk.trim().isNotEmpty)
        .toList();
    if (usable.isEmpty) return const [];

    // Everything available as a distractor source.
    final allEntries = <DictEntry>[
      ...usable.map((i) => i.entry),
      ...pool,
    ];

    final order = [...usable]..shuffle(rng);
    var allowed = kinds.isEmpty ? [QKind.kkEn, QKind.enKk] : kinds;
    allowed = allowed.where((k) => !exclude.contains(k)).toList();
    // Excluding everything would leave nothing to ask; translation is the one
    // kind every entry supports, so it is the floor.
    if (allowed.isEmpty) allowed = [QKind.kkEn, QKind.enKk];

    final out = <Question>[];
    var cursor = 0;
    var guard = 0;

    // EN-22: the PRD's example is an audio question about a word followed
    // immediately by another question about that same word. Nothing tracked
    // what had just been asked, so with a small pool a round could ask about
    // four words in ten questions and ask two of them back to back.
    //
    // `recentWords` is a sliding window over the answers already used, and
    // `recentKinds` stops a round turning into six spelling questions in a
    // row. Both are relaxed once the pool is genuinely too small to satisfy
    // them, because a shorter round is worse than a repetitive one.
    final recentWords = <String>[];
    final recentKinds = <QKind>[];
    final wordWindow = min(5, max(1, usable.length - 1));

    String keyOf(PlayItem i) =>
        (i.wordId ?? i.entry.en).trim().toLowerCase();

    while (out.length < count && guard < count * 8) {
      guard++;
      if (order.isEmpty) break;
      final item = order[cursor % order.length];
      cursor++;

      // A relaxed pass only kicks in once cycling has clearly failed to find
      // anything fresh, so the window is honoured whenever it can be.
      final relaxed = guard > count * 4;
      if (!relaxed && recentWords.contains(keyOf(item))) continue;

      var supported = allowed.where((k) => _supports(item.entry, k)).toList();
      if (supported.isEmpty) {
        supported = [
          if (!exclude.contains(QKind.kkEn)) QKind.kkEn,
          if (!exclude.contains(QKind.enKk)) QKind.enKk,
        ];
        if (supported.isEmpty) supported = [QKind.kkEn];
      }

      // Prefer a kind that has not just been used twice running.
      final tired = recentKinds.length >= 2 &&
          recentKinds.last == recentKinds[recentKinds.length - 2]
              ? recentKinds.last
              : null;
      final fresh = supported.where((k) => k != tired).toList();
      final pickFrom = fresh.isEmpty ? supported : fresh;
      final kind = pickFrom[rng.nextInt(pickFrom.length)];

      final q = _make(item, kind, allEntries, rng, nativeLang);
      if (q == null) continue;

      out.add(q);
      recentWords.add(keyOf(item));
      if (recentWords.length > wordWindow) recentWords.removeAt(0);
      recentKinds.add(kind);
      if (recentKinds.length > 3) recentKinds.removeAt(0);
    }

    return out;
  }

  // ── capability check ─────────────────────────────────────
  static bool _supports(DictEntry e, QKind k) => switch (k) {
    QKind.kkEn || QKind.enKk || QKind.listening => true,
    QKind.definition => (e.definitionEn ?? '').trim().length > 4,
    QKind.synonym    => e.synonyms.isNotEmpty,
    QKind.antonym    => e.antonyms.isNotEmpty,
    QKind.spelling   => _spellable(e),
    QKind.sentence   => _blankOut(e) != null,
  };

  /// Only single words make a fair spelling round: the keypad hands out
  /// letters with the spaces removed, so a phrase can never be assembled
  /// back into its exact spelling.
  static bool _spellable(DictEntry e) {
    final t = _bare(e.en).trim();
    return !t.contains(' ') && t.length >= 3 && t.length <= 14;
  }

  // ── builders ─────────────────────────────────────────────
  static Question? _make(PlayItem item, QKind kind, List<DictEntry> all,
      Random rng, String lang) {
    final e = item.entry;
    final own = e.native(lang);

    switch (kind) {
      case QKind.kkEn:
        final opts = _options(e.en, all.map((x) => x.en), rng, exclude: {own});
        if (opts.length < _minOptions) return null;
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: own, subPrompt: e.emoji,
          answer: e.en, options: opts,
        );

      case QKind.enKk:
        final opts = _options(
            own, all.map((x) => x.native(lang)), rng, exclude: {e.en});
        if (opts.length < _minOptions) return null;
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: e.en, subPrompt: e.ipa,
          answer: own, options: opts, speakText: _bare(e.en),
        );

      case QKind.definition:
        final def = (e.definitionEn ?? '').trim();
        final others = all
            .where((x) => x.en != e.en && (x.definitionEn ?? '').trim().length > 4)
            .map((x) => x.definitionEn!.trim());
        final opts = _options(def, others, rng);
        if (opts.length < _minOptions) return null;
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: e.en, subPrompt: e.pos,
          answer: def, options: opts, speakText: _bare(e.en),
        );

      case QKind.synonym: {
        final answer = e.synonyms[rng.nextInt(e.synonyms.length)];
        final banned = {
          _norm(e.en), _norm(answer),
          ...e.synonyms.map(_norm), ...e.antonyms.map(_norm),
        };
        final others = all
            .map((x) => _bare(x.en))
            .where((s) => !banned.contains(_norm(s)));
        final opts = _options(answer, others, rng);
        if (opts.length < _minOptions) return null;
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: e.en, subPrompt: e.definitionEn,
          answer: answer, options: opts, speakText: _bare(e.en),
        );
      }

      case QKind.antonym: {
        final answer = e.antonyms[rng.nextInt(e.antonyms.length)];
        final banned = {
          _norm(e.en), _norm(answer),
          ...e.synonyms.map(_norm), ...e.antonyms.map(_norm),
        };
        final others = all
            .map((x) => _bare(x.en))
            .where((s) => !banned.contains(_norm(s)));
        final opts = _options(answer, others, rng);
        if (opts.length < _minOptions) return null;
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: e.en, subPrompt: e.definitionEn,
          answer: answer, options: opts, speakText: _bare(e.en),
        );
      }

      case QKind.listening: {
        final opts = _options(
            own, all.map((x) => x.native(lang)), rng, exclude: {e.en});
        if (opts.length < _minOptions) return null;
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: '🎧', subPrompt: null,
          answer: own, options: opts, speakText: _bare(e.en),
        );
      }

      case QKind.spelling: {
        if (!_spellable(e)) return null;
        final target = _bare(e.en).trim();
        final letters = target.split('')..shuffle(rng);
        // add two decoy letters so it is not a pure anagram give-away
        const extra = 'aeioustrnl';
        while (letters.length < target.length + 2 && letters.length < 16) {
          letters.add(extra[rng.nextInt(extra.length)]);
        }
        letters.shuffle(rng);
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: own, subPrompt: e.definitionEn,
          answer: target, options: const [], letters: letters,
          speakText: target,
        );
      }

      case QKind.sentence: {
        final blanked = _blankOut(e);
        if (blanked == null) return null;
        final answer = _bare(e.en);
        final others = all
            .map((x) => _bare(x.en))
            .where((s) => _norm(s) != _norm(answer));
        final opts = _options(answer, others, rng);
        if (opts.length < _minOptions) return null;
        return Question(
          kind: kind, wordId: item.wordId,
          prompt: blanked, subPrompt: own,
          answer: answer, options: opts,
        );
      }
    }
  }

  // ── helpers ──────────────────────────────────────────────

  static String _norm(String s) => s.trim().toLowerCase();

  /// English entries are stored as "to run"; most game surfaces want "run".
  static String _bare(String en) {
    final t = en.trim();
    return t.toLowerCase().startsWith('to ') ? t.substring(3).trim() : t;
  }

  /// Builds a shuffled option list containing [answer] plus distinct decoys.
  static List<String> _options(
    String answer,
    Iterable<String> candidates,
    Random rng, {
    Set<String> exclude = const {},
    int total = _minOptions,
  }) {
    final seen = <String>{_norm(answer), ...exclude.map(_norm)};
    final pool = <String>[];
    for (final c in candidates) {
      final t = c.trim();
      if (t.isEmpty) continue;
      if (seen.contains(_norm(t))) continue;
      seen.add(_norm(t));
      pool.add(t);
    }
    if (pool.length < total - 1) return const [];

    pool.shuffle(rng);
    final picked = pool.take(total - 1).toList();
    return [answer.trim(), ...picked]..shuffle(rng);
  }

  /// Replaces the target word inside its example sentence with a blank.
  /// Returns null when the example does not actually contain the word.
  static String? _blankOut(DictEntry e) {
    final sentence = (e.exampleEn ?? '').trim();
    if (sentence.length < 12) return null;

    final bare = _bare(e.en);
    if (bare.isEmpty) return null;

    // match the word and simple inflections: run / runs / running / ran-less
    final stem = bare.length > 4 ? bare.substring(0, bare.length - 1) : bare;
    final re = RegExp(r'\b' + RegExp.escape(stem) + r'\w{0,4}\b',
        caseSensitive: false);
    if (!re.hasMatch(sentence)) return null;

    final blanked = sentence.replaceFirst(re, '_____');
    return blanked == sentence ? null : blanked;
  }

  /// Deterministic set so every player at a level gets the same daily round.
  static List<Question> daily({
    required List<DictEntry> pool,
    required List<QKind> kinds,
    required DateTime day,
    required String cefr,
    int count = 12,
    String nativeLang = 'kk',
  }) {
    // `.hashCode` is not guaranteed stable across compiler backends (VM/AOT
    // vs dart2js/dart2wasm), so mobile and web builds could derive different
    // seeds for the same CEFR string. Fold the char codes by hand instead —
    // identical on every backend this app ships.
    var cefrSeed = 0;
    for (final c in cefr.codeUnits) {
      cefrSeed = (cefrSeed * 31 + c) & 0x7fffffff;
    }
    final seed = day.year * 10000 + day.month * 100 + day.day + cefrSeed;
    final ordered = [...pool]..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    return build(
      items: ordered.map(PlayItem.fromDict).toList(),
      pool: ordered,
      kinds: kinds,
      count: count,
      seed: seed,
      nativeLang: nativeLang,
    );
  }
}
