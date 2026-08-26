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


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../core/constants/game_meta.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sq.dart';
import '../../data/models/dict_entry.dart';
import '../../data/models/profile.dart';
import '../../data/models/word.dart';
import '../../data/repos/profile_repo.dart';
import '../../data/supa.dart';
import '../../providers.dart';
import '../../services/meta_store.dart';
import '../../services/sozqor_ai.dart';
import '../arena/leaderboard_screen.dart';
import '../events/events_screen.dart';
import '../auth/guest_gate.dart';
import '../play/play_session_screen.dart';
import '../profile/friends_screen.dart';
import '../profile/report_screen.dart';
import '../profile/shop_screen.dart';
import '../words/add_word_screen.dart';
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

  /// The streak, its week and its freezes — the whole of EN-7 in one sheet,
  /// opened from the fire chip that used to be only a number.
  Future<void> _openStreak() async {
    final p = ref.read(myProfileProvider).valueOrNull;
    await showModalBottomSheet<void>(
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
              Text(tr('Күнделікті серия'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.text(isDark(context)))),
              const SizedBox(height: 18),
              _StreakSheet(
                streak: p?.streak ?? 0,
                bestStreak: p?.bestStreak ?? 0,
                freezes: ref.read(metaProvider).freezes,
                onFreeze: () {
                  Navigator.of(context).pop();
                  _open(const ShopScreen());
                },
                onDayTap: () {
                  Navigator.of(context).pop();
                  _open(const ReportScreen());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(langProvider); // repaint on a language switch
    final profile = ref.watch(myProfileProvider).valueOrNull;
    final words = ref.watch(myWordsProvider).valueOrNull ?? const <Word>[];
    final due = ref.watch(dueCountProvider).valueOrNull ?? 0;
    final quests = ref.watch(questsProvider);
    final meta = ref.watch(metaProvider);
    final dailyWord = ref.watch(dailyWordProvider);
    final claimedQuests =
        ref.watch(dailyProgressProvider).valueOrNull?.claimed ?? const <String>[];

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
          // EN-7 / KK-1: the seven-day strip used to sit on the page as its
          // own "Апталық серия" panel while the fire chip counted the same
          // streak two centimetres above it. There is one streak, so there is
          // one place to read it — behind the chip.
          onStreak: _openStreak,
        ),
        const SizedBox(height: 18),

        const GuestBanner(feature: GuestFeature.saveWord),

        // EN-6: Today's Plan is the whole daily hub. The quest checklist, the
        // daily challenge and the current mission step live inside the card
        // itself rather than as separate blocks around it — the plan, then
        // the checklist that makes it up, with nothing to tap open first.
        SqRise(child: _TodayPlan(
          profile: profile,
          due: due,
          quests: quests,
          claimedQuests: claimedQuests,
        )),
        const SizedBox(height: 14),

        // The two things the day GIVES you, side by side: a chest to open
        // and a word to take. They were a full-width card each, which made
        // the first screen a column of large blocks you had to scroll past to
        // reach anything you could actually do.
        if (dailyWord != null)
          SqEqualRow(
            children: [
              Expanded(child: _ChestCard(
                meta: meta,
                compact: true,
                onTap: () => _open(const ChestScreen()))),
              const SizedBox(width: 9),
              Expanded(child: _WordOfDayTile(
                key: ValueKey(dailyWord.id), entry: dailyWord)),
            ],
          )
        else ...[
          _ChestCard(meta: meta, onTap: () => _open(const ChestScreen())),
          if (words.isEmpty) ...[
            const SizedBox(height: 14),
            _FirstWordCard(onTap: () => _open(const AddWordScreen())),
          ],
        ],
        const SizedBox(height: 18),

        // Everything else the app can do lives one tap away instead of being
        // stacked onto the first screen. Three tiles, no prose.
        SqEqualRow(
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
            // Events moved off the Arena, which is about the rating and the
            // modes that move it. They belong where the day starts.
            Expanded(child: _Shortcut(
              icon: PhosphorIconsFill.confetti,
              label: tr('Ивенттер'),
              tint: AppColors.green,
              onTap: () => _open(const EventsScreen()))),
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
  final VoidCallback onStreak;

  const _Greeting({
    required this.greeting,
    required this.profile,
    required this.onBell,
    required this.onStreak,
  });

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
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onStreak,
          child: Container(
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
        ),
        const SizedBox(width: 9),
        SqSquareButton(PhosphorIconsFill.chartLineUp,
          size: 40, onTap: onBell),
      ],
    );
  }
}

// ── Today's plan: the one dark block ───────────────────────

