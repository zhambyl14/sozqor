// lib/features/arena/league_screen.dart
//
// The weekly league: thirty learners per group, top ten promote, bottom ten
// demote. Standings come straight from XP earned this week.
//
// 4.0 stops explaining the rule in a legend and draws it instead: a green band
// above the promotion cut, a red band below the relegation cut, and your own
// row tinted violet wherever it sits between them. You can read your fate
// without reading a sentence.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../play/play_session_screen.dart';

List<String> get _tierNames =>
    [tr('Қола'), tr('Күміс'), tr('Алтын'), tr('Платина'), tr('Алмас')];
const _promote = 10;
const _demote = 10;

class LeagueScreen extends ConsumerWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(myLeagueProvider);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(myLeagueProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        async.when(
          loading: () => const Column(children: [
            SqShimmer(height: 60, margin: EdgeInsets.only(bottom: 16)),
            SqShimmer(height: 70), SqShimmer(height: 240)]),
          error: (e, _) => Column(
            children: [
              SqHeader(title: tr('Лига'),
                onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 30),
              SqEmpty(
                icon: PhosphorIconsFill.warningCircle,
                title: tr('Лига жүктелмеді'),
                subtitle: humanError(e),
                tint: AppColors.red),
            ],
          ),
          data: (rows) {
            final tier = (rows.isEmpty ? 0 : rows.first.tier).clamp(0, 4);
            final me = rows.where((r) => r.isMe).firstOrNull;
            final demoteFrom = rows.length - _demote;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SqHeader(
                  title: trp('{tier} лигасы',
                    {'tier': tr(_tierNames[tier])}),
                  eyebrow: tr('Апталық лига'),
                  onBack: () => Navigator.of(context).pop(),
                  actions: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.soft(AppColors.red, d),
                        borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsFill.clock,
                            size: 14, color: AppColors.red),
                          const SizedBox(width: 5),
                          SqNum(_untilMonday(),
                            size: 11.5, color: AppColors.redInk),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    for (var i = 0; i < 5; i++) ...[
                      Expanded(child: _TierPip(index: i, active: i == tier)),
                      if (i != 4) const SizedBox(width: 6),
                    ],
                  ],
                ),
                const SizedBox(height: 16),

                if (rows.isEmpty)
                  SqEmpty(
                    icon: PhosphorIconsFill.shieldStar,
                    title: tr('Лигаға енді қосыласың'),
                    subtitle: tr(
                        tr('XP жинай баста — апта соңында орның анықталады')))
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card(d),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border(d)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _Band(
                          icon: PhosphorIconsFill.arrowFatLineUp,
                          label: trp('Көтерілу аймағы · топ-{n}',
                            {'n': '$_promote'}),
                          tint: AppColors.green),
                        for (var i = 0; i < rows.length; i++) ...[
                          _Row(row: rows[i], total: rows.length),
                          if (i == _promote - 1 && rows.length > _promote)
                            _Band(
                              icon: PhosphorIconsBold.minus,
                              label: tr('Қалу аймағы'),
                              tint: AppColors.text3(d)),
                          if (i == demoteFrom - 1 &&
                              rows.length > _promote + _demote)
                            _Band(
                              icon: PhosphorIconsFill.arrowFatLineDown,
                              label: trp('Түсу аймағы · соңғы {n}',
                                {'n': '$_demote'}),
                              tint: AppColors.red),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),

                SqPanel(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  fill: AppColors.soft(AppColors.primary, d),
                  border: AppColors.line(AppColors.primary, d),
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsFill.info,
                        size: 22, color: AppColors.primaryDeep),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _advice(rows, me),
                          style: TextStyle(
                            fontSize: 12, height: 1.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSoft(AppColors.primary, d))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                SqAction(tr('XP жинауға кірісу'),
                  icon: PhosphorIconsFill.lightning,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          const PlaySessionScreen(mode: PlayMode.classic)));
                    ref.invalidate(myLeagueProvider);
                  }),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _advice(List<LeagueRow> rows, LeagueRow? me) {
    if (me == null) {
      return trp('Апта соңында топ-{n} жоғары көтеріледі.',
        {'n': '$_promote'});
    }
    if (me.rank <= _promote) {
      final below = rows.where((r) => r.rank == _promote + 1).firstOrNull;
      final gap = below == null ? 0 : (me.xp - below.xp).clamp(0, 1 << 30);
      return trp('Көтерілу аймағындасың — артыңдағыдан {n} XP алдасың.',
        {'n': '$gap'});
    }
    final target = rows.where((r) => r.rank == _promote).firstOrNull;
    final need = target == null ? 0 : (target.xp - me.xp).clamp(0, 1 << 30);
    return trp('{r}-орын. Көтерілуге {n} XP керек.',
      {'r': '${me.rank}', 'n': '$need'});
  }

  static String _untilMonday() {
    final now = DateTime.now();
    final days = 8 - now.weekday;
    final hours = 24 - now.hour;
    return days >= 7
        ? trp('{h} сағ', {'h': '$hours'})
        : trp('{d} күн {h} сағ', {'d': '$days', 'h': '$hours'});
  }
}

class _TierPip extends StatelessWidget {
  final int index;
  final bool active;
  const _TierPip({required this.index, required this.active});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = AppColors.tiers[index];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      decoration: BoxDecoration(
        color: active ? tint : AppColors.muted(d),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: active ? tint : AppColors.border(d)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsFill.shieldStar,
            size: 16, color: active ? Colors.white : AppColors.text4(d)),
          const SizedBox(height: 5),
          Text(tr(_tierNames[index]),
            style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w800,
              color: active ? Colors.white : AppColors.text4(d))),
        ],
      ),
    );
  }
}

class _Band extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  const _Band({required this.icon, required this.label, required this.tint});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
      color: AppColors.soft(tint, d),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.onSoft(tint, d)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800,
                letterSpacing: 0.02,
                color: AppColors.onSoft(tint, d))),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final LeagueRow row;
  final int total;
  const _Row({required this.row, required this.total});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final promoting = row.rank <= _promote;
    final demoting = total > _promote + _demote && row.rank > total - _demote;
    final tint = promoting
        ? AppColors.green
        : demoting ? AppColors.red : AppColors.text3(d);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: row.isMe ? AppColors.soft(AppColors.primary, d) : null,
        border: Border(top: BorderSide(color: AppColors.divider(d))),
      ),
      child: Row(
        children: [
          SizedBox(width: 20,
            child: SqNum('${row.rank}', size: 13, color: tint)),
          const SizedBox(width: 10),
          SqAvatar(row.name,
            size: 34,
            tint: row.isMe ? AppColors.primary : null,
            solid: row.isMe),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              row.isMe
                  ? trp('{name} (сен)', {'name': row.name}) : row.name,
              style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800,
                color: row.isMe
                    ? AppColors.primaryDeep : AppColors.text(d))),
          ),
          SqNum('${row.xp}', size: 12.5, color: AppColors.text2(d)),
          const SizedBox(width: 3),
          Text('XP',
            style: TextStyle(
              fontSize: 9.5, fontWeight: FontWeight.w700,
              color: AppColors.text4(d))),
        ],
      ),
    );
  }
}
