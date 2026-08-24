// lib/features/arena/arena_screen.dart
//
// Everything competitive in one place.
//
// The 3.0 arena showed six identical gradient cards and left "what even is
// Elo?" unanswered. 4.0 answers it before offering anything: the rating panel
// spells out the three steps of a ranked match in one line each, then a single
// dark block lets you pick the opponent type with a segment and start with one
// button. League, tournament, daily and team follow as quiet entries.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/question.dart';
import '../../data/models/word.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/question_factory.dart';
import '../auth/guest_gate.dart';
import '../events/events_screen.dart';
import '../play/play_session_screen.dart';
import 'battle_screen.dart';
import 'clan_screen.dart';
import 'leaderboard_screen.dart';
import 'league_screen.dart';
import 'tournament_screen.dart';

enum _Opponent { ranked, bot, friend }

class ArenaScreen extends ConsumerStatefulWidget {
  const ArenaScreen({super.key});

  @override
  ConsumerState<ArenaScreen> createState() => _ArenaScreenState();
}

class _ArenaScreenState extends ConsumerState<ArenaScreen> {
  bool _busy = false;
  _Opponent _opponent = _Opponent.ranked;

  /// Battle rounds are built from the shared dictionary at the learner's
  /// level, so both sides always get the same fair set.
  Future<List<Question>> _buildQuestions({int count = 10}) async {
    final profile = ref.read(myProfileProvider).valueOrNull;
    final cefr = profile?.cefrLevel ?? 'A1';
    final lang = ref.read(nativeLangProvider);

    var pool = ref.read(levelPoolProvider).valueOrNull ?? const <DictEntry>[];
    if (pool.length < 12) {
      pool = await ref.read(dictRepoProvider)
          .pool(cefr: visibleCefrFor(cefr), limit: 120)
          .catchError((_) => <DictEntry>[]);
    }

    final words = ref.read(myWordsProvider).valueOrNull ?? const <Word>[];
    final items = <PlayItem>[
      ...words.take(30).map(PlayItem.fromWord),
      ...pool.map(PlayItem.fromDict),
    ];

    return QuestionFactory.build(
      items: items, pool: pool, kinds: kindsFor(cefr),
      count: count, nativeLang: lang);
  }

