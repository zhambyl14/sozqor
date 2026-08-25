// lib/features/home/missions_screen.dart
//
// The mission path, as a progression map (EN-9 / KK-1).
//
// The complaint the PRD makes about 4.0's version is that a learner cannot
// tell what the mission IS, what to do about it, where they are, or what comes
// next. It was a flat list of twelve reward rows with a level number derived
// from lifetime XP — accurate, and unreadable as a journey.
//
// This is a path: nodes down the screen in a zig-zag, each in one of four
// states you can tell apart at a glance, with the CURRENT one as the single
// dark focus block carrying the action. A locked node states its condition
// rather than showing a padlock and leaving the learner to guess. Milestones
// are visibly larger, so the ladder has landmarks instead of twelve identical
// rungs.
//
// Two dishonest things from 4.0 are gone. The countdown counted down to the
// end of the calendar month, which is not a season boundary and not stored
// anywhere — a deadline the app invented. And "Премиум жолды ашу" granted
// premium for free, on this device, to anybody who pressed it: a paywall that
// is not one is worse than either having one or not. Those rewards are
// milestones now, earned at their level like everything else.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../providers.dart';
import '../../services/meta_store.dart';
import '../play/play_session_screen.dart';

/// What one node on the path is currently worth doing about.
enum _NodeState { claimed, claimable, current, locked }

class MissionsScreen extends ConsumerWidget {
  const MissionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(langProvider); // repaint on a language switch
    final d = isDark(context);
    final xp = ref.watch(myProfileProvider).valueOrNull?.xp ?? 0;
    final meta = ref.watch(metaProvider);
    final level = passLevelFor(xp);
    final claimed = meta.passClaimed;

    final ready = kPassRewards
        .where((r) => r.level <= level && !claimed.contains(r.level))
        .toList();
    final done = kPassRewards.where((r) => claimed.contains(r.level)).length;

    // The next node that is not finished — the one the whole screen is about.
    final next = kPassRewards.firstWhere(
      (r) => !claimed.contains(r.level),
      orElse: () => kPassRewards.last);

    return SqPage(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      onRefresh: () async {
        ref.invalidate(myProfileProvider);
        await Future<void>.delayed(const Duration(milliseconds: 350));
      },
      children: [
        SqHeader(
          title: tr('Миссия жолы'),
          eyebrow: tr('Прогресс'),
          onBack: () => Navigator.of(context).pop(),
          // The old badge counted down to the end of the calendar month, which
          // is not a season boundary and is not stored anywhere. How far
          // along the path you are is both true and more useful.
          actions: [
            SqBadge('$done / ${kPassRewards.length}',
              tint: AppColors.primary, numeric: true),
          ],
        ),
        const SizedBox(height: 6),
        // The badge counts rewards that were TAKEN, not levels reached. A
        // learner on level five who has tapped nothing sees 0 / 12 and reads
        // it as a broken counter, so the number says what it counts.
        Text(tr('Жоғарыдағы сан — алынған сыйлық саны'),
          style: TextStyle(
            fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
        const SizedBox(height: 16),

        // The current step, and what to do about it. One dark block, one
        // button — the answer to "what now" before anything else on the page.
        _CurrentStep(
          reward: next,
          level: level,
          xp: xp,
          claimable: ready.contains(next),
          onClaim: () async {
            await ref.read(metaProvider.notifier).claimPass(next);
            if (next.xp > 0) {
              await ref.read(profileRepoProvider)
                  .addXp(next.xp, 'mission_${next.level}')
                  .catchError((_) => 0);
              ref.invalidate(myProfileProvider);
            }
            if (context.mounted) {
              sqSnack(context, trp('«{p1}» алынды', {'p1': tr(next.title)}));
            }
          },
          onPlay: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PlaySessionScreen(mode: PlayMode.classic)));
            if (context.mounted) refreshAll(ref);
          },
        ),
        const SizedBox(height: 6),

        if (ready.length > 1) ...[
          const SizedBox(height: 10),
          SqPanel(
            fill: AppColors.soft(AppColors.green, d),
            border: AppColors.line(AppColors.green, d),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const SqTintBox(PhosphorIconsFill.gift,
                  tint: AppColors.green, size: 34, solid: true),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    trp('Тағы {n} сыйлық алуға дайын',
                      {'n': '${ready.length - 1}'}),
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800,
                      color: AppColors.onSoft(AppColors.green, d))),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),

        // The screen drew a path and a price but never said what pays into
        // it, so a first-timer had to guess whether missions wanted their own
        // kind of playing. Folded, like the Arena explainer: there for the
        // one reading, out of the way for everyone else.
        const _HowPanel(),
        const SizedBox(height: 18),

