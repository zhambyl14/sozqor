// lib/features/arena/tournament_screen.dart
//
// A rolling 24-hour tournament, played as SURVIVAL (EN-23 / KK-4).
//
// A round used to be PlayMode.tournament — PlayMode.classic with a different
// label and a different place to post the score. "Tournament must not feel
// like another Classic Test" is the PRD's wording, and it was right: nothing
// about it was different.
//
// Now a run is something you can lose. Three lives a day, waves that answer
// faster the deeper you go, and a decision between every wave: bank what you
// have, or push on and risk it. That decision is the mode; the run screen
// (tournament_run_screen.dart) is where it happens.
//
// The header block answers the three questions a timed event has to answer in
// one glance — how long is left, where am I, how many points do I have — and
// the prize ladder sits right under it so "why bother" never needs looking up.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import 'tournament_run_screen.dart';

class TournamentScreen extends ConsumerStatefulWidget {
  const TournamentScreen({super.key});

  @override
  ConsumerState<TournamentScreen> createState() => _TournamentScreenState();
}

class _TournamentScreenState extends ConsumerState<TournamentScreen> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _clock?.cancel(); super.dispose(); }

  Future<void> _play(Tournament t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TournamentRunScreen(
        tournamentId: t.id, title: t.title)));
    if (mounted) {
      ref.invalidate(tournamentBoardProvider(t.id));
      ref.invalidate(tournamentProvider);
      refreshAll(ref);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final async = ref.watch(tournamentProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Турнир'),
          eyebrow: tr('24 сағаттық'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),
        async.when(
          loading: () => const Column(children: [
            SqShimmer(height: 190), SqShimmer(), SqShimmer()]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Турнир жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red),
          data: (t) => _Body(tournament: t, onPlay: () => _play(t)),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  final Tournament tournament;
  final VoidCallback onPlay;
  const _Body({required this.tournament, required this.onPlay});

  static List<(String, String, Color)> get _prizes => [
    (tr('1 орын'), tr('2 000 тәжірибе + Алмас жиек'), const Color(0xFFFFAA00)),
    (tr('2–3 орын'), '1 200 XP', const Color(0xFF9FB0C4)),
    (tr('4–10 орын'), '600 XP', const Color(0xFFCD7F32)),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final board = ref.watch(tournamentBoardProvider(tournament.id));
    final uid = currentUid;
    final remaining = tournament.remaining;
    final rows = board.valueOrNull ?? const <BoardRow>[];
    final me = rows.where((r) => r.userId == uid).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SqInkCard(
          padding: const EdgeInsets.all(20),
          glow: AppColors.amber,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      borderRadius: BorderRadius.circular(16)),
                    child: const Icon(PhosphorIconsFill.crownSimple,
                      size: 23, color: AppColors.ink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tournament.title,
                          style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800,
                            letterSpacing: -0.3, color: Colors.white)),
                        Text(trp('Жиынтық ұпай · {n} қатысушы',
                            {'n': '${rows.length}'}),
                          style: const TextStyle(
                            fontSize: 11.5, fontWeight: FontWeight.w600,
                            color: AppColors.onInk2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: SqInkStat(_clock(remaining), tr('қалды'))),
                  const SizedBox(width: 9),
                  Expanded(child: SqInkStat(
                    me == null ? '—' : '${me.rank}', tr('орын'))),
                  const SizedBox(width: 9),
                  Expanded(child: SqInkStat(
                    me == null ? '0' : '${me.value}', tr('ұпай'),
                    valueColor: AppColors.amber)),
                ],
              ),
              const SizedBox(height: 16),
              SqAction(
                remaining > Duration.zero
                    ? tr('Раунд ойнау') : tr('Турнир аяқталды'),
                icon: PhosphorIconsFill.play,
                tone: SqTone.amber,
                height: 52,
                onTap: remaining > Duration.zero ? onPlay : null),
            ],
          ),
        ),
        const SizedBox(height: 18),

        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: SqEyebrow(tr('Жүлделер'))),
        SqGroup(children: [
          for (final p in _prizes)
            SqTile(
              leading: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: p.$3, borderRadius: BorderRadius.circular(11)),
                child: const Icon(PhosphorIconsFill.medal,
                  size: 16, color: Colors.white),
              ),
              title: tr(p.$1),
              trailing: Text(tr(p.$2),
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppColors.text2(d))),
            ),
        ]),
        const SizedBox(height: 18),

        SqSection(tr('Турнир кестесі')),
        board.when(
          loading: () => const Column(children: [SqShimmer(), SqShimmer()]),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) {
            if (list.isEmpty) {
              return SqPanel(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SqTintBox(PhosphorIconsFill.trophy,
                      tint: AppColors.amber, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('Әзірге қатысушы жоқ — бірінші болып баста!'),
                        style: TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600,
                          color: AppColors.text3(d))),
                    ),
                  ],
                ),
              );
            }
            return SqGroup(children: [
              for (final r in list.take(20))
                SqTile(
                  fill: r.userId == uid
                      ? AppColors.soft(AppColors.primary, d) : null,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(width: 20,
                        child: SqNum('${r.rank}',
                          size: 13, color: AppColors.text4(d))),
                      const SizedBox(width: 8),
                      SqAvatar(r.name,
                        size: 34,
                        tint: r.userId == uid ? AppColors.primary : null,
                        solid: r.userId == uid),
                    ],
                  ),
                  title: r.userId == uid
                      ? trp('{name} (сен)', {'name': r.name}) : r.name,
                  titleColor: r.userId == uid
                      ? AppColors.primaryDeep : AppColors.text(d),
                  subtitle: r.cefrLevel,
                  trailing: SqNum('${r.value}',
                    size: 12.5, color: AppColors.text2(d)),
                ),
            ]);
          },
        ),
      ],
    );
  }

  static String _clock(Duration d) {
    if (d <= Duration.zero) return '00:00';
    return '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }
}