  Future<void> _openBattle(Battle b) async {
    final result = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BattleScreen(battle: b)));
    if (mounted) {
      refreshAll(ref);
      ref.invalidate(battleHistoryProvider);
      ref.invalidate(pendingInvitesProvider);
    }
    // "Кек қайтару" (rematch) pops the finished Battle back to us instead of
    // null — start a fresh match of the same mode right away so the button
    // actually does something a plain close does not.
    if (result is Battle && mounted) {
      if (result.mode == 'ranked') {
        await _startRanked();
      } else if (result.mode == 'bot') {
        await _startBot();
      } else if (result.mode == 'friend') {
        await _rematchFriend(result);
      }
    }
  }

  /// Starts a fresh no-code friend battle against whoever was on the other
  /// side of [finished] — used both for "Кек қайтару" on a finished friend
  /// match and for the direct challenge action on a history row.
  Future<void> _rematchFriend(Battle finished) async {
    final uid = currentUid;
    final opponentId = uid == null ? null : finished.oppId(uid);
    if (opponentId == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final questions = await _buildQuestions();
      if (questions.length < 5) {
        if (mounted) {
          sqSnack(context, tr('Баттл үшін сөз жетпейді'), error: true);
        }
        return;
      }
      final cefr = ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
      final battle = await ref.read(battleRepoProvider).createFriendBattle(
        questions: questions, cefr: cefr, targetUserId: opponentId);
      if (mounted) await _openBattle(battle);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    switch (_opponent) {
      case _Opponent.ranked: return _startRanked();
      case _Opponent.bot:    return _startBot();
      case _Opponent.friend: return _friendSheet();
    }
  }

  Future<void> _startRanked() async {
    if (!await requireAccount(context, ref, GuestFeature.ranked)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final questions = await _buildQuestions();
      if (questions.length < 5) {
        if (mounted) {
          sqSnack(context, tr('Баттл үшін сөз жетпейді'), error: true);
        }
        return;
      }
      if (!mounted) return;

      final battle = await showModalBottomSheet<Battle>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        builder: (_) => _MatchmakingSheet(questions: questions),
      );
      if (battle != null && mounted) await _openBattle(battle);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startBot() async {
    setState(() => _busy = true);
    try {
      final profile = ref.read(myProfileProvider).valueOrNull;
      final cefr = profile?.cefrLevel ?? 'A1';
      final questions = await _buildQuestions();
      if (questions.length < 5) {
        if (mounted) {
          sqSnack(context, tr('Баттл үшін сөз жетпейді'), error: true);
        }
        return;
      }
      final bot = botFor(cefr);
      final battle = await ref.read(battleRepoProvider)
          .startBot(questions: questions, cefr: cefr, bot: bot);
      if (mounted) await _openBattle(battle);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _friendSheet() async {
    if (!await requireAccount(context, ref, GuestFeature.friends)) return;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FriendSheet(
        onCreate: () async {
          final questions = await _buildQuestions();
          if (questions.length < 5) {
            throw Exception(tr('Баттл үшін сөз жетпейді'));
          }
          final cefr = ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
          return ref.read(battleRepoProvider)
              .createFriendBattle(questions: questions, cefr: cefr);
        },
        onJoin: (code) => ref.read(battleRepoProvider).joinByCode(code),
        onPlay: _openBattle,
      ),
    );
    if (mounted) ref.invalidate(pendingInvitesProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final league = ref.watch(myLeagueProvider).valueOrNull ?? const <LeagueRow>[];
    final tournament = ref.watch(tournamentProvider).valueOrNull;
    final invites = ref.watch(pendingInvitesProvider).valueOrNull ?? const <Battle>[];
    final playedDaily = ref.watch(playedDailyProvider).valueOrNull ?? false;
    final myRow = league.where((r) => r.isMe).firstOrNull;

    final played = profile?.battlesPlayed ?? 0;
    final won = profile?.battlesWon ?? 0;
    final lost = (played - won).clamp(0, played);

    return SqPage(
      onRefresh: () async {
        ref.invalidate(myLeagueProvider);
        ref.invalidate(tournamentProvider);
        ref.invalidate(pendingInvitesProvider);
        ref.invalidate(playedDailyProvider);
        ref.invalidate(battleHistoryProvider);
        ref.invalidate(myProfileProvider);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqEyebrow(tr('Жарыс')),
                  const SizedBox(height: 1),
                  Text(tr('Арена'),
                    style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800,
                      letterSpacing: -0.6)),
                ],
              ),
            ),
            SqSquareButton(PhosphorIconsBold.ranking,
              size: 40,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LeaderboardScreen()))),
          ],
        ),
        const SizedBox(height: 18),

        // not const: these translate, so they repaint on a language switch
        // ignore: prefer_const_constructors
        GuestBanner(feature: GuestFeature.ranked),

        if (invites.isNotEmpty) ...[
          for (final b in invites) ...[
            _InviteCard(battle: b, onPlay: () => _openBattle(b)),
            const SizedBox(height: 11),
          ],
        ],

        _RatingPanel(
          elo: profile?.elo ?? 1000,
          rank: profile?.rankTitle ?? '—',
          played: played, won: won, lost: lost),
        const SizedBox(height: 14),

        SqInkCard(
          padding: const EdgeInsets.all(19),
          glow: AppColors.red,
          glowAt: Alignment.bottomLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(PhosphorIconsFill.sword,
                    size: 20, color: AppColors.red),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(tr('Жекпе-жек'),
                      style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.w800,
                        letterSpacing: -0.3, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(tr('10 сұрақ · 3 мин'),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.onInk2)),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  for (final o in _Opponent.values) ...[
                    Expanded(
                      child: SqChip(
                        switch (o) {
                          _Opponent.ranked => tr('Рейтинг'),
                          _Opponent.bot => tr('Бот'),
                          _Opponent.friend => tr('Дос'),
                        },
                        icon: switch (o) {
                          _Opponent.ranked =>
                            PhosphorIconsFill.globeHemisphereEast,
                          _Opponent.bot => PhosphorIconsFill.robot,
                          _Opponent.friend => PhosphorIconsFill.usersThree,
                        },
                        onInk: true,
                        selected: _opponent == o,
                        radius: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 11),
                        onTap: () => setState(() => _opponent = o),
                      ),
                    ),
                    if (o != _Opponent.values.last) const SizedBox(width: 7),
                  ],
                ],
              ),
              const SizedBox(height: 15),
              SqAction(
                switch (_opponent) {
                  _Opponent.ranked => tr('Қарсылас табу'),
                  _Opponent.bot => tr('Ботпен ойнау'),
                  _Opponent.friend => tr('Дос шақыру'),
                },
                icon: PhosphorIconsFill.crosshair,
                tone: SqTone.danger,
                busy: _busy,
                onTap: _busy ? null : _start),
            ],
          ),
        ),
        const SizedBox(height: 14),

        _LeagueCard(
          rows: league,
          me: myRow,
          onTap: () async {
            if (!await requireAccount(context, ref, GuestFeature.league)) return;
            if (!context.mounted) return;
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LeagueScreen()));
          }),
        const SizedBox(height: 14),

        SqEqualRow(
          children: [
            Expanded(
              child: SqLip(
                fill: playedDaily ? AppColors.muted(d) : AppColors.primary,
                lip: playedDaily
                    ? AppColors.surfaceLip(d)
                    : AppColors.primaryDeep,
                radius: 20,
                padding: const EdgeInsets.all(15),
                onTap: () async {
                  if (playedDaily) {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const LeaderboardScreen(
                        initialTab: LeaderboardTab.daily)));
                    return;
                  }
                  if (!await requireAccount(
                      context, ref, GuestFeature.daily)) {
                    return;
                  }
                  if (!context.mounted) return;
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        const PlaySessionScreen(mode: PlayMode.daily)));
                  if (mounted) {
                    ref.invalidate(playedDailyProvider);
                    refreshAll(ref);
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsFill.globeHemisphereEast,
                      size: 24,
                      color: playedDaily
                          ? AppColors.text3(d) : Colors.white),
                    const SizedBox(height: 9),
                    Text(tr('Күнделікті сынақ'),
                      style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800,
                        color: playedDaily
                            ? AppColors.text(d) : Colors.white)),
                    Text(playedDaily
                        ? tr('Нәтижені көр') : tr('Әлем бір жиынтық'),
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: playedDaily
                            ? AppColors.text3(d)
                            : Colors.white.withValues(alpha: 0.82))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: SqLip(
                fill: AppColors.card(d),
                border: AppColors.border(d),
                lip: AppColors.surfaceLip(d),
                depth: 3,
                radius: 20,
                padding: const EdgeInsets.all(15),
                onTap: () async {
                  if (!await requireAccount(
                      context, ref, GuestFeature.tournament)) {
                    return;
                  }
                  if (!context.mounted) return;
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const TournamentScreen()));
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(PhosphorIconsFill.crownSimple,
                          size: 24, color: AppColors.amber),
                        const Spacer(),
                        if (tournament != null)
                          SqBadge(_short(tournament.remaining),
                            tint: AppColors.red, numeric: true, size: 9.5),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(tr('Турнир'),
                      style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    Text(tournament?.title ?? tr('24 сағат'),
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: AppColors.text3(d))),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ignore: prefer_const_constructors
        _TeamCard(),
        const SizedBox(height: 20),

        // Events sit in Arena rather than Play because they are the
        // competitive side of the app: a moderator runs them, they rank
        // people, and they hand out prizes. They had no entrance at all until
        // now — the rows existed on the server and nothing ever showed them.
        Consumer(
          builder: (_, ref, __) {
            final n = ref.watch(activeEventsProvider).valueOrNull?.length ?? 0;
            return SqTile(
              leading: const SqTintBox(PhosphorIconsFill.confetti,
                  tint: AppColors.primary, size: 36),
              title: tr('Ивенттер'),
              subtitle: n > 0
                  ? trp('{p1} ивент жүріп жатыр', {'p1': '$n'})
                  : tr('Жаңасын күт'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EventsScreen())),
            );
          },
        ),
        const SizedBox(height: 20),

        SqSection(tr('Соңғы баттлдар')),
        _HistoryList(onChallenge: _rematchFriend),
      ],
    );
  }

  static String _short(Duration d) {
    if (d.inHours > 0) {
      return trp('{h}с {m}м',
        {'h': '${d.inHours}', 'm': '${d.inMinutes % 60}'});
    }
    return trp('{m}м', {'m': '${d.inMinutes}'});
  }
}

