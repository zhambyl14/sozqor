// lib/features/teams/teams_screen.dart
//
// Teams (EN-24) and the weekly team challenge (EN-25 / KK-4).
//
// 4.0 called "your friends" a clan and raced them against a goal nobody
// agreed to, nobody could leave, and no two people saw the same version of.
// A team here is a row: you create it or you are let into it, it has a roster
// with roles, and everybody in it sees the same numbers.
//
// The weekly bar is the screen's focus block, and it deliberately shows the
// two rules that make it a *team* challenge rather than a solo one: every
// member's contribution is capped at a share of the goal, and the reward needs
// a minimum number of different people to have helped. Both are enforced in
// SQL — this screen only has to make them legible, because a bar that stops
// moving for no visible reason reads as a bug.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/battle.dart';
import '../../data/models/team.dart';
import '../../data/repos/teams_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../auth/guest_gate.dart';
import '../profile/public_profile_screen.dart';
import 'team_war_screen.dart';

/// Emblems and colours a team can fly. Kept short on purpose — a picker with
/// forty options is a decision, and naming the team is the decision that
/// matters.
const _kEmblems = ['🛡️', '⚔️', '🔥', '🐺', '🦅', '🌙', '⭐', '🏔️', '🐎', '🏹'];
const _kColours = [
  '#7C5CFF', '#F0455E', '#12B981', '#F59E0B', '#3B82F6', '#EC4899',
];

class TeamsScreen extends ConsumerStatefulWidget {
  const TeamsScreen({super.key});

  @override
  ConsumerState<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends ConsumerState<TeamsScreen> {
  final _search = TextEditingController();
  List<TeamBoardRow> _results = const [];
  bool _searching = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The browse list is the whole screen for somebody without a team, so it
    // is fetched up front rather than waiting for them to type.
    WidgetsBinding.instance.addPostFrameCallback((_) => _find());
  }

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _find() async {
    setState(() => _searching = true);
    try {
      final rows = await ref.read(teamsRepoProvider).search(_search.text);
      if (mounted) setState(() => _results = rows);
    } on TeamsUnavailable {
      // The empty state below already explains this; a snackbar on top of it
      // would just be the same sentence twice.
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _run(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
      refreshTeam(ref);
    } on TeamsUnavailable {
      if (mounted) sqSnack(context, tr('Команда жүйесі әлі қосылмаған'), error: true);
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!await requireAccount(context, ref, GuestFeature.friends)) return;
    if (!mounted) return;
    final made = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateTeamSheet(),
    );
    if (made == true) refreshTeam(ref);
  }

  /// The same gate `_create` uses. Without it the server answers a guest with
  /// TEAM_ERR:guest, which is a refusal with no way forward in it — the sheet
  /// is the way forward.
  Future<void> _join(TeamBoardRow row) async {
    if (!await requireAccount(context, ref, GuestFeature.friends)) return;
    if (!mounted) return;
    await _run(() async {
      await ref.read(teamsRepoProvider).join(row.id);
      if (mounted) {
        sqSnack(context, trp('«{p1}» командасына қосылдың', {'p1': row.name}));
      }
    });
  }

