// lib/features/arena/league_screen.dart
//
// The weekly league: thirty learners per group, top ten promote, bottom ten
// demote.
//
// 5.0 ranks it on RATING rather than on XP earned this week (EN-19 / KK-3).
// Before, the league measured how much you played and the rating measured how
// well you played, and the two ladders had nothing to say to each other —
// which is what made "climb the league" and "raise your rating" feel like two
// unrelated games running side by side. The band a learner sits in now comes
// straight from their Elo, and the room is ordered by it.
//
// The band names, their thresholds and their colours all come from the server
// (league_bands()), never from a list compiled in here: a ladder whose rungs
// disagree between the app and the database is worse than no ladder. Until
// v5_league_elo.sql is applied the rows carry no band at all, and _tierNames
// below is the fallback that keeps the screen readable in the meantime.
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

/// Fallback band names, used only while the server is still on the old
/// my_league() and sends no band with the row.
List<String> get _tierNames => [
  tr('Қола'), tr('Күміс'), tr('Алтын'), tr('Платина'), tr('Алмас'), tr('Тұғыр'),
];
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
            final tier = (rows.isEmpty ? 0 : rows.first.tier).clamp(0, 5);
            final me = rows.where((r) => r.isMe).firstOrNull;
            // The server's own name for the band wins; the compiled list is
            // only there for a server that has not been migrated yet.
            final bandName = rows.isEmpty || rows.first.tierName.isEmpty
                ? _tierNames[tier]
                : rows.first.tierName;
            final demoteFrom = rows.length - _demote;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SqHeader(
                  title: trp('{tier} лигасы', {'tier': bandName}),
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
                    for (var i = 0; i < 6; i++) ...[
                      Expanded(child: _TierPip(index: i, active: i == tier)),
                      if (i != 5) const SizedBox(width: 5),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                // What the band actually means. A ladder rung with no number
                // on it is just a colour, and "how far am I from the next
                // one" is the only question anybody opens this screen to ask.
                if (me != null && me.tierMax > 0)
                  _BandRange(me: me),
                if (me != null && me.tierMax > 0) const SizedBox(height: 16),

                if (rows.isEmpty)
                  SqEmpty(
                    icon: PhosphorIconsFill.shieldStar,
                    title: tr('Лигаға енді қосыласың'),
                    subtitle: tr('Рейтингті баттл ойна — орның рейтингіңмен '
                                 'анықталады'))
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

                SqAction(tr('Рейтинг жинауға кірісу'),
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

  /// The one sentence on the screen, and it answers the only question the
  /// screen is opened to ask. It reads the rating rather than weekly XP,
  /// because that is what the standings are now ordered by — advice measured
  /// in a number the table is not sorted on is advice nobody can act on.
  static String _advice(List<LeagueRow> rows, LeagueRow? me) {
    if (me == null) {
      return trp('Апта соңында топ-{n} жоғары көтеріледі.',
        {'n': '$_promote'});
    }
    // The summit has nowhere above it, so "how do I climb" is the wrong
    // question to answer there (EN-19).
    if (me.isTopRank) {
      return tr('Ең жоғарғы дәрежедесің. Мұнда рейтингіңді ұстап тұру керек.');
    }
    if (me.rank <= _promote) {
      final below = rows.where((r) => r.rank == _promote + 1).firstOrNull;
      final gap = below == null ? 0 : (me.elo - below.elo).clamp(0, 1 << 30);
      return trp('Көтерілу аймағындасың — артыңдағыдан {n} рейтинг алдасың.',
        {'n': '$gap'});
    }
    final target = rows.where((r) => r.rank == _promote).firstOrNull;
    final need = target == null ? 0 : (target.elo - me.elo).clamp(0, 1 << 30);
    return trp('{r}-орын. Көтерілуге {n} рейтинг керек.',
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

/// Where the learner sits inside their own band, and what the next one costs.
class _BandRange extends StatelessWidget {
  final LeagueRow me;
  const _BandRange({required this.me});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = sqHexColor(me.tierColour) ?? AppColors.primary;
    final span = (me.tierMax - me.tierMin).clamp(1, 1 << 30);
    final into = ((me.elo - me.tierMin) / span).clamp(0.0, 1.0);

    return SqPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsFill.shieldStar, size: 15, color: tint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  me.isTopRank
                      ? trp('{n} рейтингтен жоғары', {'n': '${me.tierMin}'})
                      : trp('{lo} – {hi} рейтинг',
                          {'lo': '${me.tierMin}', 'hi': '${me.tierMax}'}),
                  style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.text2(d))),
              ),
              SqNum('${me.elo}', size: 14, color: tint),
            ],
          ),
          if (!me.isTopRank) ...[
            const SizedBox(height: 9),
            SqTrack(into, color: tint, height: 7),
            const SizedBox(height: 5),
            Text(
              trp('Келесі дәрежеге {n} рейтинг қалды',
                {'n': '${(me.tierMax + 1 - me.elo).clamp(0, 1 << 30)}'}),
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
          ],
        ],
      ),
    );
  }
}

class _TierPip extends StatelessWidget {
  final int index;
  final bool active;
  const _TierPip({required this.index, required this.active});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    // AppColors.tiers holds five; the summit reuses the brand red so the
    // top rung reads as a different thing rather than a sixth shade.
    final tint = index < AppColors.tiers.length
        ? AppColors.tiers[index] : AppColors.red;
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
          // The number the table is sorted by. Showing weekly XP here while
          // ranking on rating was the quickest way to make the order look
          // arbitrary.
          SqNum('${row.elo}', size: 12.5, color: AppColors.text2(d)),
        ],
      ),
    );
  }
}