// ── Rating panel ───────────────────────────────────────────

/// The rating card. The "how does a ranked match work" explainer is the one
/// piece of real prose on the Arena tab, so it starts folded — the answer is
/// there for a first-timer without taxing everyone who already knows.
class _RatingPanel extends StatefulWidget {
  final int elo, played, won, lost;
  final String rank;
  const _RatingPanel({
    required this.elo, required this.rank,
    required this.played, required this.won, required this.lost});

  @override
  State<_RatingPanel> createState() => _RatingPanelState();
}

class _RatingPanelState extends State<_RatingPanel> {
  bool _how = false;

  static List<(String, String, String)> get _steps => [
    ('1', tr('Қарсылас табылады'), tr('Elo жақын ойыншы')),
    ('2', tr('10 сұрақ, екеуіңе бірдей'), tr('кім жылдам — сол алда')),
    ('3', tr('Elo өзгереді'), tr('жеңсең +, жеңілсең −')),
  ];

  @override
  Widget build(BuildContext context) {
    final elo = widget.elo;
    final rank = widget.rank;
    final played = widget.played;
    final won = widget.won;
    final lost = widget.lost;
    final d = isDark(context);
    final tierIndex = elo >= 1500 ? 4 : elo >= 1300 ? 3
        : elo >= 1150 ? 2 : elo >= 1000 ? 1 : 0;
    final tint = AppColors.tiers[tierIndex];

    return SqPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqEyebrow(tr('Рейтинг')),
                  const SizedBox(height: 2),
                  SqNum('$elo',
                    size: 32, letterSpacing: -1, height: 1,
                    color: AppColors.text(d)),
                ],
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqBadge(tr(rank), tint: tint),
                  const SizedBox(height: 5),
                  Text(trp('{n} ойын · {w} жеңіс',
                      {'n': '$played', 'w': '$won'}),
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: AppColors.text3(d))),
                ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: played == 0
                  ? Container(color: AppColors.muted(d))
                  : Row(
                      children: [
                        Expanded(
                          flex: won.clamp(0, 9999) + 1,
                          child: Container(color: AppColors.green)),
                        Expanded(
                          flex: lost.clamp(0, 9999) + 1,
                          child: Container(color: AppColors.red)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _how = !_how),
            child: Row(
              children: [
                Icon(PhosphorIconsFill.info,
                  size: 15, color: AppColors.text3(d)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Баттл қалай өтеді?'),
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800,
                      color: AppColors.text2(d))),
                ),
                Icon(_how
                    ? PhosphorIconsBold.caretUp
                    : PhosphorIconsBold.caretDown,
                  size: 13, color: AppColors.text4(d)),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: !_how
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SqEqualRow(
                      children: [
                        for (var i = 0; i < _steps.length; i++) ...[
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.muted(d),
                                borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 20, height: 20,
                                    decoration: BoxDecoration(
                                      color: AppColors.inkBlock(d),
                                      borderRadius: BorderRadius.circular(7)),
                                    alignment: Alignment.center,
                                    child: SqNum(_steps[i].$1,
                                      size: 10.5, color: Colors.white),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(tr(_steps[i].$2),
                                    style: TextStyle(
                                      fontSize: 11, height: 1.3,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.text(d))),
                                  const SizedBox(height: 2),
                                  Text(tr(_steps[i].$3),
                                    style: TextStyle(
                                      fontSize: 10, height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.text3(d))),
                                ],
                              ),
                            ),
                          ),
                          if (i != _steps.length - 1) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── League preview ─────────────────────────────────────────

class _LeagueCard extends StatelessWidget {
  final List<LeagueRow> rows;
  final LeagueRow? me;
  final VoidCallback onTap;
  const _LeagueCard({required this.rows, required this.me, required this.onTap});

  static List<String> get _names =>
      [tr('Қола'), tr('Күміс'), tr('Алтын'), tr('Платина'), tr('Алмас')];

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final tier = (rows.isEmpty ? 0 : rows.first.tier).clamp(0, 4);
    final tint = AppColors.tiers[tier];
    final top = rows.take(7).toList();
    final maxXp = top.isEmpty
        ? 1 : top.map((r) => r.xp).reduce((a, b) => a > b ? a : b).clamp(1, 1 << 30);

    return SqPanel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SqTintBox(PhosphorIconsFill.shieldStar, tint: tint, size: 40),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(trp('{tier} лигасы', {'tier': _names[tier]}),
                      style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800,
                        color: AppColors.text(d))),
                    Text(
                      me == null
                          ? tr('XP жинай баста — орның анықталады')
                          : trp('{n}-орын · {xp} XP',
                              {'n': '${me!.rank}', 'xp': '${me!.xp}'}),
                      style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: AppColors.text3(d))),
                  ],
                ),
              ),
              Icon(PhosphorIconsBold.caretRight,
                size: 16, color: AppColors.text4(d)),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < top.length; i++) ...[
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: (10 + (top[i].xp / maxXp) * 28)
                                .clamp(6.0, 38.0),
                            decoration: BoxDecoration(
                              color: top[i].isMe
                                  ? AppColors.primary
                                  : i < 3 ? AppColors.green : AppColors.text4(d),
                              borderRadius: BorderRadius.circular(6)),
                          ),
                          const SizedBox(height: 4),
                          SqNum('${top[i].rank}',
                            size: 9,
                            color: top[i].isMe
                                ? AppColors.primary : AppColors.text4(d)),
                        ],
                      ),
                    ),
                    if (i != top.length - 1) const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Team card ──────────────────────────────────────────────