        SqSection(tr('Жол')),
        // The path itself. Drawn top to bottom because that is the direction
        // the page already scrolls — a horizontal map would mean two axes of
        // movement for one journey.
        for (var i = 0; i < kPassRewards.length; i++)
          _PathNode(
            reward: kPassRewards[i],
            index: i,
            last: i == kPassRewards.length - 1,
            state: _stateOf(kPassRewards[i], level, claimed, next),
            xpNeeded: (kPassRewards[i].level * 400 - xp).clamp(0, 1 << 30),
          ),
      ],
    );
  }

  /// Earned is tested before current, and the order is the whole point.
  ///
  /// `next` is simply the first unclaimed reward, so a learner who has passed
  /// its level without tapping anything matched `current` first and read
  /// "0 XP қалды" with no button — the one node they could actually collect
  /// looked like the one node they could not.
  static _NodeState _stateOf(
    PassReward r, int level, Set<int> claimed, PassReward next) {
    if (claimed.contains(r.level)) return _NodeState.claimed;
    if (r.level <= level) return _NodeState.claimable;
    if (r.level == next.level) return _NodeState.current;
    return _NodeState.locked;
  }
}

/// Which nodes are landmarks. Every fourth, plus the last — a ladder with no
/// landmarks is twelve identical rungs, and nothing to aim at between them.
bool _isMilestone(PassReward r) =>
    r.level % 4 == 0 || r.level == kPassRewards.last.level;

IconData _rewardIcon(PassReward r) {
  if (r.grant == null) return PhosphorIconsFill.star;
  if (r.grant!.startsWith('freeze')) return PhosphorIconsFill.snowflake;
  if (r.grant == 'life') return PhosphorIconsFill.heart;
  if (r.grant!.startsWith('frame')) return PhosphorIconsFill.circleHalf;
  if (r.grant!.startsWith('theme')) return PhosphorIconsFill.moonStars;
  return PhosphorIconsFill.gift;
}

// ── How a mission is finished ────────────────────────────────

/// The rules of the path, folded away.
///
/// Same shape as the "Баттл қалай өтеді?" panel on the Arena tab: one line
/// you can ignore, three short steps when you cannot. Three questions were
/// unanswered anywhere in the app — what feeds the bar, why the next node is
/// shut, and why a reward that says "дайын" is not in the inventory.
class _HowPanel extends StatefulWidget {
  const _HowPanel();

  @override
  State<_HowPanel> createState() => _HowPanelState();
}

class _HowPanelState extends State<_HowPanel> {
  bool _how = false;

  static List<(String, String, String)> get _steps => [
    ('1', tr('Кез келген режим'), tr('әр ойын жолды жылжытады')),
    ('2', tr('Әр деңгей келесі қадамды ашады'), tr('кезекпен, аттамай')),
    ('3', tr('Сыйлықты басып ал'), tr('баспасаң, берілмейді')),
  ];

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _how = !_how),
            child: Row(
              children: [
                Icon(PhosphorIconsFill.info,
                  size: 15, color: AppColors.text3(d)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Миссия қалай орындалады?'),
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
                                  Text(_steps[i].$2,
                                    style: TextStyle(
                                      fontSize: 11, height: 1.3,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.text(d))),
                                  const SizedBox(height: 2),
                                  Text(_steps[i].$3,
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

// ── The current step ─────────────────────────────────────────

class _CurrentStep extends StatelessWidget {
  final PassReward reward;
  final int level, xp;
  final bool claimable;
  final Future<void> Function() onClaim;
  final Future<void> Function() onPlay;

  const _CurrentStep({
    required this.reward,
    required this.level,
    required this.xp,
    required this.claimable,
    required this.onClaim,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final target = reward.level * 400;
    final prev = (reward.level - 1) * 400;
    final into = ((xp - prev) / (target - prev)).clamp(0.0, 1.0);
    final need = (target - xp).clamp(0, 1 << 30);

    return SqRise(
      child: SqInkCard(
        padding: const EdgeInsets.all(20),
        glow: claimable ? AppColors.green : AppColors.primary,
        glowAt: Alignment.topRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SqEyebrow(
              claimable ? tr('Алуға дайын') : tr('Қазіргі қадам'),
              color: AppColors.onInk2),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: claimable ? AppColors.green : AppColors.primary,
                    borderRadius: BorderRadius.circular(16)),
                  child: Icon(_rewardIcon(reward),
                    size: 24, color: Colors.white),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr(reward.title),
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          letterSpacing: -0.3, color: Colors.white)),
                      Text(trp('{n}-қадам', {'n': '${reward.level}'}),
                        style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: AppColors.onInk3)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // What it takes, as a number rather than a mood. "Where am I and
            // how much further" is the whole question this screen exists for.
            if (!claimable) ...[
              SqTrack(into, height: 9, background: AppColors.inkTrack),
              const SizedBox(height: 7),
              Text(trp('{n} XP жинасаң ашылады', {'n': '$need'}),
                style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: AppColors.onInk2)),
              const SizedBox(height: 14),
              SqAction(tr('XP жинау'),
                icon: PhosphorIconsFill.play,
                onTap: onPlay),
            ] else ...[
              SqAction(tr('Сыйлықты алу'),
                icon: PhosphorIconsFill.gift,
                tone: SqTone.green,
                onTap: onClaim),
            ],
          ],
        ),
      ),
    );
  }
}

