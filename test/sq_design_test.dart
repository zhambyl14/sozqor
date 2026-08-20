// test/sq_design_test.dart
//
// Guards for the 4.0 kit and the pure logic behind the new meta-game.
//
// The layout tests pump components at 320×568 — the smallest phone the app
// realistically runs on — with text scaled to the 1.2 ceiling the app clamps
// to. A RenderFlex overflow throws in a test binding, so "it rendered" is the
// assertion: these catch the class of bug that only shows up on a small
// device, which is exactly the one nobody has on their desk.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sozqor/core/constants/game_meta.dart';
import 'package:sozqor/core/theme/app_colors.dart';
import 'package:sozqor/core/theme/app_theme.dart';
import 'package:sozqor/core/widgets/spelling_pad.dart';
import 'package:sozqor/core/widgets/sq.dart';
import 'package:sozqor/data/models/question.dart';
import 'package:sozqor/features/play/pronounce_screen.dart';
import 'package:sozqor/services/meta_store.dart';

const _small = Size(320, 568);

Widget _host(Widget child, {bool dark = false}) => MediaQuery(
  data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
  child: MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(
      backgroundColor: AppColors.bg(dark),
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(18), child: child)),
    ),
  ),
);

Future<void> _pumpSmall(WidgetTester tester, Widget child,
    {bool dark = false}) async {
  tester.view.physicalSize = _small;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(child, dark: dark));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('4.0 kit survives a 320pt phone', () {
    testWidgets('the primary action and its tones', (tester) async {
      await _pumpSmall(tester, const Column(children: [
        SqAction('Жалғастыру', tone: SqTone.primary),
        SizedBox(height: 10),
        SqAction('Нәтижені көру', tone: SqTone.ink),
        SizedBox(height: 10),
        SqAction('Қарсылас табу', tone: SqTone.danger),
        SizedBox(height: 10),
        SqAction('Тағы ойнау', tone: SqTone.ghost),
      ]));
      expect(find.text('Жалғастыру'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a four-answer question block', (tester) async {
      await _pumpSmall(tester, const Column(children: [
        SqAnswer(text: 'reliable', badge: 'A'),
        SizedBox(height: 10),
        SqAnswer(text: 'remarkable', badge: 'B',
          revealed: true, isCorrect: true),
        SizedBox(height: 10),
        SqAnswer(text: 'reluctant', badge: 'C',
          revealed: true, isPicked: true),
      ]));
      expect(find.text('reliable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a grouped list row with every slot filled', (tester) async {
      await _pumpSmall(tester, const SqGroup(children: [
        SqTile(
          leading: SqTintBox(Icons.star, size: 34),
          title: 'Күнделікті мақсат бойынша қайталау',
          subtitle: 'Ұмытуға жақын 18 сөз бүгін кезекте',
          below: SqTrack(0.6),
          trailing: SqBadge('+40 XP', tint: AppColors.amber),
          chevron: true),
        SqTile(title: 'Екінші жол', subtitle: 'Қысқа'),
      ]));
      expect(find.text('Екінші жол'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the ink focus block with a ring and beads', (tester) async {
      await _pumpSmall(tester, const SqInkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: SqEyebrow('Бүгінгі жоспар')),
              SqRing(value: 0.8, size: 58,
                child: SqNum('80%', size: 13, color: Colors.white)),
            ]),
            SizedBox(height: 14),
            SqBeads(total: 10, done: 8, current: 8),
            SizedBox(height: 14),
            Row(children: [
              Expanded(child: SqInkStat('8/10', 'дәлдік 80%')),
              SizedBox(width: 9),
              Expanded(child: SqInkStat('×5', 'ең үлкен комбо')),
              SizedBox(width: 9),
              Expanded(child: SqInkStat('2:41', 'уақыт')),
            ]),
          ],
        ),
      ));
      expect(find.text('80%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the spelling pad on the dark battle field', (tester) async {
      const question = Question(
        kind: QKind.spelling,
        prompt: 'сенімді',
        answer: 'reliable',
        letters: ['r', 'e', 'l', 'i', 'a', 'b', 'l', 'e', 'o', 'n'],
      );
      await _pumpSmall(tester, SpellingPad(
        question: question,
        chosen: const [0, 1],
        revealed: false,
        dense: true,
        onInk: true,
        onPick: (_) {},
        onUndo: () {},
        onSubmit: () {},
      ));
      expect(find.text('Тексеру'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the kit renders in dark mode too', (tester) async {
      await _pumpSmall(tester, const Column(children: [
        SqPanel(child: SqStat(
          icon: Icons.book, tint: AppColors.primary,
          value: '248', label: 'сөз')),
        SizedBox(height: 10),
        SqSegmented(items: ['Апта', 'Бүгін', 'Достар'],
          index: 0, onChanged: _noop),
        SizedBox(height: 10),
        SqEmpty(icon: Icons.search, title: 'Ештеңе табылмады',
          subtitle: 'Сүзгіні өзгертіп көр'),
      ]), dark: true);
      expect(find.text('248'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('syllablesOf', () {
    test('splits common words the way a learner would say them', () {
      expect(syllablesOf('reliable').length, greaterThan(2));
      expect(syllablesOf('computer').length, greaterThan(1));
      expect(syllablesOf('cat'), ['cat']);
      expect(syllablesOf(''), ['—']);
    });

    test('never returns a one-letter fragment', () {
      for (final w in ['beautiful', 'organisation', 'apple', 'idea']) {
        for (final s in syllablesOf(w)) {
          expect(s.length, greaterThan(1), reason: '"$w" produced "$s"');
        }
      }
    });

    test('keeps the whole word between the pieces', () {
      for (final w in ['reliable', 'computer', 'travel']) {
        expect(syllablesOf(w).join(), w);
      }
    });
  });

  group('MetaState', () {
    test('a fresh install has a chest waiting', () {
      expect(const MetaState().chestReady, isTrue);
      expect(const MetaState().nextChestStreak, 1);
    });

    test('opening today closes the chest until tomorrow', () {
      final state = MetaState(chestDay: MetaState.today(), chestStreak: 3);
      expect(state.chestReady, isFalse);
    });

    test('a gap in the run restarts the chest streak', () {
      const stale = MetaState(chestDay: '2020-01-01', chestStreak: 9);
      expect(stale.chestReady, isTrue);
      expect(stale.nextChestStreak, 1, reason: 'a missed day resets the run');
    });

    test('yesterday continues the run', () {
      final yesterday = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      final state = MetaState(chestDay: yesterday, chestStreak: 4);
      expect(state.nextChestStreak, 5);
    });

    test('round-trips through JSON', () {
      const before = MetaState(
        chestDay: '2026-08-17', chestStreak: 6, freezes: 2, lives: 1,
        passClaimed: {1, 2, 5}, passPremium: true,
        owned: {'frame_gold'}, frame: 'frame_gold',
        packs: {'ielts': 12}, storyNode: 7, spent: 900);
      final after = MetaState.fromJson(before.toJson());
      expect(after.chestStreak, 6);
      expect(after.passClaimed, {1, 2, 5});
      expect(after.owned, {'frame_gold'});
      expect(after.packs['ielts'], 12);
      expect(after.storyNode, 7);
      expect(after.spent, 900);
    });

    test('bad stored JSON never crashes the reader', () {
      expect(MetaState.fromJson(const {}).chestStreak, 0);
      expect(MetaState.fromJson(const {'freezes': 3}).freezes, 3);
    });
  });

  group('mission path', () {
    test('level tracks lifetime XP and stops at the last reward', () {
      expect(passLevelFor(0), 0);
      expect(passLevelFor(399), 0);
      expect(passLevelFor(400), 1);
      expect(passLevelFor(2000), 5);
      expect(passLevelFor(999999), kPassRewards.last.level);
    });

    test('progress and remaining XP agree with each other', () {
      for (final xp in [0, 137, 400, 1201, 7777]) {
        expect(passProgressFor(xp), inInclusiveRange(0.0, 1.0));
        // Once the last reward level is reached (xp >= 4800) there is no next
        // level to progress toward, so remaining XP reads as exactly 0 instead
        // of a phantom countdown toward a level that will never pay out.
        final maxed = passLevelFor(xp) >= kPassRewards.last.level;
        expect(passXpToNext(xp), maxed ? equals(0) : inInclusiveRange(1, 400));
      }
    });

    test('every reward level is unique and ordered', () {
      final levels = kPassRewards.map((r) => r.level).toList();
      expect(levels, equals(List<int>.from(levels)..sort()));
      expect(levels.toSet().length, levels.length);
    });
  });

  group('word packs', () {
    test('every pack resolves and targets real topics and levels', () {
      for (final p in kWordPacks) {
        expect(packOf(p.id), isNotNull);
        expect(kTopics.any((t) => t.key == p.topic), isTrue,
            reason: '${p.id} points at an unknown topic "${p.topic}"');
        for (final level in p.levels) {
          expect(kCefrCodes.contains(level), isTrue,
              reason: '${p.id} points at an unknown level "$level"');
        }
        expect(p.size, greaterThan(0));
      }
    });

    test('shop items are uniquely identified', () {
      final ids = kShopItems.map((i) => i.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final i in kShopItems) {
        expect(shopItemOf(i.id), isNotNull);
        expect(i.price, greaterThan(0));
      }
    });
  });
}

void _noop(int _) {}