class _TeamCard extends ConsumerWidget {
  const _TeamCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final team = ref.watch(teamProvider).valueOrNull;

    return SqPanel(
      radius: 20,
      padding: const EdgeInsets.all(16),
      fill: AppColors.soft(AppColors.sky, d),
      border: AppColors.line(AppColors.sky, d),
      onTap: () async {
        if (!await requireAccount(context, ref, GuestFeature.friends)) return;
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ClanScreen()));
      },
      child: Row(
        children: [
          const SqTintBox(PhosphorIconsFill.flagBanner,
            tint: AppColors.sky, size: 40, solid: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Менің командам'),
                  style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
                Text(
                  team == null
                      ? tr('Жүктелуде…')
                      : trp('Апталық жарыс: {done} / {goal}',
                          {'done': '${team.total}', 'goal': '${team.goal}'}),
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: AppColors.onSoft(AppColors.sky, d))),
              ],
            ),
          ),
          Icon(PhosphorIconsBold.caretRight,
            size: 16, color: AppColors.onSoft(AppColors.sky, d)),
        ],
      ),
    );
  }
}

// ── Invite + history ───────────────────────────────────────

class _InviteCard extends StatelessWidget {
  final Battle battle;
  final VoidCallback onPlay;
  const _InviteCard({required this.battle, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqPanel(
      radius: 20,
      padding: const EdgeInsets.all(15),
      fill: AppColors.soft(AppColors.red, d),
      border: AppColors.line(AppColors.red, d),
      child: Row(
        children: [
          const SqTintBox(PhosphorIconsFill.sword,
            tint: AppColors.red, size: 40, solid: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Дос баттлы күтіп тұр'),
                  style: TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800,
                    color: AppColors.text(d))),
                Text(trp('Код: {code}', {'code': battle.inviteCode ?? '—'}),
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: AppColors.onSoft(AppColors.red, d))),
              ],
            ),
          ),
          SqLip(
            fill: AppColors.red,
            lip: AppColors.redDeep,
            depth: 3,
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            onTap: onPlay,
            child: Text(tr('Ойнау'),
              style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800,
                color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  final Future<void> Function(Battle) onChallenge;
  const _HistoryList({required this.onChallenge});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final uid = currentUid ?? '';
    final async = ref.watch(battleHistoryProvider);

    return async.when(
      loading: () => const SqShimmer(height: 70, margin: EdgeInsets.zero),
      error: (_, __) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) {
          return SqPanel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.sword,
                  tint: AppColors.red, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tr('Әзірге баттл жоқ. Біреуін баста!'),
                    style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                      color: AppColors.text3(d))),
                ),
              ],
            ),
          );
        }
        return SqGroup(children: [
          for (final b in list.take(5))
            _HistoryRow(battle: b, uid: uid, onChallenge: onChallenge),
        ]);
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Battle battle;
  final String uid;
  final Future<void> Function(Battle) onChallenge;
  const _HistoryRow({
    required this.battle, required this.uid, required this.onChallenge});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final mine = battle.myScore(uid);
    final theirs = battle.oppScore(uid);
    final won = battle.winner == uid;
    final draw = battle.isDraw;
    final tint = draw ? AppColors.amber : won ? AppColors.green : AppColors.red;
    final delta = battle.myEloDelta(uid);
    // A stranger from ranked (or the bot) isn't a "challenge again" target —
    // only a finished friend match has a known opponent worth re-inviting.
    final canChallenge = battle.mode == 'friend' && battle.oppId(uid) != null;

    return SqTile(
      leading: SqTintBox(
        draw
            ? PhosphorIconsFill.handshake
            : won ? PhosphorIconsFill.trophy
                  : PhosphorIconsFill.shieldWarning,
        tint: tint, size: 36),
      title: draw ? tr('Тең түсті') : won ? tr('Жеңіс') : tr('Жеңіліс'),
      titleColor: tint,
      subtitle: switch (battle.mode) {
        'ranked' => tr('Рейтингті баттл'),
        'bot'    => trp('Ботпен · {name}',
                      {'name': battle.botName ?? tr('Бот')}),
        _        => tr('Доспен'),
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              SqNum('$mine : $theirs', size: 14, color: AppColors.text(d)),
              if (battle.mode == 'ranked' && delta != 0)
                SqNum('${delta > 0 ? '+' : ''}$delta',
                  size: 11,
                  color: delta > 0 ? AppColors.green : AppColors.red),
            ],
          ),
          if (canChallenge) ...[
            const SizedBox(width: 8),
            SqSquareButton(PhosphorIconsFill.sword,
              size: 30,
              onTap: () => onChallenge(battle)),
          ],
        ],
      ),
    );
  }
}

