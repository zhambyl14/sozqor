// test/question_factory_test.dart
//
// A question a learner cannot get right is worse than no question at all, and
// it is invisible from the code: every path here builds a list of four
// strings and one of them is nominally the answer. What this file asserts is
// the thing the types cannot — that EXACTLY one of those four is right.
//
// The three shapes that broke it, all of which the pool below contains:
//
//   * "to run" offered next to "run", which are the same word written two
//     ways. isCorrect compares strings, so one of them is marked wrong.
//   * a synonym of the answer offered as a distractor — "lighthouse" against
//     "beacon" — where both options are correct and the learner is told they
//     are not.
//   * a Russian-speaking learner shown a Kazakh option, because native()
//     falls back to Kazakh without saying so when a row has no Russian.

import 'package:flutter_test/flutter_test.dart';

import 'package:sozqor/core/constants/game_meta.dart';
import 'package:sozqor/data/models/dict_entry.dart';
import 'package:sozqor/services/question_factory.dart';

DictEntry _e(
  String en,
  String kk, {
  String? ru,
  List<String> synonyms = const [],
  String? definition,
  String? example,
}) =>
    DictEntry(
      en: en,
      kk: kk,
      ru: ru,
      synonyms: synonyms,
      definitionEn: definition ?? 'A short definition of $en.',
      exampleEn: example ?? 'This sentence uses $en once.',
      cefr: 'A2',
    );

/// Deliberately full of traps.
final _pool = <DictEntry>[
  _e('beacon', 'шамшырақ', ru: 'маяк', synonyms: ['lighthouse', 'signal']),
  _e('lighthouse', 'шамшырақ мұнарасы', ru: 'маяк-башня'),
  _e('to run', 'жүгіру', ru: 'бежать'),
  _e('run', 'жүгіріс', ru: 'пробежка'),
  _e('book', 'кітап', ru: 'книга'),
  _e('book.', 'кітапша', ru: 'книжка'),
  _e('post office', 'пошта', ru: 'почта'),
  _e('post-office', 'пошта бөлімі', ru: 'почтовое отделение'),
  _e('teacher', 'мұғалім', ru: 'учитель'),
  _e('library', 'кітапхана', ru: 'библиотека'),
  _e('cheese', 'ірімшік', ru: 'сыр'),
  _e('table', 'үстел', ru: 'стол'),
  _e('window', 'терезе', ru: 'терезе-ru'),
  _e('door', 'есік', ru: 'дверь'),
  // No Russian at all: unusable for a Russian-speaking learner, and the
  // factory has to leave it out rather than substitute the Kazakh.
  _e('шаңырақ-only', 'шаңырақ'),
];

String _key(String s) {
  var t = s.trim().toLowerCase();
  if (t.startsWith('to ')) t = t.substring(3);
  return t.replaceAll(RegExp(r'[^a-zЀ-ӿ0-9]'), '');
}

void main() {
  final items = _pool.map(PlayItem.fromDict).toList();

  for (final lang in const ['kk', 'ru']) {
    test('every $lang question has exactly one right answer', () {
      // Many seeds, because the trap is a particular pairing and a single
      // shuffle may simply not produce it.
      for (var seed = 0; seed < 200; seed++) {
        final qs = QuestionFactory.build(
          items: items,
          pool: _pool,
          kinds: QKind.values,
          count: 10,
          seed: seed,
          nativeLang: lang,
        );

        for (final q in qs) {
          if (q.kind == QKind.spelling) {
            expect(q.letters, isNotEmpty,
                reason: 'spelling round with no letters, seed $seed');
            expect(q.spellTarget, isNotEmpty, reason: 'seed $seed');
            continue;
          }

          expect(q.options.length, greaterThanOrEqualTo(4),
              reason: '${q.kind} had ${q.options.length} options, seed $seed');

          expect(q.options.any((o) => o.trim().isEmpty), isFalse,
              reason: '${q.kind} had a blank option, seed $seed');

          final correct = q.options.where(q.isCorrect).length;
          expect(correct, 1,
              reason: '${q.kind} "${q.prompt}" had $correct correct options '
                  'among ${q.options}, seed $seed');

          final keys = q.options.map(_key).toSet();
          expect(keys.length, q.options.length,
              reason: '${q.kind} repeated an option in ${q.options}, '
                  'seed $seed');
        }
      }
    });
  }

  test('a Russian learner is never shown a Kazakh-only word', () {
    final noRu = _pool.where((e) => (e.ru ?? '').trim().isEmpty).toList();
    expect(noRu, isNotEmpty, reason: 'the fixture must contain the trap');

    final kkOnly = noRu.map((e) => e.kk).toSet();
    for (var seed = 0; seed < 200; seed++) {
      final qs = QuestionFactory.build(
        items: items,
        pool: _pool,
        kinds: QKind.values,
        count: 10,
        seed: seed,
        nativeLang: 'ru',
      );
      for (final q in qs) {
        for (final o in [...q.options, q.prompt, q.answer]) {
          expect(kkOnly.contains(o.trim()), isFalse,
              reason: 'Kazakh "$o" reached a Russian round, seed $seed');
        }
      }
    }
  });

  test('a synonym of the answer is never offered as a distractor', () {
    final beacon = _pool.firstWhere((e) => e.en == 'beacon');
    for (var seed = 0; seed < 200; seed++) {
      final qs = QuestionFactory.build(
        items: items,
        pool: _pool,
        kinds: [QKind.kkEn],
        count: 10,
        seed: seed,
        nativeLang: 'kk',
      );
      for (final q in qs.where((q) => q.answer == beacon.en)) {
        for (final syn in beacon.synonyms) {
          expect(q.options.map(_key).contains(_key(syn)), isFalse,
              reason: 'synonym "$syn" offered against "${q.answer}", '
                  'seed $seed');
        }
      }
    }
  });
}
