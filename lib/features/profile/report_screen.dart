// lib/features/profile/report_screen.dart
//
// The weekly report.
//
// A streak counter tells you that you showed up; it does not tell you whether
// it worked. This screen answers that: XP per day for the last seven days,
// accuracy broken down by topic, and one concrete suggestion built from the
// weakest topic — the only place in the app that tells the learner what to do
// next based on their own history.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/repos/profile_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../play/play_session_screen.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  static List<String> get _months => [
    tr('қаңтар'), tr('ақпан'), tr('наурыз'), tr('сәуір'), tr('мамыр'), tr('маусым'),
    tr('шілде'), tr('тамыз'), tr('қыркүйек'), tr('қазан'), tr('қараша'), tr('желтоқсан'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(weekStatsProvider);
    final topics = ref.watch(topicAccuracyProvider);
    final strongest = topics.take(5).toList();
    final profile = ref.watch(myProfileProvider).valueOrNull;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(weekStatsProvider);
        ref.invalidate(myWordsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Апталық есеп'),
          eyebrow: _range(),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        async.when(
          loading: () => const Column(children: [
            SqShimmer(height: 200), SqShimmer(height: 150)]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Есеп жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red),
          data: (week) {
            final total = week.fold(0, (a, s) => a + s.xp);
            final best = week.isEmpty
                ? 1
                : week.map((s) => s.xp).reduce((a, b) => a > b ? a : b)
                    .clamp(1, 1 << 30);
            final active = week.where((s) => s.xp > 0).length;
            final reviewed = week.fold(0, (a, s) => a + s.reviewed);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SqPanel(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SqCountUp(total,
                                size: 32, color: AppColors.text(d)),
                              const SizedBox(height: 2),
                              Text(tr('апталық XP'),
                                style: TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.w700,
                                  color: AppColors.text3(d))),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.soft(
                                active >= 4 ? AppColors.green : AppColors.amber,
                                d),
                              borderRadius: BorderRadius.circular(999)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  active >= 4
                                      ? PhosphorIconsFill.trendUp
                                      : PhosphorIconsFill.trendDown,
                                  size: 14,
                                  color: active >= 4
                                      ? AppColors.greenDeep : AppColors.amber),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    trp('{p1} / 7 күн белсенді',
                                        {'p1': '$active'}),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.onSoft(
                                        active >= 4
                                            ? AppColors.green : AppColors.amber,
                                        d))),
                                ),
                              ],
                            ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 130,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < week.length; i++) ...[
                              Expanded(child: _Bar(
                                stat: week[i], best: best)),
                              if (i != week.length - 1)
                                const SizedBox(width: 7),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                SqEqualRow(
                  children: [
                    Expanded(child: SqStat(
                      icon: PhosphorIconsFill.arrowsClockwise,
                      tint: AppColors.primary,
                      value: '$reviewed', label: tr('сөз қайталанды'))),
                    const SizedBox(width: 9),
                    Expanded(child: SqStat(
                      icon: PhosphorIconsFill.fire, tint: AppColors.amber,
                      value: '${profile?.streak ?? 0}', label: tr('күндік серия'))),
                  ],
                ),
                const SizedBox(height: 14),

                if (topics.isNotEmpty) ...[
                  SqPanel(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SqEyebrow(tr('Тақырып бойынша дәлдік')),
                        const SizedBox(height: 14),
                        // The provider now returns every scored topic
                        // (strongest first) so `topics.last` below can be the
                        // true weakest — the bar chart itself only ever
                        // needs to highlight the top few.
                        for (var i = 0; i < strongest.length; i++) ...[
                          Row(
                            children: [
                              SizedBox(
                                width: 82,
                                child: Text(topicOf(strongest[i].topic).label,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.text(d))),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: SqTrack(strongest[i].ratio,
                                  height: 9,
                                  color: strongest[i].percent >= 70
                                      ? AppColors.green
                                      : strongest[i].percent >= 45
                                          ? AppColors.amber : AppColors.red),
                              ),
                              const SizedBox(width: 11),
                              SizedBox(
                                width: 36,
                                child: SqNum('${strongest[i].percent}%',
                                  size: 11.5, color: AppColors.text2(d)),
                              ),
                            ],
                          ),
                          if (i != strongest.length - 1) const SizedBox(height: 11),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  SqPanel(
                    radius: 20,
                    padding: const EdgeInsets.all(16),
                    fill: AppColors.soft(AppColors.amber, d),
                    border: AppColors.line(AppColors.amber, d),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(PhosphorIconsFill.lightbulb,
                          size: 22, color: AppColors.amber),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_advice(topics.last),
                            style: TextStyle(
                              fontSize: 12.5, height: 1.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSoft(AppColors.amber, d))),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SqAction(
                    trp('{p1} тақырыбын жаттығу', {'p1': topicOf(topics.last.topic).label}),
                    icon: PhosphorIconsFill.target,
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlaySessionScreen(
                          mode: PlayMode.classic,
                          topic: topics.last.topic,
                          title: topicOf(topics.last.topic).label)));
                      if (context.mounted) refreshAll(ref);
                    }),
                ] else
                  SqPanel(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const SqTintBox(PhosphorIconsFill.chartLineUp,
                          tint: AppColors.green, size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('Тақырып талдауы бірнеше раундтан кейін шығады.'),
                            style: TextStyle(
                              fontSize: 12.5, height: 1.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.text3(d))),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 14),
                SqAction(tr('Есепті бөлісу'),
                  icon: PhosphorIconsFill.shareNetwork,
                  tone: SqTone.ink,
                  height: 52,
                  onTap: () => Share.share(
                    trp('SozQor-дағы апталық есебім: {xp} XP, '
                        '{words} сөз қайталадым, {days} күн белсендімін.', {
                      'xp': '$total',
                      'words': '$reviewed',
                      'days': '$active',
                    }))),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _advice(TopicScore weakest) {
    final label = topicOf(weakest.topic).label;
    if (weakest.percent >= 70) {
      return trp('«{p1}» — {p2}%. Жаңа тақырып ашып көр.', {'p1': label, 'p2': '${weakest.percent}'});
    }
    return trp('«{p1}» — {p2}%. Осы тақырыптан 20 сөз жаттық.', {'p1': label, 'p2': '${weakest.percent}'});
  }

  static String _range() {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 6));
    if (from.month == now.month) {
      return '${from.day}–${now.day} ${_months[now.month - 1]}';
    }
    return '${from.day} ${_months[from.month - 1]} – '
        '${now.day} ${_months[now.month - 1]}';
  }
}

class _Bar extends StatelessWidget {
  final DayStat stat;
  final int best;
  const _Bar({required this.stat, required this.best});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final ratio = (stat.xp / best).clamp(0.0, 1.0);
    final tint = stat.isToday
        ? AppColors.primary
        : stat.xp == 0
            ? AppColors.muted(d)
            : AppColors.primaryEdge;
    final ink = stat.isToday
        ? (d ? AppColors.primary : AppColors.primaryDeep)
        : AppColors.text3(d);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SqNum('${stat.xp}', size: 9.5, color: ink),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: ratio),
          duration: const Duration(milliseconds: 620),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => Container(
            height: (6 + v * 74).clamp(6.0, 80.0),
            decoration: BoxDecoration(
              color: tint, borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 6),
        Text(stat.label,
          style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: ink)),
      ],
    );
  }
}
