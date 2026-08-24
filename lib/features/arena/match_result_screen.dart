// lib/features/arena/match_result_screen.dart
//
// A finished match, reopened (EN-28 / KK-5).
//
// Recent Battles was a list of five rows that could not be tapped: the score
// and the rating change were printed on the row and everything else the match
// contained — who it was against, how long it took, how many answers were
// right, what mode it was — existed only for the few seconds the post-match
// screen was on screen, and then not at all.
//
// This is deliberately not the post-match screen reused. That one is part of
// playing: it animates in, it offers a rematch, it hands out achievements.
// This one is a record. It reads the row that was already fetched for the
// history list, so opening it costs nothing, and only the opponent's name is
// looked up.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/supa.dart';
import '../../providers.dart';

class MatchResultScreen extends ConsumerStatefulWidget {
  final Battle battle;
  /// Offered only for a friend match, where the opponent is somebody the
  /// learner can actually invite again. Null hides the action.
  final Future<void> Function(Battle)? onChallenge;

  const MatchResultScreen({super.key, required this.battle, this.onChallenge});

  @override
  ConsumerState<MatchResultScreen> createState() => _MatchResultScreenState();
}

class _MatchResultScreenState extends ConsumerState<MatchResultScreen> {
  String? _oppName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOpponent());
  }

  Future<void> _loadOpponent() async {
    final b = widget.battle;
    if (b.mode == 'bot') {
      if (mounted) setState(() => _oppName = b.botName ?? tr('Бот'));
      return;
    }
    final oppId = b.oppId(currentUid ?? '');
    if (oppId == null) return;
    try {
      final p = await ref.read(profileRepoProvider).byId(oppId);
      if (mounted && p != null) setState(() => _oppName = p.name);
    } catch (_) {/* the card simply stays generic */}
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final b = widget.battle;
    final uid = currentUid ?? '';

    final mine = b.myScore(uid);
    final theirs = b.oppScore(uid);
    final won = b.winner == uid;
    final draw = b.isDraw;
    final tint = draw ? AppColors.amber : won ? AppColors.green : AppColors.red;
    final delta = b.myEloDelta(uid);
    final correct = b.amHost(uid) ? b.p1Correct : b.p2Correct;
    final total = b.questions.length;
    final opp = _oppName ?? tr('Қарсылас');

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        SqHeader(
          title: tr('Баттл нәтижесі'),
          eyebrow: switch (b.mode) {
            'ranked' => tr('Рейтингті баттл'),
            'bot'    => tr('Ботпен'),
            _        => tr('Доспен'),
          },
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        SqInkCard(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
          glow: tint,
          glowAt: Alignment.topRight,
          child: Column(
            children: [
              Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: tint, borderRadius: BorderRadius.circular(20)),
                child: Icon(
                  draw
                      ? PhosphorIconsFill.handshake
                      : won ? PhosphorIconsFill.trophy
                            : PhosphorIconsFill.shieldWarning,
                  size: 30, color: Colors.white),
              ),
              const SizedBox(height: 14),
              Text(
                draw ? tr('Тең түсті') : won ? tr('Жеңіс') : tr('Жеңіліс'),
                style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w800,
                  letterSpacing: -0.5, color: Colors.white)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SqNum('$mine', size: 34, color: Colors.white),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text(':',
                      style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800,
                        color: AppColors.onInk3)),
                  ),
                  SqNum('$theirs', size: 34, color: AppColors.onInk2),
                ],
              ),
              const SizedBox(height: 3),
              Text(opp,
                style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: AppColors.onInk2)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        SqGroup(children: [
          _Stat(
            icon: PhosphorIconsFill.checkCircle,
            tint: AppColors.green,
            label: tr('Дұрыс жауап'),
            value: total > 0 ? '$correct / $total' : '$correct'),
          _Stat(
            icon: PhosphorIconsFill.xCircle,
            tint: AppColors.red,
            label: tr('Қате жауап'),
            value: '${(total - correct).clamp(0, total)}'),
          // Rating only ever moves in ranked play, so printing a zero for a
          // friend or bot match would read as "you drew" rather than "this
          // mode does not count" (EN-18).
          if (b.mode == 'ranked')
            _Stat(
              icon: delta >= 0
                  ? PhosphorIconsFill.trendUp
                  : PhosphorIconsFill.trendDown,
              tint: delta >= 0 ? AppColors.green : AppColors.red,
              label: tr('Рейтинг'),
              value: '${delta >= 0 ? '+' : ''}$delta')
          else
            _Stat(
              icon: PhosphorIconsFill.shieldCheck,
              tint: AppColors.text3(d),
              label: tr('Рейтинг'),
              value: tr('Есептелмейді')),
          if (_duration != null)
            _Stat(
              icon: PhosphorIconsFill.timer,
              tint: AppColors.sky,
              label: tr('Ұзақтығы'),
              value: _duration!),
          _Stat(
            icon: PhosphorIconsFill.calendarBlank,
            tint: AppColors.primary,
            label: tr('Күні'),
            value: _date),
        ]),

        if (widget.onChallenge != null && b.oppId(uid) != null) ...[
          const SizedBox(height: 18),
          // EN-29: an invitation, not a start. The other side still has to
          // accept before anything begins.
          SqAction(tr('Қайта шақыру'),
            icon: PhosphorIconsFill.sword,
            onTap: () async {
              final fn = widget.onChallenge!;
              Navigator.of(context).pop();
              await fn(b);
            }),
        ],
      ],
    );
  }

  /// How long the match took, or null when the row predates the timestamps
  /// (older battles carry no started_at).
  String? get _duration {
    final b = widget.battle;
    final start = b.startedAt, end = b.endedAt;
    if (start == null || end == null) return null;
    final secs = end.difference(start).inSeconds;
    if (secs <= 0) return null;
    final m = secs ~/ 60, s = secs % 60;
    return m > 0
        ? trp('{m} мин {s} сек', {'m': '$m', 's': '$s'})
        : trp('{s} сек', {'s': '$s'});
  }

  String get _date {
    final t = widget.battle.endedAt ?? widget.battle.createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.day)}.${two(t.month)}.${t.year}';
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String label, value;
  const _Stat({
    required this.icon, required this.tint,
    required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SqTile(
    leading: SqTintBox(icon, tint: tint, size: 34),
    title: label,
    trailing: SqNum(value,
      size: 13, color: AppColors.text(isDark(context))),
  );
}
