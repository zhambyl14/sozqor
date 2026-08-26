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

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/repos/league_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../auth/guest_gate.dart';
import '../profile/public_profile_screen.dart';

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
        ref.invalidate(leagueRewardProvider);
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
                  const SizedBox(height: 14),
                ],

                // The reason to climb. Everything above this line only ever
                // told the learner where they stood.
                const _LeagueChest(),
                const SizedBox(height: 18),

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

                // This used to open a classic practice round, which earns
                // тәжірибе and moves the rating by exactly nothing — the
                // button promised the one thing it could not do. Rating comes
                // from rated battles only, and those start on the Arena.
                SqAction(tr('Рейтингті баттлға кірісу'),
                  icon: PhosphorIconsFill.sword,
                  tone: SqTone.danger,
                  onTap: () {
                    ref.invalidate(leagueStandingsProvider);
                    ref.invalidate(leagueProgressProvider);
                    Navigator.of(context).pop();
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

    // Everybody in this room is somebody you are competing with, and until
    // now there was no way to find out who any of them were. Tapping opens
    // their profile — which is also where you can add them.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: row.isMe
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PublicProfileScreen(
                userId: row.userId,
                fallbackName: row.displayName.isEmpty
                    ? row.username : row.displayName))),
      child: Container(
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
      ),
    );
  }
}

/// The band's chest: what standing here pays, and the button that takes it.
///
/// Two things arrive together and are claimed together — the weekly chest and
/// the one-off for having climbed — because presenting them as two buttons
/// would mean explaining the difference, and the learner does not care: they
/// care that the ladder pays.
class _LeagueChest extends ConsumerStatefulWidget {
  const _LeagueChest();

  @override
  ConsumerState<_LeagueChest> createState() => _LeagueChestState();
}

class _LeagueChestState extends ConsumerState<_LeagueChest> {
  bool _busy = false;

  Future<void> _claim() async {
    if (_busy) return;
    if (!await requireAccount(context, ref, GuestFeature.league)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final got = await ref.read(leagueRepoProvider).claimReward();
      ref.invalidate(leagueRewardProvider);
      ref.invalidate(myProfileProvider);
      if (!mounted) return;
      if (got == null) {
        sqSnack(context, tr('Бұл аптаның сыйлығы алынып қойған'));
      } else {
        sqSnack(context, trp('+{c} тиын · +{x} тәжірибе',
            {'c': '${got.coins}', 'x': '${got.xp}'}));
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final r = ref.watch(leagueRewardProvider).valueOrNull;
    // Null means an un-migrated server. A card that cannot say anything true
    // should say nothing at all.
    if (r == null) return const SizedBox.shrink();

    final tint = sqHexColor(r.colour) ?? AppColors.amber;

    return SqPanel(
      radius: 20,
      padding: const EdgeInsets.all(16),
      fill: AppColors.soft(tint, d),
      border: AppColors.line(tint, d),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SqTintBox(PhosphorIconsFill.treasureChest,
                tint: tint, size: 42, solid: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(trp('{tier} сыйлығы', {'tier': r.name}),
                      style: TextStyle(
                        fontSize: 14.5, height: 1.25,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    const SizedBox(height: 2),
                    Text(
                      r.ready
                          ? trp('{c} тиын · {x} тәжірибе',
                              {'c': '${r.coins}', 'x': '${r.xp}'})
                          : trp('Келесі аптада: {c} тиын · {x} тәжірибе',
                              {'c': '${r.weeklyCoins}',
                               'x': '${r.weeklyXp}'}),
                      style: TextStyle(
                        fontSize: 12, height: 1.3, fontWeight: FontWeight.w700,
                        color: AppColors.onSoft(tint, d))),
                  ],
                ),
              ),
            ],
          ),
          if (r.promoReady) ...[
            const SizedBox(height: 10),
            Text(
              trp('{n} лигаға көтерілгенің үшін бонус қосылды',
                {'n': '${r.promoBands}'}),
              style: TextStyle(
                fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w700,
                color: AppColors.onSoft(tint, d))),
          ],
          if (r.nextCoins > 0) ...[
            const SizedBox(height: 10),
            Text(
              trp('Келесі лигада апта сайын: {c} тиын · {x} тәжірибе',
                {'c': '${r.nextCoins}', 'x': '${r.nextXp}'}),
              style: TextStyle(
                fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
          ],
          const SizedBox(height: 12),
          SqAction(
            r.ready ? tr('Сыйлықты алу') : tr('Сыйлық алынды'),
            icon: r.ready
                ? PhosphorIconsFill.gift
                : PhosphorIconsFill.checkCircle,
            tone: r.ready ? SqTone.primary : SqTone.ghost,
            height: 48,
            busy: _busy,
            onTap: r.ready ? _claim : null),
        ],
      ),
    );
  }
}
