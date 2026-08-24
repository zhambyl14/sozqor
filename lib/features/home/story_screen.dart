// lib/features/home/story_screen.dart
//
// The Word Path (EN-11 / KK-1).
//
// 4.0 drew a zig-zag of forty nodes across five "zones" and every one of them
// launched `PlayMode.classic` filtered by topic. It looked like a journey and
// behaved like a quiz with extra steps — the single clearest example of the
// complaint the PRD makes about the whole app, that everything is question →
// answer → score.
//
// It is a story now. Five chapters, four scenes each, with people in them; the
// vocabulary is what moves the story rather than what is being marked. This
// screen is the shelf you pick a chapter off, so it stays deliberately quiet:
// where you are, what is next, and one button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';
import 'story_chapter_screen.dart';
import 'story_content.dart';

class StoryScreen extends ConsumerWidget {
  const StoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    // How many scenes have been cleared. Chapters are cleared whole, so this
    // always lands on a chapter boundary.
    final done = ref.watch(metaProvider).storyNode;
    final current = _currentChapter(done);
    final allDone = done >= kStoryLength;

    Future<void> play(int chapter) async {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StoryChapterScreen(chapter: chapter)));
      if (context.mounted) refreshAll(ref);
    }

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Сөз жолы'),
          eyebrow: tr('Әңгіме'),
          onBack: () => Navigator.of(context).pop(),
          actions: [
            SqBadge('${_chaptersDone(done)} / ${kStory.length}',
              tint: AppColors.primary, numeric: true),
          ],
        ),
        const SizedBox(height: 16),

        // Where you are, and the one button. Everything else on this page is
        // a list of places you have already been.
        SqRise(
          child: SqInkCard(
            padding: const EdgeInsets.all(20),
            glow: allDone ? AppColors.green : AppColors.primary,
            glowAt: Alignment.topRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SqEyebrow(
                  allDone ? tr('Әңгіме аяқталды') : tr('Келесі тарау'),
                  color: AppColors.onInk2),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        color: allDone ? AppColors.green : AppColors.primary,
                        borderRadius: BorderRadius.circular(17)),
                      child: Icon(kStory[current].icon,
                        size: 25, color: Colors.white),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            byLang(
                              kk: kStory[current].titleKk,
                              ru: kStory[current].titleRu),
                            style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w800,
                              letterSpacing: -0.4, color: Colors.white)),
                          Text(
                            byLang(
                              kk: kStory[current].placeKk,
                              ru: kStory[current].placeRu),
                            style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w600,
                              color: AppColors.onInk3)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SqAction(
                  allDone ? tr('Қайта оқу') : tr('Оқуды бастау'),
                  icon: PhosphorIconsFill.bookOpenText,
                  onTap: () => play(current)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        SqSection(tr('Тараулар')),
        SqGroup(children: [
          for (var i = 0; i < kStory.length; i++)
            _ChapterRow(
              chapter: kStory[i],
              index: i,
              // A chapter opens once the one before it is finished. Reading
              // chapter four before chapter one is not a story.
              unlocked: i <= _chaptersDone(done),
              finished: i < _chaptersDone(done),
              onTap: () => play(i)),
        ]),
        const SizedBox(height: 14),

        Text(
          byLang(
            kk: 'Әр тарауда таңдаған сөзің — кейіпкердің айтқаны. Қате '
                'айтсаң, әңгіме тоқтамайды: түзетіп, әрі қарай жүреді.',
            ru: 'В каждой главе выбранное тобой слово — это то, что говорит '
                'героиня. Ошибёшься — история не остановится: поправит и '
                'пойдёт дальше.'),
          style: TextStyle(
            fontSize: 12, height: 1.55, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
      ],
    );
  }

  static int _chaptersDone(int scenes) {
    var n = 0, count = 0;
    for (final c in kStory) {
      n += c.scenes.length;
      if (scenes >= n) count++;
    }
    return count;
  }

  static int _currentChapter(int scenes) =>
      _chaptersDone(scenes).clamp(0, kStory.length - 1);
}

class _ChapterRow extends StatelessWidget {
  final StoryChapter chapter;
  final int index;
  final bool unlocked, finished;
  final VoidCallback onTap;

  const _ChapterRow({
    required this.chapter,
    required this.index,
    required this.unlocked,
    required this.finished,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = finished
        ? AppColors.green
        : unlocked ? AppColors.primary : AppColors.text4(d);

    return SqTile(
      leading: SqTintBox(
        finished
            ? PhosphorIconsFill.checkCircle
            : unlocked ? chapter.icon : PhosphorIconsFill.lock,
        tint: tint, size: 36),
      title: byLang(kk: chapter.titleKk, ru: chapter.titleRu),
      titleColor: unlocked ? AppColors.text(d) : AppColors.text3(d),
      subtitle: finished
          ? tr('Оқылды')
          : unlocked
              ? trp('{n} көрініс', {'n': '${chapter.scenes.length}'})
              // A padlock alone says "no". Saying which chapter opens it says
              // "not yet, and here is how".
              : trp('{n}-тарауды бітір', {'n': '$index'}),
      trailing: unlocked
          ? Icon(PhosphorIconsBold.caretRight,
              size: 15, color: AppColors.text3(d))
          : null,
      onTap: unlocked ? onTap : null,
    );
  }
}
