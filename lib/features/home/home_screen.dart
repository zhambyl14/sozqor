// lib/features/home/home_screen.dart
//
// 4.0 home. One screen, one primary action.
//
// The old home offered five gradient cards of equal weight and left the
// learner to pick. This one answers "what do I do now?" before anything else:
// a single dark block states today's plan and carries the biggest button on
// the screen.
//
// Everything under it is deliberately short. Nothing here explains itself in a
// paragraph — the streak is seven squares, a quest is an icon and a bar, the
// word of the day is a word and a speaker. The word path, friends and the
// weekly report are three icon tiles rather than three cards of prose: same
// destinations, a fraction of the reading.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/profile.dart';
import '../../data/models/word.dart';
import '../../data/repos/profile_repo.dart';
import '../../providers.dart';
import '../../services/meta_store.dart';
import '../../services/sozqor_ai.dart';
import '../../services/speech.dart';
import '../auth/guest_gate.dart';
import '../play/play_session_screen.dart';
import '../profile/friends_screen.dart';
import '../profile/report_screen.dart';
import '../profile/shop_screen.dart';
import '../words/add_word_screen.dart';
import '../words/word_detail_screen.dart';
import 'chest_screen.dart';
import 'missions_screen.dart';
import 'story_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpen());
  }

  /// Once per app session: bump the streak and let the shared brain grow.
  Future<void> _onOpen() async {
    if (_opened) return;
    _opened = true;
    try {
      await ref.read(profileRepoProvider).touchStreak();
      if (mounted) ref.invalidate(myProfileProvider);
    } catch (_) {/* offline is fine */}
    SozQorAI.instance.growInBackground();
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return tr('Қайырлы таң');
    if (h < 18) return tr('Қайырлы күн');
    return tr('Қайырлы кеш');
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) refreshAll(ref);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final profile = ref.watch(myProfileProvider).value;
    final words = ref.watch(myWordsProvider).value ?? const <Word>[];
    final due = ref.watch(dueCountProvider).value ?? 0;
    final quests = ref.watch(questsProvider);
    final meta = ref.watch(metaProvider);
    final claimedQuests =
        ref.watch(dailyProgressProvider).value?.claimed ?? const <String>[];

    return SqPage(
      onRefresh: () async {
        refreshAll(ref);
        ref.invalidate(friendsProvider);
        await Future<void>.delayed(const Duration(milliseconds: 400));
      },
      children: [
        _Greeting(
          greeting: _greeting,
          profile: profile,
          onBell: () => _open(const ReportScreen()),
        ),
        const SizedBox(height: 18),

        const GuestBanner(feature: GuestFeature.saveWord),

        SqRise(child: _TodayPlan(profile: profile, due: due)),
        const SizedBox(height: 16),

        _StreakWeek(
          freezes: meta.freezes,
          onFreeze: () => _open(const ShopScreen()),
          onDayTap: () => _open(const ReportScreen()),
        ),
        const SizedBox(height: 14),

        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _ChestCard(
              meta: meta, onTap: () => _open(const ChestScreen()))),
            const SizedBox(width: 11),
            Expanded(child: _MissionsCard(
              xp: profile?.xp ?? 0,
              onTap: () => _open(const MissionsScreen()))),
          ],
        ),
        const SizedBox(height: 14),

        SqSection(tr('Күнделікті тапсырма'),
          trailingWidget: SqNum(
            '${quests.where((q) => q.done).length}/${quests.length}',
            size: 11, color: AppColors.text3(isDark(context)))),
        SqGroup(children: [
          for (final q in quests)
            _QuestRow(quest: q, claimed: claimedQuests.contains(q.id)),
        ]),
        const SizedBox(height: 18),

        if (words.isNotEmpty)
          _WordOfDay(words: words, onOpen: _open)
        else
          _FirstWordCard(onTap: () => _open(const AddWordScreen())),
        const SizedBox(height: 18),

        // Everything else the app can do lives one tap away instead of being
        // stacked onto the first screen. Three tiles, no prose.
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _Shortcut(
              icon: PhosphorIconsFill.path,
              label: tr('Сөз жолы'),
              tint: AppColors.primary,
              onTap: () => _open(const StoryScreen()))),
            const SizedBox(width: 9),
            Expanded(child: _Shortcut(
              icon: PhosphorIconsFill.usersThree,
              label: tr('Достар'),
              tint: AppColors.sky,
              onTap: () => _open(const FriendsScreen()))),
            const SizedBox(width: 9),
            Expanded(child: _Shortcut(
              icon: PhosphorIconsFill.chartLineUp,
              label: tr('Есеп'),
              tint: AppColors.green,
              onTap: () => _open(const ReportScreen()))),
          ],
        ),
      ],
    );
  }
}