  Future<void> _invitePlayer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _InvitePlayerSheet(),
    );
    refreshTeam(ref);
  }

  Future<void> _leave(Team team) async {
    final ok = await sqConfirm(context,
      title: tr('Командадан шығу'),
      message: team.iAmOwner
          ? tr('Сен құрушысың. Шықсаң, командаңды басқа мүшеге береді немесе '
               'ешкім қалмаса команда жойылады.')
          : trp('«{p1}» командасынан шығасың ба?', {'p1': team.name}),
      confirm: tr('Шығу'));
    if (!ok) return;
    await _run(() async {
      await ref.read(teamsRepoProvider).leave();
      if (mounted) sqSnack(context, tr('Командадан шықтың'));
    });
  }

  Future<void> _claim() => _run(() async {
    final w = await ref.read(teamsRepoProvider).claimWeekly();
    if (mounted && w != null) {
      sqSnack(context, trp('Апталық сыйлық алынды: +{n} XP', {'n': '${w.rewardXp}'}));
    }
    refreshAll(ref);
  });

  Future<void> _respondInvite(TeamInvite i, {required bool accept}) => _run(() async {
    await ref.read(teamsRepoProvider).respondToInvite(i.id, accept: accept);
    if (mounted) {
      sqSnack(context, accept
          ? trp('«{p1}» командасына қосылдың', {'p1': i.name})
          : tr('Шақыру қабылданбады'));
    }
  });

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final teamAsync = ref.watch(myTeamProvider);
    final team = teamAsync.valueOrNull;
    final unavailable = teamAsync.hasError &&
        teamAsync.error is TeamsUnavailable;

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        refreshTeam(ref);
        await _find();
      },
      children: [
        SqHeader(
          title: tr('Команда'),
          eyebrow: tr('Бірге үйрен'),
          onBack: () => Navigator.of(context).pop()),
        const SizedBox(height: 16),

        if (unavailable)
          SqEmpty(
            icon: PhosphorIconsFill.usersThree,
            title: tr('Команда жүйесі әлі қосылмаған'),
            subtitle: tr('Сервер жаңартылған соң қолжетімді болады'),
            tint: AppColors.sky)
        else if (teamAsync.isLoading)
          const Column(children: [SqShimmer(height: 150), SqShimmer()])
        else if (team == null)
          ..._noTeam(d)
        else
          ..._withTeam(d, team),
      ],
    );
  }

  // ── No team yet ────────────────────────────────────────
  List<Widget> _noTeam(bool d) {
    final invites = ref.watch(teamInvitesProvider).valueOrNull
        ?? const <TeamInvite>[];

    return [
      SqInkCard(
        padding: const EdgeInsets.all(20),
        glow: AppColors.primary,
        glowAt: Alignment.topRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SqEyebrow(tr('Команда'), color: AppColors.onInk2),
            const SizedBox(height: 5),
            Text(tr('Бірге үйрену жылдамырақ'),
              style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800,
                letterSpacing: -0.4, color: Colors.white)),
            const SizedBox(height: 4),
            Text(tr('Апталық ортақ мақсат, командалық шайқас және сыйлықтар'),
              style: const TextStyle(
                fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600,
                color: AppColors.onInk2)),
            const SizedBox(height: 15),
            SqAction(tr('Команда құру'),
              icon: PhosphorIconsBold.plus,
              busy: _busy,
              onTap: _busy ? null : _create),
          ],
        ),
      ),
      const SizedBox(height: 16),

      // An invitation is the fastest way in, so it sits above the browse list.
      if (invites.isNotEmpty) ...[
        SqSection(tr('Шақырулар'),
          trailingWidget: SqNum('${invites.length}',
            size: 11, color: AppColors.text3(d))),
        SqGroup(children: [
          for (final i in invites)
            SqTile(
              leading: _Emblem(emblem: i.emblem, colour: i.colour, size: 38),
              title: i.tag.isEmpty ? i.name : '[${i.tag}] ${i.name}',
              subtitle: trp('{n} мүше · {who} шақырды',
                {'n': '${i.memberCount}', 'who': i.invitedByName}),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SqSquareButton(PhosphorIconsBold.check,
                    size: 34,
                    fill: AppColors.soft(AppColors.green, d),
                    border: Colors.transparent,
                    iconColor: AppColors.greenDeep,
                    onTap: _busy ? null : () => _respondInvite(i, accept: true)),
                  const SizedBox(width: 8),
                  SqSquareButton(PhosphorIconsBold.x,
                    size: 34,
                    fill: AppColors.soft(AppColors.red, d),
                    border: Colors.transparent,
                    iconColor: AppColors.red,
                    onTap: _busy ? null : () => _respondInvite(i, accept: false)),
                ],
              ),
            ),
        ]),
        const SizedBox(height: 18),
      ],

      _SearchBar(
        controller: _search,
        hint: tr('Команда іздеу…'),
        onSubmit: _find),
      const SizedBox(height: 12),

      if (_searching)
        const Column(children: [SqShimmer(), SqShimmer(), SqShimmer()])
      else if (_results.isEmpty)
        SqEmpty(
          icon: PhosphorIconsFill.magnifyingGlass,
          title: tr('Команда табылмады'),
          subtitle: tr('Атын немесе тегін жаз, әлде өзің құр'),
          tint: AppColors.sky)
      else
        SqGroup(children: [
          for (final r in _results)
            SqTile(
              leading: _Emblem(emblem: r.emblem, colour: r.colour, size: 38),
              title: r.tag.isEmpty ? r.name : '[${r.tag}] ${r.name}',
              subtitle: trp('{n}/{max} мүше · {xp} XP',
                {'n': '${r.memberCount}', 'max': '20', 'xp': '${r.weekXp}'}),
              trailing: SqBadge(tr('Қосылу'),
                tint: AppColors.primary, solid: true),
              onTap: _busy ? null : () => _join(r),
            ),
        ]),
    ];
  }

  // ── In a team ──────────────────────────────────────────
  List<Widget> _withTeam(bool d, Team team) {
    final weekly = ref.watch(teamWeeklyProvider).valueOrNull;
    final roster = ref.watch(teamRosterProvider(team.id)).valueOrNull
        ?? const <TeamMemberRow>[];
    final war = ref.watch(teamWarProvider).valueOrNull;

    return [
      // The team's own banner. Not the focus block — the weekly goal is.
      SqPanel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _Emblem(emblem: team.emblem, colour: team.colour, size: 52),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(team.name,
                    style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800,
                      letterSpacing: -0.3, color: AppColors.text(d))),
                  Text(trp('{n} мүше · {lvl}-деңгей',
                    {'n': '${team.memberCount}', 'lvl': '${team.level}'}),
                    style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: AppColors.text3(d))),
                ],
              ),
            ),
            SqSquareButton(PhosphorIconsBold.signOut,
              size: 36,
              fill: AppColors.soft(AppColors.red, d),
              border: Colors.transparent,
              iconColor: AppColors.red,
              onTap: _busy ? null : () => _leave(team)),
          ],
        ),
      ),
      const SizedBox(height: 14),

      if (weekly != null) ...[
        _WeeklyCard(
          weekly: weekly,
          busy: _busy,
          onClaim: _claim),
        const SizedBox(height: 14),
      ],

      // The war entry. EN-26 is a separate screen because it is a separate
      // day-long event with its own rules, not a widget on this page.
      SqLip(
        fill: AppColors.red,
        lip: const Color(0xFFB8253A),
        radius: 20,
        padding: const EdgeInsets.all(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const TeamWarScreen())),
        child: Row(
          children: [
            const Icon(PhosphorIconsFill.sword, size: 24, color: Colors.white),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Командалық шайқас'),
                    style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w800,
                      color: Colors.white)),
                  Text(
                    war?.war == null
                        ? tr('Қарсылас тап — бір күндік аң аулау')
                        : trp('{me} : {opp}', {
                            'me': '${war!.war!.myEffective}',
                            'opp': '${war.war!.oppEffective}',
                          }),
                    style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85))),
                ],
              ),
            ),
            const Icon(PhosphorIconsBold.caretRight,
              size: 16, color: Colors.white),
          ],
        ),
      ),
      const SizedBox(height: 18),

      SqSection(tr('Мүшелер'),
        trailingWidget: SqNum('${roster.length}/${team.memberLimit}',
          size: 11, color: AppColors.text3(d))),
      if (roster.isEmpty)
        const SqShimmer()
      else
        SqGroup(children: [
          for (final m in roster)
            SqTile(
              leading: SqAvatar(m.name, size: 36),
              title: m.name,
              subtitle: switch (m.role) {
                'owner'   => tr('Құрушы'),
                'officer' => tr('Офицер'),
                _         => trp('{n} XP қосты', {'n': '${m.contributedXp}'}),
              },
              trailing: SqNum(trp('{n} XP', {'n': '${m.weekXp}'}),
                size: 12,
                color: m.capped ? AppColors.amberInk : AppColors.text3(d)),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PublicProfileScreen(
                  userId: m.userId, fallbackName: m.name))),
            ),
        ]),

      // Only the owner and officers may invite — the server refuses everybody
      // else, and offering a button that always fails is worse than not
      // offering one.
      if (team.iAmOfficer && !team.isFull) ...[
        const SizedBox(height: 12),
        SqAction(tr('Ойыншы шақыру'),
          icon: PhosphorIconsBold.userPlus,
          tone: SqTone.softPrimary,
          onTap: _busy ? null : _invitePlayer),
      ],
    ];
  }
}