class _TodayPlan extends ConsumerStatefulWidget {
  final Profile? profile;
  final int due;
  final List<Quest> quests;
  final List<String> claimedQuests;
  const _TodayPlan({
    required this.profile,
    required this.due,
    required this.quests,
    required this.claimedQuests,
  });

  @override
  ConsumerState<_TodayPlan> createState() => _TodayPlanState();
}

class _TodayPlanState extends ConsumerState<_TodayPlan> {
  /// Null until the learner opens or closes the checklist themselves.
  ///
  /// Six rows of it was most of the first screen, so the goal — the thing the
  /// card is actually for — began below the fold. Folded, the count in the
  /// header says everything the rows said at a glance.
  ///
  /// The one case it must not stay folded for is a finished quest whose
  /// reward is still sitting there uncollected: a fold that hides a button
  /// nobody knows about loses the learner their тәжірибе. So the default
  /// follows the rewards, and an explicit tap overrides it either way.
  bool? _openList;

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final due = widget.due;
    final quests = widget.quests;
    final claimedQuests = widget.claimedQuests;
    final d = isDark(context);
    final progress = ref.watch(dailyProgressProvider).valueOrNull;
    final reviewed = progress?.wordsReviewed ?? 0;
    final goal = (profile?.dailyGoal ?? 10).clamp(1, 500);
    final ratio = (reviewed / goal).clamp(0.0, 1.0);
    final left = (goal - reviewed).clamp(0, goal);
    final minutes = (left * 0.65).ceil().clamp(1, 90);
    final beads = goal.clamp(4, 10);
    final beadsDone = (ratio * beads).round();

    final playedDaily = ref.watch(playedDailyProvider).valueOrNull ?? false;
    final claimable = quests
        .any((q) => q.done && !claimedQuests.contains(q.id));
    final openList = _openList ?? claimable;
    final doneCount =
        quests.where((q) => q.done).length + (playedDaily ? 1 : 0);
    final total = quests.length + 1;

    // The mission line reads the path from the same two sources
    // missions_screen.dart reads, so the step named here is the step that
    // screen opens on — a second copy of the maths would drift.
    final xp = profile?.xp ?? 0;
    final passClaimed = ref.watch(metaProvider).passClaimed;
    final mission = kPassRewards.firstWhere(
      (r) => !passClaimed.contains(r.level),
      orElse: () => kPassRewards.last);
    final missionReady = mission.level <= passLevelFor(xp);
    final missionInto =
        ((xp - (mission.level - 1) * 400) / 400).clamp(0.0, 1.0);