/// A small square entry point. Icon plus one word — the least text a
/// navigation target can carry and still be understood.
class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _Shortcut({
    required this.icon, required this.label,
    required this.tint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqLip(
      fill: AppColors.card(d),
      border: AppColors.border(d),
      lip: AppColors.surfaceLip(d),
      depth: 3,
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: tint),
          const SizedBox(height: 7),
          Text(label,
            style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w800,
              color: AppColors.text(d))),
        ],
      ),
    );
  }
}

// ── Greeting row ───────────────────────────────────────────

class _Greeting extends ConsumerWidget {
  final String greeting;
  final Profile? profile;
  final VoidCallback onBell;

  const _Greeting({
    required this.greeting, required this.profile, required this.onBell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final streak = profile?.streak ?? 0;
    final frame = ref.watch(metaProvider).frame;

    return Row(
      children: [
        SqLip(
          fill: AppColors.primary,
          lip: AppColors.primaryDeep,
          depth: 3,
          radius: 16,
          child: Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: frame.isEmpty
                  ? null
                  : Border.all(
                      color: frame == 'frame_gold'
                          ? AppColors.amber : AppColors.green,
                      width: 2.5),
            ),
            alignment: Alignment.center,
            child: SqNum(
              sqInitial(profile?.name),
              size: 19, color: Colors.white),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SqEyebrow(greeting),
              const SizedBox(height: 1),
              Text(profile?.name ?? '…',
                style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800,
                  letterSpacing: -0.45, color: AppColors.text(d))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.soft(AppColors.amber, d),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.line(AppColors.amber, d)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                streak > 0 ? PhosphorIconsFill.fire : PhosphorIconsBold.fire,
                size: 15,
                color: streak > 0 ? AppColors.amber : AppColors.text4(d)),
              const SizedBox(width: 5),
              SqNum('$streak',
                size: 14, color: AppColors.onSoft(AppColors.amber, d)),
            ],
          ),
        ),
        const SizedBox(width: 9),
        SqSquareButton(PhosphorIconsFill.chartLineUp,
          size: 40, onTap: onBell),
      ],
    );
  }
}

// ── Today's plan: the one dark block ───────────────────────

class _TodayPlan extends ConsumerWidget {
  final Profile? profile;
  final int due;
  const _TodayPlan({required this.profile, required this.due});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(dailyProgressProvider).value;
    final reviewed = progress?.wordsReviewed ?? 0;
    final goal = (profile?.dailyGoal ?? 10).clamp(1, 500);
    final ratio = (reviewed / goal).clamp(0.0, 1.0);
    final left = (goal - reviewed).clamp(0, goal);
    final minutes = (left * 0.65).ceil().clamp(1, 90);
    final beads = goal.clamp(4, 10);
    final beadsDone = (ratio * beads).round();

    return SqInkCard(
      padding: const EdgeInsets.all(20),
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
                    SqEyebrow(tr('Бүгінгі жоспар'),
                      color: AppColors.onInk2),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        SqCountUp(reviewed,
                          size: 36, color: Colors.white),
                        const SizedBox(width: 5),
                        Text(trp('/ {n} сөз', {'n': '$goal'}),
                          style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700,
                            color: AppColors.onInk3)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      left == 0
                          ? tr('Бүгінгі мақсат орындалды — жарайсың!')
                          : trp('{n} сөз қалды — шамамен {m} минут',
                              {'n': '$left', 'm': '$minutes'}),
                      style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600,
                        height: 1.35, color: AppColors.onInk2)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SqRing(
                value: ratio,
                size: 58,
                stroke: 7,
                color: left == 0 ? AppColors.green : AppColors.primary,
                track: AppColors.inkTrack,
                child: SqNum('${(ratio * 100).round()}%',
                  size: 13, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SqBeads(
            total: beads,
            done: beadsDone,
            doneColor: AppColors.primary,
            pending: AppColors.inkTrack,
          ),
          const SizedBox(height: 16),
          SqAction(
            due > 0 ? tr('Жалғастыру') : tr('Жаттығуды бастау'),
            icon: PhosphorIconsFill.play,
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlaySessionScreen(
                  mode: due > 0 ? PlayMode.review : PlayMode.classic)));
              if (context.mounted) refreshAll(ref);
            },
          ),
        ],
      ),
    );
  }
}

// ── Weekly streak strip ────────────────────────────────────