// ── The weekly goal ──────────────────────────────────────────

class _WeeklyCard extends StatelessWidget {
  final TeamWeekly weekly;
  final bool busy;
  final VoidCallback onClaim;

  const _WeeklyCard({
    required this.weekly, required this.busy, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final w = weekly;
    return SqInkCard(
      padding: const EdgeInsets.all(20),
      glow: w.canClaim ? AppColors.green : AppColors.primary,
      glowAt: Alignment.topRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SqEyebrow(tr('Апталық мақсат'), color: AppColors.onInk2),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        SqCountUp(w.progress, size: 32, color: Colors.white),
                        const SizedBox(width: 5),
                        Text('/ ${w.goal}',
                          style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700,
                            color: AppColors.onInk3)),
                      ],
                    ),
                  ],
                ),
              ),
              SqRing(
                value: w.ratio,
                size: 54, stroke: 7,
                color: w.canClaim ? AppColors.green : AppColors.primary,
                track: AppColors.inkTrack,
                child: SqNum('${(w.ratio * 100).round()}%',
                  size: 12, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // EN-25 made legible. A member whose bar stopped at the cap, or a
          // goal that is full but short of contributors, both look like bugs
          // unless the screen says what the rule is.
          Row(
            children: [
              const Icon(PhosphorIconsFill.users,
                size: 14, color: AppColors.onInk2),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  trp('{n}/{need} мүше қосты · әркімнің шегі {cap} XP', {
                    'n': '${w.contributors}',
                    'need': '${w.minContributors}',
                    'cap': '${w.capPerMember}',
                  }),
                  style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600,
                    color: AppColors.onInk2)),
              ),
            ],
          ),

          if (w.members.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final m in w.members.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(m.name,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w700,
                          color: AppColors.onInk2)),
                    ),
                    Expanded(
                      child: SqTrack(
                        w.capPerMember == 0
                            ? 0
                            : (m.weekXp / w.capPerMember).clamp(0.0, 1.0),
                        color: m.capped ? AppColors.amber : AppColors.primary,
                        background: AppColors.inkTrack,
                        height: 6),
                    ),
                    const SizedBox(width: 8),
                    SqNum('${m.weekXp}',
                      size: 11,
                      color: m.capped ? AppColors.amber : AppColors.onInk2),
                  ],
                ),
              ),
          ],

          const SizedBox(height: 12),
          if (w.claimed)
            Center(
              child: SqChip(tr('Сыйлық алынды'),
                icon: PhosphorIconsFill.checkCircle,
                tint: AppColors.green,
                radius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
            )
          else if (w.canClaim)
            SqAction(trp('Сыйлықты алу · +{n} XP', {'n': '${w.rewardXp}'}),
              icon: PhosphorIconsFill.gift,
              tone: SqTone.green,
              busy: busy,
              onTap: busy ? null : onClaim)
          else if (w.needsMorePeople)
            Text(
              trp('Мақсат орындалды, бірақ тағы {n} мүшенің үлесі керек', {
                'n': '${w.minContributors - w.contributors}',
              }),
              style: const TextStyle(
                fontSize: 12, height: 1.4, fontWeight: FontWeight.w700,
                color: AppColors.amber))
          else
            Text(trp('Сенің үлесің: {n} XP', {'n': '${w.myXp}'}),
              style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: AppColors.onInk2)),
        ],
      ),
    );
  }
}

