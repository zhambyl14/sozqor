// lib/features/teams/team_war_screen.dart
//
// Team versus team, one day long (EN-26 / KK-4).
//
// KK-4 asks that this not be another test, and the shape it takes here is a
// hunt: both teams face the same boss and every match score is damage. The
// first side to fell it wins outright; if the creature is still standing at
// midnight the side that did more damage takes it. That framing is what turns
// "post a score" into "we are all hitting the same thing", which is the whole
// difference between a leaderboard and a raid.
//
// Two rules make it a TEAM event rather than a solo one, and both are enforced
// in SQL because a rule the client keeps is a rule a REST client ignores:
//
//   • Each player has a limited number of counted matches per war, so one
//     strong member cannot play the whole thing.
//   • A side scores NOTHING until enough distinct members have played, so one
//     strong member cannot BE the whole thing.
//
// The screen's job is to make both legible. A team whose damage says 1400 but
// whose effective damage says 0 looks broken unless the reason is on screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/team.dart';
import '../../data/repos/teams_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../play/play_session_screen.dart';

class TeamWarScreen extends ConsumerStatefulWidget {
  const TeamWarScreen({super.key});

  @override
  ConsumerState<TeamWarScreen> createState() => _TeamWarScreenState();
}

class _TeamWarScreenState extends ConsumerState<TeamWarScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      ref.invalidate(teamWarProvider);
    } on TeamsUnavailable {
      if (mounted) {
        sqSnack(context, tr('Команда жүйесі әлі қосылмаған'), error: true);
      }
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _findOpponent() => _run(() async {
    final s = await ref.read(teamsRepoProvider).findWar();
    if (!mounted) return;
    sqSnack(context, s?.war == null
        ? tr('Кезекке тұрдың — қарсылас табылған соң хабарлаймыз')
        : tr('Қарсылас табылды!'));
  });

  /// Plays one counted round and posts its score as damage.
  ///
  /// The round itself is the ordinary classic engine — what makes this a war
  /// is where the score goes, not a different set of questions. The server
  /// clamps the damage to what a real round can produce and refuses once the
  /// player has spent their counted matches, so a replayed or edited result
  /// cannot inflate the raid.
  Future<void> _attack(TeamWar war) async {
    final outcome = await Navigator.of(context).push<PlayOutcome>(
      MaterialPageRoute(builder: (_) => PlaySessionScreen(
        mode: PlayMode.classic,
        count: 10,
        title: tr('Шайқас раунды'))));
    if (outcome == null || !mounted) return;
    await _run(() async {
      final s = await ref.read(teamsRepoProvider)
          .submitWarMatch(war.id, outcome.score);
      if (!mounted) return;
      final left = s?.war?.matchesLeft ?? 0;
      sqSnack(context, trp('{n} зақым келтірдің · {left} соққы қалды', {
        'n': '${outcome.score}', 'left': '$left',
      }));
      refreshAll(ref);
    });
  }

  void _showRules(WarState s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SqSheetGrip(),
              Text(tr('Шайқас ережелері'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.text(isDark(context)))),
              const SizedBox(height: 16),
              // Written as byLang rather than tr because these are whole
              // paragraphs: a tr() key that long is unreadable in source and
              // a half-translated rulebook is worse than none.
              _Rule(
                icon: PhosphorIconsFill.skull,
                text: byLang(
                  kk: 'Екі команда бір жыртқышқа қарсы шығады. Әр раундтағы '
                      'ұпайың — сол жыртқышқа келтірген зақымың.',
                  ru: 'Две команды выходят против одного зверя. Твои очки в '
                      'раунде — это урон, который ты ему наносишь.')),
              _Rule(
                icon: PhosphorIconsFill.clock,
                text: byLang(
                  kk: 'Шайқас бір күнге созылады. Жыртқышты бірінші құлатқан '
                      'команда жеңеді; ешкім құлата алмаса, зақымы көп команда '
                      'жеңеді.',
                  ru: 'Битва длится один день. Побеждает команда, которая '
                      'первой свалит зверя; если он выстоит — та, что нанесла '
                      'больше урона.')),
              _Rule(
                icon: PhosphorIconsFill.handFist,
                text: byLang(
                  kk: 'Әр ойыншыға күніне ${s.matchLimit} соққы ғана '
                      'есептеледі. Бір адам бүкіл команда үшін ойнай алмайды.',
                  ru: 'Каждому игроку засчитывается только ${s.matchLimit} '
                      'удара в день. Один человек не может отыграть за всю '
                      'команду.')),
              _Rule(
                icon: PhosphorIconsFill.users,
                text: byLang(
                  kk: 'Командада кемінде ${s.minPlayers} мүше ойнамайынша, '
                      'зақым мүлде есептелмейді.',
                  ru: 'Пока в команде не сыграют минимум ${s.minPlayers} '
                      'участника, урон не засчитывается вовсе.')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final async = ref.watch(teamWarProvider);
    final state = async.valueOrNull;
    final unavailable = async.hasError && async.error is TeamsUnavailable;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async => ref.invalidate(teamWarProvider),
      children: [
        SqHeader(
          title: tr('Командалық шайқас'),
          eyebrow: tr('Бір күндік аң аулау'),
          onBack: () => Navigator.of(context).pop(),
          actions: [
            if (state != null)
              SqSquareButton(PhosphorIconsBold.question,
                size: 38, onTap: () => _showRules(state)),
          ]),
        const SizedBox(height: 16),

        if (unavailable)
          SqEmpty(
            icon: PhosphorIconsFill.sword,
            title: tr('Команда жүйесі әлі қосылмаған'),
            subtitle: tr('Сервер жаңартылған соң қолжетімді болады'),
            tint: AppColors.sky)
        else if (async.isLoading)
          const Column(children: [SqShimmer(height: 170), SqShimmer()])
        else if (state == null)
          SqEmpty(
            icon: PhosphorIconsFill.usersThree,
            title: tr('Алдымен командаға қосыл'),
            subtitle: tr('Шайқасқа тек команда мүшелері түседі'),
            tint: AppColors.sky)
        else if (state.war == null)
          ..._noWar(d, state)
        else
          ..._inWar(d, state, state.war!),
      ],
    );
  }

  List<Widget> _noWar(bool d, WarState s) => [
    SqInkCard(
      padding: const EdgeInsets.all(20),
      glow: AppColors.red,
      glowAt: Alignment.topRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(PhosphorIconsFill.skull, size: 34, color: AppColors.red),
          const SizedBox(height: 12),
          Text(tr('Бүгінгі шайқас басталмаған'),
            style: const TextStyle(
              fontSize: 19, fontWeight: FontWeight.w800,
              letterSpacing: -0.4, color: Colors.white)),
          const SizedBox(height: 4),
          Text(
            trp('Қарсылас іздеу үшін командада кемінде {n} мүше болуы керек',
              {'n': '${s.minTeamForWar}'}),
            style: const TextStyle(
              fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600,
              color: AppColors.onInk2)),
          const SizedBox(height: 16),
          SqAction(tr('Қарсылас табу'),
            icon: PhosphorIconsFill.sword,
            tone: SqTone.danger,
            busy: _busy,
            onTap: _busy ? null : _findOpponent),
        ],
      ),
    ),
    const SizedBox(height: 14),
    // The rules belong here, not only behind the "?" — this is the screen
    // where somebody decides whether to pull their team into a whole day of
    // it.
    _rulesPanel(d, s),
  ];

  /// EN-26's three rules where they can be read without opening anything.
  ///
  /// The numbers come from team_rules() by way of war_state, never from a
  /// constant here — a rulebook that quotes a number the server has since
  /// changed is worse than no rulebook.
  Widget _rulesPanel(bool d, WarState s) => SqPanel(
    padding: const EdgeInsets.fromLTRB(14, 13, 14, 5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _RuleLine(
          icon: PhosphorIconsFill.clock,
          text: tr('Шайқас бір күнге созылады')),
        _RuleLine(
          icon: PhosphorIconsFill.handFist,
          text: trp('Әр мүшеге күніне {n} соққы есептеледі',
            {'n': '${s.matchLimit}'})),
        _RuleLine(
          icon: PhosphorIconsFill.users,
          text: trp('Командадан кемінде {n} мүше ойнамайынша, зақым '
                    'есептелмейді', {'n': '${s.minPlayers}'})),
      ],
    ),
  );

  List<Widget> _inWar(bool d, WarState s, TeamWar war) {
    // war_state answers with a status='open' row the moment a team queues, and
    // team_b stays null until somebody is paired with it. isFinished, isToday
    // and matchesLeft all say "go" in that state, which is why the red button
    // used to render right beside the "Қарсылас күтілуде" card — ten questions
    // later submit_war_match refused the score with TEAM_ERR:war_over.
    final waiting = !war.isFinished && war.oppTeam == null;
    final canAttack =
        !war.isFinished && !waiting && war.isToday && war.matchesLeft > 0;
    final blocked = war.myPlayers < s.minPlayers;

    return [
      // The boss is the focus block: one creature, one bar, both teams' damage
      // in it. This is what makes the war feel shared rather than parallel.
      SqInkCard(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        glow: war.isFinished
            ? (war.iWon ? AppColors.green : AppColors.red)
            : AppColors.red,
        glowAt: Alignment.topRight,
        child: Column(
          children: [
            const Icon(PhosphorIconsFill.skull, size: 40, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              war.isFinished
                  ? (war.iWon ? tr('Жеңдік!') : tr('Жеңілдік'))
                  : tr('Жыртқыш'),
              style: const TextStyle(
                fontSize: 21, fontWeight: FontWeight.w800,
                letterSpacing: -0.4, color: Colors.white)),
            const SizedBox(height: 12),
            SqTrack(war.bossRatio,
              color: AppColors.red,
              background: AppColors.inkTrack,
              height: 12),
            const SizedBox(height: 6),
            Text(
              trp('{done} / {hp} зақым', {
                'done': '${war.myEffective + war.oppEffective}',
                'hp': '${war.bossHp}',
              }),
              style: const TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w700,
                color: AppColors.onInk2)),
          ],
        ),
      ),
      const SizedBox(height: 14),

      // Both sides, side by side. `effective` is the number that decides the
      // war; raw damage is shown underneath it so a blocked team can see the
      // damage it did do and why it is not counting yet.
      SqEqualRow(
        children: [
          Expanded(child: _SideCard(
            team: war.myTeam,
            effective: war.myEffective,
            raw: war.myScore,
            players: war.myPlayers,
            minPlayers: s.minPlayers,
            mine: true)),
          const SizedBox(width: 10),
          Expanded(child: _SideCard(
            team: war.oppTeam,
            effective: war.oppEffective,
            raw: war.oppScore,
            players: war.oppPlayers,
            minPlayers: s.minPlayers,
            mine: false)),
        ],
      ),
      const SizedBox(height: 14),

      if (blocked)
        SqPanel(
          padding: const EdgeInsets.all(14),
          fill: AppColors.soft(AppColors.amber, d),
          border: AppColors.line(AppColors.amber, d),
          child: Row(
            children: [
              const Icon(PhosphorIconsFill.warning,
                size: 18, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trp('Зақым әлі есептелмейді — тағы {n} мүше ойнауы керек', {
                    'n': '${s.minPlayers - war.myPlayers}',
                  }),
                  style: TextStyle(
                    fontSize: 12, height: 1.4, fontWeight: FontWeight.w700,
                    color: AppColors.onSoft(AppColors.amber, d))),
              ),
            ],
          ),
        ),
      if (blocked) const SizedBox(height: 12),

      if (war.isFinished)
        SqPanel(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              war.iWon
                  ? tr('Шайқас аяқталды — командаң жеңді')
                  : tr('Шайқас аяқталды'),
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: AppColors.text2(d))),
          ),
        )
      else if (waiting)
        SqPanel(
          padding: const EdgeInsets.all(16),
          fill: AppColors.soft(AppColors.sky, d),
          border: AppColors.line(AppColors.sky, d),
          child: Row(
            children: [
              const Icon(PhosphorIconsFill.hourglassMedium,
                size: 20, color: AppColors.sky),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Қарсылас күтілуде'),
                      style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800,
                        color: AppColors.onSoft(AppColors.sky, d))),
                    const SizedBox(height: 2),
                    Text(
                      tr('Командаң кезекте тұр. Қарсылас табылған соң шабуыл '
                         'ашылады.'),
                      style: TextStyle(
                        fontSize: 12, height: 1.4, fontWeight: FontWeight.w600,
                        color: AppColors.onSoft(AppColors.sky, d))),
                  ],
                ),
              ),
            ],
          ),
        )
      else if (canAttack)
        SqAction(
          trp('Шабуылдау · {n} соққы қалды', {'n': '${war.matchesLeft}'}),
          icon: PhosphorIconsFill.sword,
          tone: SqTone.danger,
          height: 54,
          busy: _busy,
          onTap: _busy ? null : () => _attack(war))
      else
        SqPanel(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              war.matchesLeft == 0
                  ? tr('Бүгінгі соққыларың бітті — ертең қайта кел')
                  : tr('Шайқас аяқталған'),
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: AppColors.text3(d))),
          ),
        ),

      const SizedBox(height: 14),
      _rulesPanel(d, s),

      if (war.top.isNotEmpty) ...[
        const SizedBox(height: 18),
        SqSection(tr('Ең көп зақым')),
        SqGroup(children: [
          for (final f in war.top)
            SqTile(
              leading: SqAvatar(f.name,
                size: 36,
                tint: f.mine ? AppColors.primary : AppColors.red),
              title: f.name,
              subtitle: trp('{n} раунд', {'n': '${f.matches}'}),
              trailing: SqNum('${f.damage}',
                size: 13,
                color: f.mine ? AppColors.primaryDeep : AppColors.red),
            ),
        ]),
      ],
    ];
  }
}