class _StreakWeek extends ConsumerWidget {
  final int freezes;
  final VoidCallback onFreeze;
  final VoidCallback onDayTap;
  const _StreakWeek({
    required this.freezes, required this.onFreeze, required this.onDayTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final week = ref.watch(weekStatsProvider).value ?? const <DayStat>[];

    return SqPanel(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(tr('Апталық серия'),
                style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800,
                  color: AppColors.text(d))),
              const Spacer(),
              SqChip(
                freezes > 0
                    ? trp('Мұздату × {n}', {'n': '$freezes'})
                    : tr('Мұздатқыш ал'),
                icon: PhosphorIconsFill.snowflake,
                tint: AppColors.sky,
                radius: 999,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                onTap: onFreeze,
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (week.isEmpty)
            const SqShimmer(height: 52, margin: EdgeInsets.zero)
          else
            Row(
              children: [
                for (var i = 0; i < week.length; i++) ...[
                  Expanded(child: _DayCell(stat: week[i], onTap: onDayTap)),
                  if (i != week.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DayStat stat;
  final VoidCallback onTap;
  const _DayCell({required this.stat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final active = stat.isToday;
    final done = stat.xp > 0;

    late final Color bg, edge, ink, label;
    late final IconData icon;
    if (active) {
      bg = AppColors.primary;
      edge = AppColors.primary;
      ink = Colors.white;
      label = d ? AppColors.primary : AppColors.primaryDeep;
      icon = done ? PhosphorIconsFill.fire : PhosphorIconsBold.target;
    } else if (done) {
      bg = AppColors.soft(AppColors.green, d);
      edge = AppColors.line(AppColors.green, d);
      ink = AppColors.greenDeep;
      label = AppColors.text3(d);
      icon = PhosphorIconsFill.check;
    } else {
      bg = AppColors.muted(d);
      edge = AppColors.border(d);
      ink = AppColors.text4(d);
      label = AppColors.text4(d);
      icon = PhosphorIconsBold.minus;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: edge),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 15, color: ink),
            ),
          ),
          const SizedBox(height: 6),
          Text(stat.label,
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: label)),
        ],
      ),
    );
  }
}

// ── Chest + missions pair ──────────────────────────────────

class _ChestCard extends StatelessWidget {
  final MetaState meta;
  final VoidCallback onTap;
  const _ChestCard({required this.meta, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ready = meta.chestReady;
    final d = isDark(context);
    // The resting state used AppColors.muted as its fill, and in the light
    // theme mutedL is 0xFFF7F6FB — the exact same value as bgL, the page
    // behind it. Contrast ratio 1.00: the card was not dim, it was invisible,
    // which is why this button looked like it had no colour at all. Dark mode
    // hid the bug, because there mutedD and bgD genuinely differ.
    //
    // A card surface with a real outline reads as a button in both themes
    // without pretending the chest is ready.
    return SqLip(
      fill: ready ? AppColors.amber : AppColors.card(d),
      lip: ready ? AppColors.amberDeep : AppColors.border(d),
      border: ready ? null : AppColors.border(d),
      radius: 20,
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ready
                  ? const SqFloat(
                      child: Icon(PhosphorIconsFill.gift,
                        size: 26, color: Colors.white))
                  : Icon(PhosphorIconsFill.gift,
                      size: 26, color: AppColors.text4(d)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: ready
                      ? Colors.black.withValues(alpha: 0.18)
                      : AppColors.card(isDark(context)),
                  borderRadius: BorderRadius.circular(6)),
                child: SqNum(
                  ready ? tr('ДАЙЫН') : _untilMidnight(),
                  size: 9.5,
                  color: ready
                      ? Colors.white : AppColors.text3(isDark(context))),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(tr('Сыйлық сандығы'),
            style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800,
              color: ready ? Colors.white : AppColors.text(isDark(context)))),
          Text(
            ready
                ? trp('{n}-күн қатарынан', {'n': '${meta.nextChestStreak}'})
                : tr('Ертең жаңасы келеді'),
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: ready
                  ? Colors.white.withValues(alpha: 0.85)
                  : AppColors.text3(isDark(context)))),
        ],
      ),
    );
  }

  static String _untilMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    final d = next.difference(now);
    return '${d.inHours.toString().padLeft(2, '0')}:'
        '${(d.inMinutes % 60).toString().padLeft(2, '0')}';
  }
}

class _MissionsCard extends StatelessWidget {
  final int xp;
  final VoidCallback onTap;
  const _MissionsCard({required this.xp, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final level = passLevelFor(xp);
    return SqLip(
      fill: AppColors.card(d),
      border: AppColors.border(d),
      lip: AppColors.surfaceLip(d),
      depth: 3,
      radius: 20,
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsFill.medal,
                size: 26, color: AppColors.primary),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.soft(AppColors.primary, d),
                  borderRadius: BorderRadius.circular(6)),
                child: SqNum('LVL $level',
                  size: 9.5, color: AppColors.onSoft(AppColors.primary, d)),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(tr('Миссия жолы'),
            style: TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800,
              color: AppColors.text(d))),
          const SizedBox(height: 7),
          SqTrack(passProgressFor(xp)),
        ],
      ),
    );
  }
}