// ── Small pieces ─────────────────────────────────────────────

class _Emblem extends StatelessWidget {
  final String emblem, colour;
  final double size;
  const _Emblem({required this.emblem, required this.colour, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = sqHexColor(colour) ?? AppColors.primary;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
        border: Border.all(color: c.withValues(alpha: 0.45), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(emblem, style: TextStyle(fontSize: size * 0.46)),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmit;
  const _SearchBar({
    required this.controller, required this.hint, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.card(d),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.border(d)),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsBold.magnifyingGlass,
            size: 17, color: AppColors.text4(d)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              style: TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w600,
                color: AppColors.text(d)),
              decoration: InputDecoration(
                hintText: hint,
                filled: false, isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                hintStyle: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600,
                  color: AppColors.text4(d)),
              ),
            ),
          ),
          GestureDetector(
            onTap: onSubmit,
            child: const Icon(PhosphorIconsBold.arrowRight,
              size: 17, color: AppColors.primary)),
        ],
      ),
    );
  }
}

// ── Inviting a player ────────────────────────────────────────

/// The roster's way to reach `invite_to_team`, which had no button anywhere in
/// the app until now.
///
/// It asks for a whole handle on purpose. `search_users` was tightened in
/// v5_friend_search.sql to answer only a full @username or a pasted account
/// id, three characters minimum, precisely so that this kind of screen cannot
/// become a directory of strangers to page through — you invite somebody you
/// already know how to name.
class _InvitePlayerSheet extends ConsumerStatefulWidget {
  const _InvitePlayerSheet();

  @override
  ConsumerState<_InvitePlayerSheet> createState() => _InvitePlayerSheetState();
}

class _InvitePlayerSheetState extends ConsumerState<_InvitePlayerSheet> {
  final _query = TextEditingController();
  List<BoardRow> _results = const [];
  bool _searching = false;
  bool _searched = false;
  String? _sending;

  @override
  void dispose() { _query.dispose(); super.dispose(); }