    // Every row of today's work — the goal, the checklist, the daily
    // challenge, the mission step — is one block. The checklist used to hang
    // under the card as its own white group, which read as a second, unnamed
    // topic sitting between the plan and the rest of the page.
    final rows = <Widget>[
      for (final q in quests)
        _QuestRow(quest: q, claimed: claimedQuests.contains(q.id)),
      // EN-6: the daily challenge belongs to the plan. Arena keeps its tile
      // as a link to the results board, but the place you are told to play it
      // is here, with everything else due today.
      _PlanRow(
        icon: playedDaily
            ? PhosphorIconsFill.checkCircle
            : PhosphorIconsFill.globeHemisphereEast,
        tint: playedDaily ? AppColors.green : AppColors.sky,
        title: tr('Күнделікті сынақ'),
        done: playedDaily,
        trailing: playedDaily
            ? SqNum(tr('Нәтижені көр'), size: 11.5, color: AppColors.onInk3)
            : SqBadge(tr('Ойнау'), tint: AppColors.sky, solid: true),
        onTap: () async {
          if (playedDaily) {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LeaderboardScreen(
                initialTab: LeaderboardTab.daily)));
            return;
          }
          if (!await requireAccount(context, ref, GuestFeature.daily)) return;
          if (!context.mounted) return;
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const PlaySessionScreen(mode: PlayMode.daily)));
          if (context.mounted) {
            ref.invalidate(playedDailyProvider);
            refreshAll(ref);
          }
        },
      ),
      // The mission is today's work too. It used to be a card of its own two
      // rows further down, repeating a level and a bar nobody connected to
      // the plan; here it names the step that is actually next.
      _PlanRow(
        icon: PhosphorIconsFill.medal,
        tint: AppColors.amber,
        title: trp('Миссия: {p1}', {'p1': tr(mission.title)}),
        note: trp('{n}-қадам', {'n': '${mission.level}'}),
        bar: missionReady ? null : missionInto,
        trailing: missionReady
            ? SqBadge(tr('Алуға дайын'), tint: AppColors.green, solid: true)
            : SqNum('${(missionInto * 100).round()}%',
                size: 11.5, color: AppColors.onInk2),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MissionsScreen()));
          if (context.mounted) refreshAll(ref);
        },
      ),
    ];

    return SqInkCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
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

          // The checklist is the lower half of the same block: a hairline,
          // not a gap wide enough to look like a new topic. Everything the
          // learner owes today is one thing to look at.
          const SizedBox(height: 16),
          InkWell(
            onTap: () => setState(() => _openList = !openList),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SqEyebrow(tr('Бүгінгі тізім'), color: AppColors.onInk3),
                  if (claimable && !openList) ...[
                    const SizedBox(width: 7),
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.amber, shape: BoxShape.circle)),
                  ],
                  const Spacer(),
                  SqNum('$doneCount/$total',
                    size: 11.5, color: AppColors.onInk2),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: openList ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(PhosphorIconsBold.caretDown,
                      size: 14, color: AppColors.onInk3),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: openList
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i != 0)
                          Container(
                            height: 1, color: AppColors.inkBlockTrack(d)),
                        rows[i],
                      ],
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),

          if (doneCount == total) ...[
            const SizedBox(height: 4),
            Center(
              child: SqChip(
                tr('Бүгінгі жоспар толық орындалды'),
                icon: PhosphorIconsFill.confetti,
                tint: AppColors.green,
                radius: 999,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of today's checklist, drawn for the dark plan block.
///
/// SqTile is the row idiom everywhere else, but every colour it reaches for
/// comes from AppColors.text*, which disappears on ink. Now that the checklist
/// lives inside the plan card rather than in a white group under it, the row
/// is restated here in the block's own palette instead of handing SqTile six
/// colour overrides it was never built to take.
class _PlanRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  /// A second line under the title — only the mission row needs one.
  final String? note;
  /// Struck through and dimmed: the row is finished and settled.
  final bool done;
  /// Progress bar under the title, or null when there is nothing left to fill.
  final double? bar;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _PlanRow({
    required this.icon,
    required this.tint,
    required this.title,
    this.note,
    this.done = false,
    this.bar,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: done ? 0.16 : 0.26),
                borderRadius: BorderRadius.circular(11)),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                    style: TextStyle(
                      fontSize: 13, height: 1.3, fontWeight: FontWeight.w800,
                      color: done ? AppColors.onInk3 : Colors.white,
                      decorationColor: AppColors.onInk3,
                      decoration: done
                          ? TextDecoration.lineThrough
                          : TextDecoration.none)),
                  if (note != null)
                    Text(note!,
                      style: const TextStyle(
                        fontSize: 11, height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onInk3)),
                  if (bar != null) ...[
                    const SizedBox(height: 7),
                    SqTrack(bar!,
                      color: tint, height: 5,
                      background: AppColors.inkBlockTrack(d)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}

// ── Weekly streak strip ────────────────────────────────────

/// The one streak surface (EN-7 / KK-1).
///
/// 4.0 spread the same idea over three places at once: a fire chip counting
/// `profiles.streak`, an "Апталық серия" panel drawing the same seven days
/// underneath it, and a third, purely local count on the chest card. The
/// panel is now the body of this sheet, reached from the chip, so the number
/// and the days that produced it are read in one place.
class _StreakSheet extends ConsumerWidget {
  final int streak;
  final int bestStreak;
  final int freezes;
  final VoidCallback onFreeze;
  final VoidCallback onDayTap;

  const _StreakSheet({
    required this.streak,
    required this.bestStreak,
    required this.freezes,
    required this.onFreeze,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = isDark(context);
    final week = ref.watch(weekStatsProvider).valueOrNull ?? const <DayStat>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Icon(
              streak > 0 ? PhosphorIconsFill.fire : PhosphorIconsBold.fire,
              size: 26,
              color: streak > 0 ? AppColors.amber : AppColors.text4(d)),
            const SizedBox(width: 8),
            SqCountUp(streak, size: 40, color: AppColors.text(d)),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          trp('Ең ұзақ сериям: {n} күн', {'n': '$bestStreak'}),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w600,
            color: AppColors.text3(d))),
        const SizedBox(height: 18),
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
        const SizedBox(height: 16),
        SqChip(
          freezes > 0
              ? trp('Мұздату × {n}', {'n': '$freezes'})
              : tr('Мұздатқыш ал'),
          icon: PhosphorIconsFill.snowflake,
          tint: AppColors.sky,
          radius: 999,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onTap: onFreeze,
        ),
      ],
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

  /// Half a row rather than the whole of one. The streak line is the first
  /// thing to go: at this width it wraps to three lines and pushes the card
  /// taller than the tile beside it.
  final bool compact;

  const _ChestCard({
    required this.meta, required this.onTap, this.compact = false});

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
          if (!compact) Text(
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
      sqSnack(context, trp('+{xp} тәжірибе алынды!', {'xp': '${widget.quest.xp}'}));
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quest = widget.quest;
    final canClaim = quest.done && !widget.claimed && !_busy;
    // A claimed quest collapses to a tick. An open one shows a bar and a
    // count. A done-but-unclaimed one offers a tap to collect its XP — the
    // whole reason the daily loop pays out.
    return _PlanRow(
      icon: quest.done ? PhosphorIconsFill.checkCircle : quest.icon,
      tint: quest.done ? AppColors.green : quest.tint,
      title: quest.title,
      done: quest.done && widget.claimed,
      bar: quest.done ? null : quest.progress,
      trailing: canClaim
          ? SqBadge(tr('Алу'), tint: AppColors.green, solid: true)
          : SqNum('${quest.current}/${quest.target}',
              size: 11.5,
              color: quest.done ? AppColors.green : AppColors.onInk2),
      onTap: canClaim ? _claim : null,
    );
  }
}

// ── Word of the day ────────────────────────────────
//
// The full-width card is gone. It shared the first screen with the chest,
// two large blocks stacked, and the learner scrolled past both to reach
// anything they could act on. _WordOfDayTile at the foot of this file is
// what replaced it: half a row, the word, and the one button that matters.

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

/// The word of the day when it has to share a row with the chest.
///
/// The full card carries a definition, an example and a pronounce button;
/// none of that fits in half a row and none of it is the point here. The
/// point is a word you do not have and one tap to take it — everything else
/// is on the word's own screen, which is what tapping the tile opens.
class _WordOfDayTile extends ConsumerStatefulWidget {
  final DictEntry entry;
  const _WordOfDayTile({super.key, required this.entry});

  @override
  ConsumerState<_WordOfDayTile> createState() => _WordOfDayTileState();
}

class _WordOfDayTileState extends ConsumerState<_WordOfDayTile> {
  bool _busy = false;
  bool _saved = false;

  Future<void> _add() async {
    if (_busy || _saved) return;
    if (!await requireAccount(context, ref, GuestFeature.saveWord)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    final e = widget.entry;
    try {
      final repo = ref.read(wordsRepoProvider);
      // Asked of the server rather than of the loaded list: the bank is paged,
      // so its in-memory copy is only the pages scrolled so far and a word
      // sitting on an unread page would be called new.
      final already = await repo.exists(e.kk, e.en);
      if (!already) {
        await repo.addFromDict(e);
        await ref.read(profileRepoProvider).bumpWordsAdded();
        refreshAll(ref);
      }
      if (mounted) {
        setState(() => _saved = true);
        sqSnack(context, already
            ? tr('Бұл сөз сөздігіңде бар')
            : tr('Сөздікке қосылды'));
      }
    } catch (err) {
      if (mounted) sqSnack(context, humanError(err), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = isDark(context);
    final e = widget.entry;
    final lang = ref.watch(nativeLangProvider);

    return SqLip(
      fill: AppColors.card(d),
      border: AppColors.border(d),
      lip: AppColors.surfaceLip(d),
      depth: 3,
      radius: 20,
      padding: const EdgeInsets.all(15),
      // No onTap to a detail screen: WordDetailScreen takes a Word, and this
      // is a dictionary row the learner does not own yet. Adding it is the
      // whole interaction, and that is the button below.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(e.emoji ?? '✨', style: const TextStyle(fontSize: 22)),
              const Spacer(),
              SqBadge(e.cefr, tint: AppColors.sky, size: 9.5),
            ],
          ),
          const SizedBox(height: 9),
          Text(tr('Күн сөзі'),
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.text4(d))),
          Text(e.en,
            style: TextStyle(
              fontSize: 15, height: 1.2, fontWeight: FontWeight.w800,
              color: AppColors.text(d))),
          Text(e.native(lang),
            style: TextStyle(
              fontSize: 12, height: 1.3, fontWeight: FontWeight.w600,
              color: AppColors.text3(d))),
          const SizedBox(height: 10),
          SqLip(
            fill: _saved ? AppColors.muted(d) : AppColors.primary,
            lip: _saved ? AppColors.surfaceLip(d) : AppColors.primaryDeep,
            depth: 3,
            radius: 12,
            padding: const EdgeInsets.symmetric(vertical: 9),
            onTap: _saved || _busy ? null : _add,
            child: Center(
              child: Text(_saved ? tr('Қосылды') : tr('Сөздікке қосу'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w800,
                  color: _saved ? AppColors.text3(d) : Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