// ── Matchmaking sheet ──────────────────────────────────────

class _MatchmakingSheet extends ConsumerStatefulWidget {
  final List<Question> questions;
  const _MatchmakingSheet({required this.questions});

  @override
  ConsumerState<_MatchmakingSheet> createState() => _MatchmakingSheetState();
}

class _MatchmakingSheetState extends ConsumerState<_MatchmakingSheet> {
  static const _waitSeconds = 15;

  Timer? _poll;
  int _waited = 0;
  bool _closing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _poll?.cancel();
    ref.read(battleRepoProvider).leaveQueue();
    super.dispose();
  }

  Future<void> _search() async {
    final repo = ref.read(battleRepoProvider);
    final cefr = ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';

    Future<void> attempt() async {
      if (_closing || !mounted) return;
      try {
        final id = await repo.findOrQueue(
          cefr: cefr, questions: widget.questions);
        // The user may have tapped "Ботпен ойнау" while this was in flight —
        // re-check right after the await instead of trusting the entry guard.
        if (_closing || !mounted) return;
        if (id != null) {
          _closing = true;
          _poll?.cancel();
          final battle = await repo.byId(id);
          await repo.leaveQueue();
          if (mounted && battle != null) Navigator.of(context).pop(battle);
          return;
        }
      } catch (e) {
        if (mounted) setState(() => _error = humanError(e));
      }
    }

    await attempt();
    _poll = Timer.periodic(const Duration(seconds: 2), (t) async {
      if (!mounted) { t.cancel(); return; }
      setState(() => _waited += 2);
      if (_waited >= _waitSeconds) { t.cancel(); return; }
      await attempt();
    });
  }

  Future<void> _playBot() async {
    _poll?.cancel();
    _closing = true;
    final repo = ref.read(battleRepoProvider);
    await repo.leaveQueue();
    final cefr = ref.read(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
    try {
      final battle = await repo.startBot(
        questions: widget.questions, cefr: cefr, bot: botFor(cefr));
      if (mounted) Navigator.of(context).pop(battle);
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final timedOut = _waited >= _waitSeconds;

    return Padding(
      padding: EdgeInsets.only(
        left: 22, right: 22, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SqSheetGrip(),
          if (!timedOut) ...[
            const _Radar(),
            const SizedBox(height: 18),
            Text(tr('Қарсылас ізделуде…'),
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
            const SizedBox(height: 6),
            SqNum(trp('{n} сек', {'n': '${_waitSeconds - _waited}'}),
              size: 13, color: AppColors.text3(d)),
          ] else ...[
            const SqTintBox(PhosphorIconsFill.robot,
              tint: AppColors.sky, size: 62),
            const SizedBox(height: 14),
            Text(tr('Қарсылас табылмады'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
            const SizedBox(height: 6),
            Text(tr('Ботпен ойнап тұра тұр — кейін нағыз қарсылас табылады'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
            const SizedBox(height: 18),
            SqAction(tr('Ботпен ойнау'),
              icon: PhosphorIconsFill.robot,
              tone: SqTone.sky,
              onTap: _playBot),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.red, fontSize: 12.5,
                fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 10),
          SqAction(tr('Болдырмау'),
            tone: SqTone.ghost, height: 48,
            onTap: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _Radar extends StatefulWidget {
  const _Radar();
  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 116, height: 116,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Stack(
        alignment: Alignment.center,
        children: [
          for (final phase in [0.0, 0.33, 0.66])
            Opacity(
              opacity: (1 - ((_c.value + phase) % 1)).clamp(0.0, 1.0) * 0.4,
              child: Container(
                width: 44 + ((_c.value + phase) % 1) * 72,
                height: 44 + ((_c.value + phase) % 1) * 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2)),
              ),
            ),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(19),
              boxShadow: const [BoxShadow(
                color: AppColors.primaryDeep,
                offset: Offset(0, 4), blurRadius: 0)],
            ),
            child: const Icon(PhosphorIconsFill.crosshair,
              color: Colors.white, size: 26),
          ),
        ],
      ),
    ),
  );
}

// ── Friend sheet ───────────────────────────────────────────

class _FriendSheet extends StatefulWidget {
  final Future<Battle> Function() onCreate;
  final Future<Battle> Function(String code) onJoin;
  final Future<void> Function(Battle) onPlay;

  const _FriendSheet({
    required this.onCreate, required this.onJoin, required this.onPlay});

  @override
  State<_FriendSheet> createState() => _FriendSheetState();
}

class _FriendSheetState extends State<_FriendSheet> {
  final _code = TextEditingController();
  Battle? _created;
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _create() async {
    setState(() { _busy = true; _error = null; });
    try {
      final b = await widget.onCreate();
      if (mounted) setState(() => _created = b);
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final code = _code.text.trim().toUpperCase();
    if (code.length < 4) {
      setState(() => _error = tr('Кодты толық енгізіңіз'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final b = await widget.onJoin(code);
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onPlay(b);
    } catch (e) {
      if (mounted) setState(() => _error = humanError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 22, right: 22, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SqSheetGrip(),
            Text(tr('Досыңа қарсы'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800,
                letterSpacing: -0.4, color: AppColors.text(d))),
            const SizedBox(height: 18),

            if (_created == null) ...[
              SqAction(tr('Шақыру құру'),
                icon: PhosphorIconsBold.linkSimple,
                tone: SqTone.danger,
                busy: _busy,
                onTap: _create),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: Divider(color: AppColors.border(d))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(tr('немесе'),
                    style: TextStyle(
                      color: AppColors.text4(d), fontSize: 12.5,
                      fontWeight: FontWeight.w600))),
                Expanded(child: Divider(color: AppColors.border(d))),
              ]),
              const SizedBox(height: 18),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800,
                  letterSpacing: 5, color: AppColors.text(d)),
                decoration: InputDecoration(hintText: tr('Кодты енгіз')),
              ),
              const SizedBox(height: 12),
              SqAction(tr('Қосылу'),
                icon: PhosphorIconsBold.signIn,
                busy: _busy,
                onTap: _join),
            ] else ...[
              SqInkCard(
                padding: const EdgeInsets.all(22),
                glow: AppColors.red,
                child: Column(children: [
                  SqEyebrow(tr('Шақыру коды'), color: AppColors.onInk2),
                  const SizedBox(height: 8),
                  SqNum(_created!.inviteCode ?? '—',
                    size: 36, color: Colors.white, letterSpacing: 7),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: SqAction(tr('Көшіру'),
                  icon: PhosphorIconsBold.copy,
                  tone: SqTone.ghost, height: 48,
                  onTap: () {
                    Clipboard.setData(
                      ClipboardData(text: _created!.inviteCode ?? ''));
                    sqSnack(context, tr('Код көшірілді'));
                  })),
                const SizedBox(width: 10),
                Expanded(child: SqAction(tr('Бөлісу'),
                  icon: PhosphorIconsBold.shareNetwork,
                  tone: SqTone.ghost, height: 48,
                  onTap: () => Share.share(
                    trp('SozQor-да маған қарсы ойна! Код: {code}',
                      {'code': '${_created!.inviteCode}'})))),
              ]),
              const SizedBox(height: 12),
              SqAction(tr('Мен бірінші ойнаймын'),
                icon: PhosphorIconsFill.play,
                tone: SqTone.danger,
                onTap: () async {
                  final b = _created!;
                  Navigator.of(context).pop();
                  await widget.onPlay(b);
                }),
              const SizedBox(height: 10),
              Text(
                tr('Досың кодты енгізіп ойнаған соң, '
                   'нәтижелерің салыстырылады.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12, height: 1.45, fontWeight: FontWeight.w600,
                  color: AppColors.text3(d))),
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.red, fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