  Future<void> _find() async {
    final q = _query.text.trim();
    if (q.length < 3) {
      sqSnack(context, tr('Толық @атын немесе аккаунт ID-ін жаз'), error: true);
      return;
    }
    setState(() => _searching = true);
    try {
      final rows = await ref.read(boardRepoProvider).searchUsers(q);
      if (mounted) setState(() { _results = rows; _searched = true; });
    } catch (e) {
      if (mounted) sqSnack(context, humanError(e), error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _invite(BoardRow row) async {
    setState(() => _sending = row.userId);
    try {
      // 'already' means a pending invitation is still sitting in their inbox —
      // saying "invited" a second time would look like it never arrived.
      final result = await ref.read(teamsRepoProvider).invite(row.userId);
      if (!mounted) return;
      Navigator.of(context).pop();
      sqSnack(context, result == 'already'
          ? trp('{p1} бұрын шақырылған — жауабын күт', {'p1': row.name})
          : trp('{p1} командаға шақырылды', {'p1': row.name}));
    } on TeamsUnavailable {
      if (mounted) {
        setState(() => _sending = null);
        sqSnack(context, tr('Команда жүйесі әлі қосылмаған'), error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = null);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SqSheetGrip(),
            Text(tr('Ойыншы шақыру'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
            const SizedBox(height: 6),
            Text(tr('Толық @атын немесе аккаунт ID-ін жаз'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600,
                color: AppColors.text3(d))),
            const SizedBox(height: 16),

            _SearchBar(
              controller: _query,
              hint: tr('@аты немесе ID'),
              onSubmit: _find),
            const SizedBox(height: 12),

            if (_searching)
              const Column(children: [SqShimmer(), SqShimmer()])
            else if (_results.isNotEmpty)
              SqGroup(children: [
                for (final r in _results)
                  SqTile(
                    leading: SqAvatar(r.name, size: 36),
                    title: r.name,
                    subtitle: r.username.isEmpty ? null : '@${r.username}',
                    trailing: _sending == r.userId
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : SqBadge(tr('Шақыру'),
                            tint: AppColors.primary, solid: true),
                    onTap: _sending == null ? () => _invite(r) : null,
                  ),
              ])
            else if (_searched)
              SqEmpty(
                icon: PhosphorIconsFill.magnifyingGlass,
                title: tr('Ойыншы табылмады'),
                subtitle: tr('Аты дәл жазылғанын тексер — қонақтар табылмайды'),
                tint: AppColors.sky),
          ],
        ),
      ),
    );
  }
}

// ── Creating a team ──────────────────────────────────────────

class _CreateTeamSheet extends ConsumerStatefulWidget {
  const _CreateTeamSheet();

  @override
  ConsumerState<_CreateTeamSheet> createState() => _CreateTeamSheetState();
}

class _CreateTeamSheetState extends ConsumerState<_CreateTeamSheet> {
  final _name = TextEditingController();
  final _tag = TextEditingController();
  String _emblem = _kEmblems.first;
  String _colour = _kColours.first;
  bool _busy = false;

  @override
  void dispose() { _name.dispose(); _tag.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.length < 3) {
      sqSnack(context, tr('Команда атауы кемінде 3 таңба болсын'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(teamsRepoProvider).create(
        name: name, tag: _tag.text.trim(), emblem: _emblem, colour: _colour);
      if (mounted) Navigator.of(context).pop(true);
    } on TeamsUnavailable {
      if (mounted) {
        setState(() => _busy = false);
        sqSnack(context, tr('Команда жүйесі әлі қосылмаған'), error: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        sqSnack(context, humanError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).viewInsets.bottom + 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SqSheetGrip(),
            Text(tr('Команда құру'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800,
                color: AppColors.text(d))),
            const SizedBox(height: 18),

            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: tr('Атауы')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tag,
              maxLength: 5,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: tr('Қысқа тег'),
                helperText: tr('Мысалы: QYRAN'),
              ),
            ),
            const SizedBox(height: 8),

            SqEyebrow(tr('Эмблема')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                for (final e in _kEmblems)
                  GestureDetector(
                    onTap: () => setState(() => _emblem = e),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.muted(d),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: e == _emblem
                              ? AppColors.primary : Colors.transparent,
                          width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(e, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            SqEyebrow(tr('Түсі')),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final c in _kColours) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _colour = c),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: sqHexColor(c),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: c == _colour
                                ? AppColors.text(d) : Colors.transparent,
                            width: 2.5),
                        ),
                      ),
                    ),
                  ),
                  if (c != _kColours.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 20),

            SqAction(tr('Құру'),
              icon: PhosphorIconsBold.check,
              busy: _busy,
              onTap: _busy ? null : _submit),
          ],
        ),
      ),
    );
  }
}
