// lib/features/profile/achievements_screen.dart
//
// Twenty-two achievements, split into the three things the app actually
// measures: vocabulary, consistency and competition.
//
// 3.0 listed them as "earned" then "locked", which buried what you were close
// to under everything you had already done. Grouping by theme keeps the next
// realistic target visible, and the header names it outright.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';
import '../../services/achievements.dart';

final _marathonBestProvider = FutureProvider<int>(
    (ref) => ref.watch(boardRepoProvider).myBest('marathon'));

List<({String title, List<String> metrics})> get _groups => [
  (title: tr('Сөз'), metrics: ['words', 'learned']),
  (title: tr('Серия'), metrics: ['streak', 'quizzes', 'xp']),
  (title: tr('Арена'), metrics: ['battles_won', 'elo', 'marathon']),
];

IconData _iconFor(Achievement a) => switch (a.code) {
  'first_word'  => PhosphorIconsFill.seal,
  'words_10'    => PhosphorIconsFill.books,
  'words_50'    => PhosphorIconsFill.bookBookmark,
  'words_200'   => PhosphorIconsFill.bank,
  'words_500'   => PhosphorIconsFill.crownSimple,
  'learned_10'  => PhosphorIconsFill.checkCircle,
  'learned_100' => PhosphorIconsFill.graduationCap,
  'streak_3'    => PhosphorIconsFill.fire,
  'streak_7'    => PhosphorIconsFill.flame,
  'streak_30'   => PhosphorIconsFill.shield,
  'streak_100'  => PhosphorIconsFill.diamond,
  'quiz_10'     => PhosphorIconsFill.gameController,
  'quiz_100'    => PhosphorIconsFill.heartbeat,
  'battle_1'    => PhosphorIconsFill.sword,
  'battle_10'   => PhosphorIconsFill.medal,
  'battle_50'   => PhosphorIconsFill.trophy,
  'elo_1200'    => PhosphorIconsFill.chartLineUp,
  'elo_1500'    => PhosphorIconsFill.rocketLaunch,
  'xp_1000'     => PhosphorIconsFill.star,
  'xp_10000'    => PhosphorIconsFill.sparkle,
  'marathon_20' => PhosphorIconsFill.barbell,
  'marathon_50' => PhosphorIconsFill.mountains,
  _             => PhosphorIconsFill.sealCheck,
};

class AchievementsScreen extends ConsumerWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final unlocked =
        ref.watch(unlockedAchievementsProvider).value ?? const <String>{};
    final profile = ref.watch(myProfileProvider).value;
    final marathonBest = ref.watch(_marathonBestProvider).value ?? 0;

    final progress = profile == null
        ? <String, int>{}
        : AchievementService.instance.progressFor(profile, marathonBest);

    final earned = kAchievements.where((a) => unlocked.contains(a.code)).length;
    final ratio = kAchievements.isEmpty ? 0.0 : earned / kAchievements.length;

    // The closest unearned achievement — the one worth naming in the header.
    Achievement? next;
    var bestGap = double.infinity;
    for (final a in kAchievements) {
      if (unlocked.contains(a.code) || a.target == 0) continue;
      final have = (progress[a.code] ?? 0).clamp(0, a.target);
      final gap = (a.target - have) / a.target;
      if (gap < bestGap) { bestGap = gap; next = a; }
    }
    final nextLeft = next == null
        ? 0
        : (next.target - (progress[next.code] ?? 0)).clamp(0, next.target);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(unlockedAchievementsProvider);
        ref.invalidate(_marathonBestProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Жетістіктер'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        SqInkCard(
          padding: const EdgeInsets.all(17),
          glow: AppColors.amber,
          child: Row(
            children: [
              SqRing(
                value: ratio,
                size: 64,
                stroke: 7,
                color: AppColors.amber,
                track: AppColors.inkTrack,
                child: SqNum('${(ratio * 100).round()}%',
                  size: 14, color: Colors.white),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(trp('{p1} / {p2} ашылды', {'p1': '$earned', 'p2': '${kAchievements.length}'}),
                      style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800,
                        color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      next == null
                          ? tr('Барлығы ашылды — керемет жұмыс!')
                          : trp('Келесі: «{p1}» — {p2} қалды', {'p1': tr(next.title), 'p2': '$nextLeft'}),
                      style: const TextStyle(
                        fontSize: 11.5, height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onInk2)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        for (final g in _groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: SqEyebrow(g.title)),
          _Grid(
            items: kAchievements
                .where((a) => g.metrics.contains(a.metric))
                .toList(),
            unlocked: unlocked,
            progress: progress),
          const SizedBox(height: 20),
        ],

        Text(
          tr('Жетістік ашылғанда XP өзі қосылады.'),
          style: TextStyle(
            fontSize: 11, height: 1.5, fontWeight: FontWeight.w600,
            color: AppColors.text4(d))),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  final List<Achievement> items;
  final Set<String> unlocked;
  final Map<String, int> progress;

  const _Grid({
    required this.items, required this.unlocked, required this.progress});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _Badge(
            achievement: items[i],
            unlocked: unlocked.contains(items[i].code),
            current: progress[items[i].code] ?? 0)),
          const SizedBox(width: 9),
          if (i + 1 < items.length)
            Expanded(child: _Badge(
              achievement: items[i + 1],
              unlocked: unlocked.contains(items[i + 1].code),
              current: progress[items[i + 1].code] ?? 0))
          else
            const Expanded(child: SizedBox.shrink()),
        ],
      ));
      if (i + 2 < items.length) rows.add(const SizedBox(height: 9));
    }
    return Column(children: rows);
  }
}

class _Badge extends StatelessWidget {
  final Achievement achievement;
  final bool unlocked;
  final int current;

  const _Badge({
    required this.achievement, required this.unlocked, required this.current});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final a = achievement;
    final ratio = a.target == 0 ? 0.0 : (current / a.target).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: unlocked ? AppColors.card(d) : AppColors.muted(d),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: unlocked ? AppColors.border(d) : AppColors.border(d),
          style: unlocked ? BorderStyle.solid : BorderStyle.solid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SqTintBox(_iconFor(a),
                tint: unlocked ? AppColors.primary : AppColors.text4(d),
                size: 36),
              const Spacer(),
              if (unlocked)
                const Icon(PhosphorIconsFill.sealCheck,
                  size: 17, color: AppColors.amber),
            ],
          ),
          const SizedBox(height: 9),
          Text(tr(a.title),
            style: TextStyle(
              fontSize: 12.5, height: 1.3, fontWeight: FontWeight.w800,
              color: unlocked ? AppColors.text(d) : AppColors.text4(d))),
          const SizedBox(height: 8),
          SqTrack(unlocked ? 1 : ratio,
            height: 5,
            color: unlocked ? AppColors.amber : AppColors.primary),
          const SizedBox(height: 6),
          Text(
            unlocked
                ? '+${a.xp} XP'
                : '${current.clamp(0, a.target)} / ${a.target}',
            style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800,
              color: unlocked ? AppColors.amberInk : AppColors.text4(d))),
        ],
      ),
    );
  }
}
