// lib/features/arena/league_screen.dart
//
// The league is a rating threshold, not a top-ten cut.
//
// Until today this screen promoted the top ten of a thirty-person room and
// relegated the bottom ten, which meant two learners with the same rating had
// opposite fates depending on who happened to share their room — and somebody
// who improved all week could still be pushed down by strangers. The rule the
// product owner actually wants is the plain one: "кім келесі лиганың минимум
// кубогына жетті сол өтеді". You move up when your rating reaches the number
// the next band opens at. Nobody is promoted for placing.
//
// So the promotion and relegation zones are gone, along with every mention of
// a top ten, and nothing here is measured in XP any more: the room is a rating
// table, and the header is one distance to one number.
//
// Every band name, threshold and colour comes from the server — see
// league_repo.dart for why none of it is compiled into the app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/repos/league_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../play/play_session_screen.dart';

/// The band's own colour as the server sends it. The compiled palette is only
/// a fallback for a band that arrives without one — it holds five shades for
/// seven rungs, so the summit reuses the brand red rather than inventing one.
Color _bandColor(String hex, int tier) =>
    sqHexColor(hex) ??
    (tier < AppColors.tiers.length ? AppColors.tiers[tier] : AppColors.red);

class LeagueScreen extends ConsumerWidget {
  const LeagueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final async = ref.watch(leagueStandingsProvider);
    final progress = ref.watch(leagueProgressProvider).valueOrNull;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(leagueStandingsProvider);
        ref.invalidate(leagueProgressProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Лига'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        async.when(
          loading: () => const Column(children: [
            SqShimmer(height: 148, margin: EdgeInsets.only(bottom: 16)),
            SqShimmer(height: 240)]),
          error: (e, _) => SqEmpty(
            icon: PhosphorIconsFill.warningCircle,
            title: tr('Лига жүктелмеді'),
            subtitle: humanError(e),
            tint: AppColors.red),
          data: (rows) {
            final me = rows.where((r) => r.isMe).firstOrNull;
            // Only league_progress() knows the band *above* this one, and the
            // standings usually land first. Until it answers, the learner's
            // own row already carries their rating and their band, which is
            // enough to draw the header — a header that appears late reads
            // like a header that failed.
            final band =
                progress ?? (me == null ? null : LeagueProgress.fromRow(me));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (band != null) ...[
                  _Crown(band),
                  const SizedBox(height: 18),
                ],

                // The whole ladder, so "where am I in all of this" is a look
                // rather than a guess.
                if (band != null && band.bands.isNotEmpty) ...[
                  SqSection(tr('Лига баспалдағы')),
                  _Ladder(bands: band.bands, tier: band.tier),
                  const SizedBox(height: 20),
                ],

                if (rows.isEmpty)
                  SqEmpty(
                    icon: PhosphorIconsFill.shieldStar,
                    title: tr('Лигаға енді қосыласың'),
                    subtitle: tr('Рейтингті баттл ойна — орның рейтингіңмен '
                                 'анықталады'))
                else ...[
                  SqSection(tr('Рейтинг бойынша')),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card(isDark(context)),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border(isDark(context))),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          _Row(row: rows[i], first: i == 0),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                SqAction(tr('Рейтинг жинауға кірісу'),
                  icon: PhosphorIconsFill.lightning,
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          const PlaySessionScreen(mode: PlayMode.classic)));
                    ref.invalidate(leagueStandingsProvider);
                    ref.invalidate(leagueProgressProvider);
                  }),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The band, the rating, and the one sentence about what happens next.
class _Crown extends StatelessWidget {
  final LeagueProgress p;
  const _Crown(this.p);

  /// The only sentence on the screen. It names a band and a number, because
  /// the rule is now a number: reach it and you are in the next league.
  String get _next {
    if (p.isTop) return tr('Ең жоғарғы лига');
    if (p.nextName.isEmpty) {
      return trp('Келесі лигаға {n} ұпай қалды', {'n': '${p.toNext}'});
    }
    return trp('{tier} лигасына {n} ұпай қалды',
      {'tier': p.nextName, 'n': '${p.toNext}'});
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = _bandColor(p.colour, p.tier);
    final name = p.name.isEmpty ? tr('Лига') : p.name;

    return SqInkCard(
      glow: tint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(15)),
                alignment: Alignment.center,
                child: Icon(PhosphorIconsFill.shieldStar, size: 23, color: tint),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(name,
                  style: const TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800,
                    letterSpacing: -0.4, height: 1.15, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqNum('${p.elo}', size: 25, color: Colors.white),
                  SqEyebrow(tr('Рейтинг'), color: AppColors.onInk2, size: 9),
                ],
              ),
            ],
          ),

          // The bar runs from the floor of this band to the threshold of the
          // next one — the span promotion is actually decided on. A bar drawn
          // against a placing in the room would be measuring something nobody
          // is judged by any more.
          if (!p.isTop) ...[
            const SizedBox(height: 17),
            SqTrack(p.intoBand,
              color: tint,
              background: AppColors.inkBlockTrack(d),
              height: 9),
            const SizedBox(height: 7),
            Row(
              children: [
                SqNum('${p.bandMin}', size: 10.5, color: AppColors.onInk3),
                const Spacer(),
                SqNum('${p.nextAt}', size: 10.5, color: AppColors.onInk3),
              ],
            ),
          ],

          const SizedBox(height: 12),
          Text(_next,
            style: const TextStyle(
              fontSize: 13, height: 1.45, fontWeight: FontWeight.w700,
              color: AppColors.onInkSoft)),
        ],
      ),
    );
  }
}

/// Every rung of the ladder with the rating it opens at.
class _Ladder extends StatelessWidget {
  final List<LeagueBand> bands;
  final int tier;
  const _Ladder({required this.bands, required this.tier});

  @override
  Widget build(BuildContext context) {
    // Horizontal and scrollable rather than seven cells squeezed across a
    // phone: a band named "Платина" has to be able to print its whole name.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < bands.length; i++) ...[
            _Rung(band: bands[i], here: bands[i].tier == tier),
            if (i != bands.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Rung extends StatelessWidget {
  final LeagueBand band;
  final bool here;
  const _Rung({required this.band, required this.here});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = _bandColor(band.colour, band.tier);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: here ? AppColors.soft(tint, d) : AppColors.card(d),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: here ? AppColors.line(tint, d) : AppColors.border(d),
          width: here ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(band.name,
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800,
                  color: here
                      ? AppColors.onSoft(tint, d) : AppColors.text2(d))),
            ],
          ),
          const SizedBox(height: 4),
          // The number that moves you. Reaching it is the whole rule.
          SqNum(band.isTop ? '${band.min}+' : '${band.min}',
            size: 11, color: AppColors.text3(d)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final LeagueRow row;
  final bool first;
  const _Row({required this.row, required this.first});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: row.isMe ? AppColors.soft(AppColors.primary, d) : null,
        border: first
            ? null
            : Border(top: BorderSide(color: AppColors.divider(d))),
      ),
      child: Row(
        children: [
          // A band holds everybody inside a rating range, so the place can run
          // past two digits — the box grows rather than clipping the number.
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 22),
            child: SqNum('${row.rank}', size: 13, color: AppColors.text3(d))),
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
          const SizedBox(width: 10),
          // The one number on the row, and the one the table is ordered by.
          SqNum('${row.elo}',
            size: 13,
            color: row.isMe ? AppColors.primaryDeep : AppColors.text2(d)),
        ],
      ),
    );
  }
}