// ── One node on the path ─────────────────────────────────────

class _PathNode extends ConsumerWidget {
  final PassReward reward;
  final int index;
  final bool last;
  final _NodeState state;
  final int xpNeeded;

  const _PathNode({
    required this.reward,
    required this.index,
    required this.last,
    required this.state,
    required this.xpNeeded,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final milestone = _isMilestone(reward);
    final size = milestone ? 56.0 : 44.0;

    final tint = switch (state) {
      _NodeState.claimed   => AppColors.green,
      _NodeState.claimable => AppColors.amber,
      _NodeState.current   => AppColors.primary,
      _NodeState.locked    => AppColors.text4(d),
    };
    final filled = state != _NodeState.locked;

    // The zig-zag. Nodes alternate left and right of centre so the eye follows
    // a line rather than reading a column of rows — the one visual difference
    // between "a path" and "a list".
    final left = index.isEven;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Column(
              children: [
                if (!left) const SizedBox(height: 0),
                Container(
                  width: size, height: size,
                  margin: EdgeInsets.only(
                    left: left ? 0 : 18, right: left ? 18 : 0),
                  decoration: BoxDecoration(
                    color: filled ? tint : AppColors.muted(d),
                    borderRadius: BorderRadius.circular(size * 0.34),
                    border: Border.all(
                      color: state == _NodeState.current
                          ? AppColors.primaryDeep
                          : Colors.transparent,
                      width: 3),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    state == _NodeState.claimed
                        ? PhosphorIconsFill.check
                        : state == _NodeState.locked
                            ? PhosphorIconsFill.lock
                            : _rewardIcon(reward),
                    size: milestone ? 26 : 20,
                    color: filled ? Colors.white : AppColors.text3(d)),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: EdgeInsets.only(
                        left: left ? 0 : 18, right: left ? 18 : 0,
                        top: 4, bottom: 4),
                      color: state == _NodeState.claimed
                          ? AppColors.green
                          : AppColors.divider(d),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: milestone ? 10 : 6, bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(tr(reward.title),
                          style: TextStyle(
                            fontSize: milestone ? 15 : 13.5,
                            fontWeight: FontWeight.w800,
                            color: state == _NodeState.locked
                                ? AppColors.text3(d)
                                : AppColors.text(d))),
                      ),
                      if (milestone) ...[
                        const SizedBox(width: 7),
                        SqBadge(tr('Белес'), tint: AppColors.amber),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // A padlock on its own says "no". A padlock with the price
                  // next to it says "not yet, and here is how far".
                  Text(
                    switch (state) {
                      _NodeState.claimed   => tr('Алынды'),
                      _NodeState.claimable => tr('Алуға дайын'),
                      _NodeState.current   => trp('{n} XP қалды',
                          {'n': '$xpNeeded'}),
                      _NodeState.locked    => trp('{n} XP жинағанда ашылады',
                          {'n': '$xpNeeded'}),
                    },
                    style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w600,
                      color: state == _NodeState.claimable
                          ? AppColors.amberInk
                          : AppColors.text3(d))),

                  if (state == _NodeState.claimable) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 34,
                      child: SqAction(tr('Алу'),
                        height: 34,
                        tone: SqTone.green,
                        onTap: () async {
                          await ref.read(metaProvider.notifier)
                              .claimPass(reward);
                          if (reward.xp > 0) {
                            await ref.read(profileRepoProvider)
                                .addXp(reward.xp, 'mission_${reward.level}')
                                .catchError((_) => 0);
                            ref.invalidate(myProfileProvider);
                          }
                          if (context.mounted) {
                            sqSnack(context, trp('«{p1}» алынды',
                              {'p1': tr(reward.title)}));
                          }
                        }),
                    ),
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