// ── Quest row ──────────────────────────────────────────────

class _QuestRow extends ConsumerStatefulWidget {
  final Quest quest;
  /// Whether this quest's reward was already claimed today
  /// (`DailyProgress.claimed`, kept server-side).
  final bool claimed;
  const _QuestRow({required this.quest, required this.claimed});

  @override
  ConsumerState<_QuestRow> createState() => _QuestRowState();
}

class _QuestRowState extends ConsumerState<_QuestRow> {
  bool _busy = false;

  Future<void> _claim() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(profileRepoProvider);
    try {
      await repo.markQuestClaimed(widget.quest.id);
      await repo.addXp(widget.quest.xp, 'quest_${widget.quest.id}')
          .catchError((_) => 0);
    } catch (_) {
      // the meta layer must not stop the user; the row simply stays claimable
    }
    ref.invalidate(dailyProgressProvider);
    ref.invalidate(myProfileProvider);
    if (mounted) {
      sqSnack(context, trp('+{xp} XP алынды!', {'xp': '${widget.quest.xp}'}));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final quest = widget.quest;
    final canClaim = quest.done && !widget.claimed && !_busy;
    // A claimed quest collapses to a tick. An open one shows a bar and a
    // count. A done-but-unclaimed one offers a tap to collect its XP — the
    // whole reason the daily loop pays out.
    return SqTile(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      leading: SqTintBox(
        quest.done ? PhosphorIconsFill.checkCircle : quest.icon,
        tint: quest.done ? AppColors.green : quest.tint,
        size: 32),
      title: quest.title,
      titleColor: quest.done && widget.claimed
          ? AppColors.text4(d) : AppColors.text(d),
      strike: quest.done && widget.claimed,
      below: quest.done
          ? null
          : SqTrack(quest.progress, color: quest.tint, height: 5),
      trailing: canClaim
          ? SqBadge(tr('Алу'), tint: AppColors.green, solid: true)
          : SqNum('${quest.current}/${quest.target}',
              size: 11.5,
              color: quest.done ? AppColors.green : AppColors.text3(d)),
      onTap: canClaim ? _claim : null,
    );
  }
}

// ── Word of the day ────────────────────────────────────────

class _WordOfDay extends ConsumerWidget {
  final List<Word> words;
  final Future<void> Function(Widget) onOpen;
  const _WordOfDay({required this.words, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final w = words[Random(seed).nextInt(words.length)];
    final lang = ref.watch(nativeLangProvider);

    // One line of content and one speaker button. The definition, the level
    // badge and the second action all lived here in the first cut and turned
    // a nice moment into another paragraph — they are on the word card, one
    // tap away, where someone who actually wants them will look.
    return SqPanel(
      padding: const EdgeInsets.fromLTRB(17, 15, 15, 15),
      onTap: () => onOpen(WordDetailScreen(word: w)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SqEyebrow(tr('Күннің сөзі')),
                const SizedBox(height: 5),
                Text(w.en,
                  style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800,
                    letterSpacing: -0.7, color: AppColors.text(d))),
                Text(w.native(lang),
                  style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SqSquareButton(PhosphorIconsFill.speakerHigh,
            size: 46,
            fill: AppColors.inkBlock(d),
            lip: AppColors.inkBlockLip(d),
            iconColor: Colors.white,
            onTap: () => Speech.instance.say(
              w.en.toLowerCase().startsWith('to ')
                  ? w.en.substring(3) : w.en)),
        ],
      ),
    );
  }
}

class _FirstWordCard extends StatelessWidget {
  final VoidCallback onTap;
  const _FirstWordCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return SqPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SqEyebrow(tr('Бірінші қадам')),
          const SizedBox(height: 8),
          Text(tr('Алғашқы сөзіңді қос'),
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800,
              letterSpacing: -0.4, color: AppColors.text(d))),
          const SizedBox(height: 6),
          Text(tr('Қай тілде жазсаң да, қалғанын өзі толтырады.'),
            style: TextStyle(
              fontSize: 12.5, height: 1.5, fontWeight: FontWeight.w600,
              color: AppColors.text3(d))),
          const SizedBox(height: 14),
          SqAction(tr('Сөз қосу'),
            icon: PhosphorIconsBold.plus, height: 48, onTap: onTap),
        ],
      ),
    );
  }
}