class _SideCard extends StatelessWidget {
  final Team? team;
  final int effective, raw, players, minPlayers;
  final bool mine;

  const _SideCard({
    required this.team,
    required this.effective,
    required this.raw,
    required this.players,
    required this.minPlayers,
    required this.mine,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tint = mine ? AppColors.primary : AppColors.red;
    final blocked = players < minPlayers;

    return SqPanel(
      padding: const EdgeInsets.all(14),
      border: mine ? AppColors.primaryEdge : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(team?.emblem ?? '❔', style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(team?.name ?? tr('Қарсылас күтілуде'),
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SqNum('$effective', size: 24, color: tint),
          if (blocked && raw > 0)
            Text(trp('({n} есептелмеген)', {'n': '$raw'}),
              style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700,
                color: AppColors.amberInk)),
          const SizedBox(height: 2),
          Text(trp('{n} ойыншы', {'n': '$players'}),
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: AppColors.text3(d))),
        ],
      ),
    );
  }
}

/// One rule as a line on the page itself. Narrower than [_Rule], which is
/// sized for the sheet — this one has to sit under the attack button without
/// pushing it off the screen, and its text wraps rather than being cut.
class _RuleLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _RuleLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: AppColors.red)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
              style: TextStyle(
                fontSize: 12, height: 1.45, fontWeight: FontWeight.w600,
                color: AppColors.text2(d))),
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Rule({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SqTintBox(icon, tint: AppColors.red, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
              style: TextStyle(
                fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600,
                color: AppColors.text2(d))),
          ),
        ],
      ),
    );
  }
}
