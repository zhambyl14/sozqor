import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sozqor/core/constants/game_meta.dart';
import 'package:sozqor/core/theme/app_colors.dart';
import 'package:sozqor/core/theme/app_theme.dart';
import 'package:sozqor/core/widgets/spelling_pad.dart';
import 'package:sozqor/data/models/dict_entry.dart';
import 'package:sozqor/data/models/question.dart';
import 'package:sozqor/services/question_factory.dart';

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    backgroundColor: AppColors.bgL,
    body: SingleChildScrollView(child: child),
  ),
);

void main() {
  group('SpellingPad', () {
    const question = Question(
      kind: QKind.spelling,
      prompt: 'дәлел',
      answer: 'proof',
      letters: ['p', 'r', 'o', 'o', 'f', 'a', 'e'],
    );

    testWidgets('draws every letter and both controls', (tester) async {
      await tester.pumpWidget(_host(SpellingPad(
        question: question,
        chosen: const [],
        revealed: false,
        onPick: (_) {},
        onUndo: () {},
        onSubmit: () {},
      )));
      await tester.pump();

      // Seven letters, uppercased on the tiles.
      for (final letter in ['P', 'R', 'F', 'A', 'E']) {
        expect(find.text(letter), findsWidgets, reason: 'letter $letter missing');
      }
      // 4.0 keeps the submit button labelled and shrinks undo to an icon, so
      // the two never compete for the same width on a narrow phone.
      expect(find.text('Тексеру'), findsOneWidget);
      expect(find.byIcon(Icons.backspace_rounded), findsOneWidget);
    });

    testWidgets('reports the tapped letter', (tester) async {
      int? picked;
      await tester.pumpWidget(_host(SpellingPad(
        question: question,
        chosen: const [],
        revealed: false,
        onPick: (i) => picked = i,
        onUndo: () {},
        onSubmit: () {},
      )));
      await tester.pump();

      await tester.tap(find.text('R').first);
      expect(picked, 1);
    });
  });

  group('Question', () {
    test('spelling ignores spaces when grading', () {
      const q = Question(
        kind: QKind.spelling, prompt: 'пошта бөлімі',
        answer: 'post office');
      expect(q.spellTarget, 'postoffice');
      expect(q.isCorrect('postoffice'), isTrue);
      expect(q.isCorrect('post office'), isTrue);
      expect(q.isCorrect('postofice'), isFalse);
    });

    test('other kinds stay strict', () {
      const q = Question(kind: QKind.kkEn, prompt: 'су', answer: 'water');
      expect(q.isCorrect('water'), isTrue);
      expect(q.isCorrect('wa ter'), isFalse);
    });
  });

  group('QuestionFactory', () {
    List<DictEntry> pool() => [
      const DictEntry(en: 'water', kk: 'су', cefr: 'A1'),
      const DictEntry(en: 'bread', kk: 'нан', cefr: 'A1'),
      const DictEntry(en: 'house', kk: 'үй', cefr: 'A1'),
      const DictEntry(en: 'apple', kk: 'алма', cefr: 'A1'),
      const DictEntry(en: 'post office', kk: 'пошта бөлімі', cefr: 'A2'),
      const DictEntry(en: 'to run', kk: 'жүгіру', cefr: 'A2'),
    ];

    test('every question can actually be answered', () {
      final questions = QuestionFactory.build(
        items: pool().map(PlayItem.fromDict).toList(),
        pool: pool(),
        kinds: QKind.values,
        count: 30,
        seed: 7,
      );
      expect(questions, isNotEmpty);
      for (final q in questions) {
        expect(q.options.isNotEmpty || q.letters.isNotEmpty, isTrue,
            reason: '${q.kind} has neither options nor letters');
      }
    });

    test('spelling rounds are single words that the letters can build', () {
      final questions = QuestionFactory.build(
        items: pool().map(PlayItem.fromDict).toList(),
        pool: pool(),
        kinds: const [QKind.spelling],
        count: 30,
        seed: 3,
      );
      final spelling = questions.where((q) => q.kind == QKind.spelling);
      expect(spelling, isNotEmpty);
      for (final q in spelling) {
        expect(q.answer.contains(' '), isFalse,
            reason: '"${q.answer}" cannot be spelled out of loose letters');
        final available = [...q.letters];
        for (final ch in q.spellTarget.split('')) {
          expect(available.remove(ch), isTrue,
              reason: 'missing "$ch" for "${q.answer}"');
        }
      }
    });
  });
}
