// lib/providers.dart
//
// Every Riverpod provider in one place so screens have a single import and
// the dependency graph stays easy to read.

import 'dart:math' show Random;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/game_meta.dart';
import 'core/i18n/l10n.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/sq.dart' show sqHexColor;
import 'data/models/app_event.dart';
import 'data/models/battle.dart';
import 'data/models/dict_entry.dart';
import 'data/models/profile.dart';
import 'data/models/word.dart';
import 'data/repos/auth_repo.dart';
import 'data/repos/battle_repo.dart';
import 'data/repos/board_repo.dart';
import 'data/repos/cosmetics_repo.dart';
import 'data/repos/dictionary_repo.dart';
import 'data/repos/events_repo.dart';
import 'data/repos/profile_repo.dart';
import 'data/repos/words_repo.dart';
import 'data/supa.dart';
import 'services/meta_store.dart';

// Interface language: re-exported so every screen that already imports
// providers.dart gets tr(), trp() and langProvider without a second import.
export 'core/i18n/l10n.dart';

// ── Repositories ───────────────────────────────────────────
final authRepoProvider    = Provider((_) => AuthRepo());
final profileRepoProvider = Provider((_) => ProfileRepo());
final wordsRepoProvider   = Provider((_) => WordsRepo());
final dictRepoProvider    = Provider((_) => DictionaryRepo());
final battleRepoProvider  = Provider((_) => BattleRepo());
final boardRepoProvider   = Provider((_) => BoardRepo());
final cosmeticsRepoProvider = Provider((_) => CosmeticsRepo());

/// The shop catalogue, with this learner's ownership folded in. Watched by
/// the shop itself and by anything that has to turn an equipped item id into
/// a colour — the catalogue is the only place that mapping exists, since it
/// lives server-side so new items need no app release.
final shopCatalogueProvider = FutureProvider<List<Cosmetic>>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(cosmeticsRepoProvider).catalogue();
});

/// Colour of the frame a learner is wearing, or null when they wear none.
final myFrameColorProvider = Provider<Color?>((ref) {
  final id = ref.watch(myProfileProvider).valueOrNull?.equippedFrame;
  if (id == null || id.isEmpty) return null;
  final items = ref.watch(shopCatalogueProvider).valueOrNull ?? const <Cosmetic>[];
  for (final c in items) {
    if (c.id == id) return sqHexColor(c.color);
  }
  return null;
});

/// Everything *this* learner is wearing, in the same shape used to render
/// anybody else on a board.
///
/// Assembled from the catalogue rather than fetched again — the shop response
/// already carries every id, colour and emoji, and the catalogue is the only
/// place that id → payload mapping exists, since it lives server-side so new
/// items ship without an app release. Before this the app read two of the six
/// equip slots, so a badge, a banner or an aura was invisible even to the
/// person who bought it.
final myWornProvider = Provider<WornCosmetics>((ref) {
  final p = ref.watch(myProfileProvider).valueOrNull;
  final items = ref.watch(shopCatalogueProvider).valueOrNull ?? const <Cosmetic>[];
  if (p == null || items.isEmpty) return const WornCosmetics();

  Cosmetic? find(String id) {
    if (id.isEmpty) return null;
    for (final c in items) {
      if (c.id == id) return c;
    }
    return null;
  }

  // The free default of each kind is the "wearing nothing" option, so it must
  // not render as a title or paint a banner.
  final title = find(p.equippedTitle);
  final worn = title == null || title.isDefault ? null : title;

  return WornCosmetics(
    frameId:     p.equippedFrame.isEmpty ? null : p.equippedFrame,
    frameColor:  find(p.equippedFrame)?.color,
    titleKk:     worn?.nameKk,
    titleRu:     worn?.nameRu,
    bannerColor: find(p.equippedBanner)?.color,
    badgeEmoji:  find(p.equippedBadge)?.emoji,
    auraColor:   find(p.equippedAura)?.color,
  );
});

/// The title a learner is wearing, already in the interface language.
final myTitleProvider = Provider<String?>((ref) {
  final id = ref.watch(myProfileProvider).valueOrNull?.equippedTitle;
  if (id == null || id.isEmpty) return null;
  final items = ref.watch(shopCatalogueProvider).valueOrNull ?? const <Cosmetic>[];
  for (final c in items) {
    if (c.id == id) return c.isDefault ? null : c.name;
  }
  return null;
});

// ── Session ────────────────────────────────────────────────
final authChangesProvider = StreamProvider<AuthState>(
    (ref) => ref.watch(authRepoProvider).changes);

final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authChangesProvider);
  return supa.auth.currentSession;
});

/// The signed-in user's profile. Everything that shows XP, level, streak or
/// avatar watches this, so a single refresh updates the whole app.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authChangesProvider);
  return ref.watch(profileRepoProvider).me();
});

/// Level band the learner should be shown content from.
final visibleLevelsProvider = Provider<List<String>>((ref) {
  final p = ref.watch(myProfileProvider).valueOrNull;
  return visibleCefrFor(p?.cefrLevel ?? 'A1');
});

final myKindsProvider = Provider<List<QKind>>((ref) {
  final p = ref.watch(myProfileProvider).valueOrNull;
  return kindsFor(p?.cefrLevel ?? 'A1');
});

/// Which own-language side ('kk' or 'ru') the learner trains against.
///
/// 5.0 collapses the two language settings into one: there is no longer an
/// "interface language" that can disagree with a "learning language". A
/// learner who picked Russian reads Russian buttons *and* is asked Russian →
/// English, never one of each. The profile still carries `native_lang` and it
/// is still written, but it now only ever mirrors the chosen app language —
/// nothing reads it as an independent setting.
final nativeLangProvider = Provider<String>((ref) => ref.watch(langProvider));

// ── Theme ──────────────────────────────────────────────────
class ThemeCtrl extends StateNotifier<ThemeMode> {
  ThemeCtrl() : super(ThemeMode.light);
  void set(bool dark) => state = dark ? ThemeMode.dark : ThemeMode.light;
  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeProvider =
    StateNotifierProvider<ThemeCtrl, ThemeMode>((_) => ThemeCtrl());

// ── Navigation ─────────────────────────────────────────────
/// The five root tabs, in the order the 4.0 nav bar shows them. "Ойнау" sits
/// in the middle as a raised button because starting a round is the one thing
/// the app wants you to do most.
enum SqTab { home, arena, play, words, me }

const List<SqTab> kTabOrder = SqTab.values;

extension SqTabMeta on SqTab {
  int get index => SqTab.values.indexOf(this);

  String get label => switch (this) {
    SqTab.home  => tr('Басты'),
    SqTab.arena => tr('Арена'),
    SqTab.play  => tr('Ойнау'),
    SqTab.words => tr('Сөздік'),
    SqTab.me    => tr('Мен'),
  };

  IconData get iconOff => switch (this) {
    SqTab.home  => PhosphorIconsBold.house,
    SqTab.arena => PhosphorIconsBold.sword,
    SqTab.play  => PhosphorIconsFill.play,
    SqTab.words => PhosphorIconsBold.books,
    SqTab.me    => PhosphorIconsBold.userCircle,
  };

  IconData get iconOn => switch (this) {
    SqTab.home  => PhosphorIconsFill.house,
    SqTab.arena => PhosphorIconsFill.sword,
    SqTab.play  => PhosphorIconsFill.play,
    SqTab.words => PhosphorIconsFill.books,
    SqTab.me    => PhosphorIconsFill.userCircle,
  };
}

final tabProvider = StateProvider<int>((_) => 0);

/// Jump to a root tab from anywhere.
void goTab(WidgetRef ref, SqTab tab) =>
    ref.read(tabProvider.notifier).state = tab.index;

/// The app opens straight into a guest session — nobody has to sign in to
/// look around. This flips to true only when the user deliberately asks for
/// the sign-in screen (an existing account, or after signing out), so the
/// gate knows not to hand them a fresh guest session instead.
final showLoginProvider = StateProvider<bool>((_) => false);

// ── Words ──────────────────────────────────────────────────
final myWordsProvider = FutureProvider<List<Word>>((ref) async {
  ref.watch(authChangesProvider);
  return ref.watch(wordsRepoProvider).all();
});

final dueWordsProvider = FutureProvider<List<Word>>(
    (ref) => ref.watch(wordsRepoProvider).due());

/// How many words the learner owns in total. The bank only ever holds the
/// pages it has scrolled to, so the header count has to come from the server
/// rather than from `List.length`.
final wordCountProvider = FutureProvider<int>((ref) {
  ref.watch(authChangesProvider);
  return ref.watch(wordsRepoProvider).totalCount();
});

/// One growing page of the learner's own words (EN-36 / KK-5).
///
/// The bank used to hand a ListView every row the learner owned. Twenty at a
/// time keeps the first paint immediate however large the bank gets, and the
/// screen asks for the next twenty as it nears the bottom.
class WordBankState {
  final List<Word> words;
  final bool loading;
  /// True once the server returned a short page — there is nothing after this.
  final bool exhausted;
  final String? error;

  const WordBankState({
    this.words = const [],
    this.loading = false,
    this.exhausted = false,
    this.error,
  });

  WordBankState copyWith({
    List<Word>? words,
    bool? loading,
    bool? exhausted,
    String? error,
    bool clearError = false,
  }) => WordBankState(
    words: words ?? this.words,
    loading: loading ?? this.loading,
    exhausted: exhausted ?? this.exhausted,
    error: clearError ? null : (error ?? this.error),
  );
}

class WordBankCtrl extends StateNotifier<WordBankState> {
  final Ref _ref;
  WordBankCtrl(this._ref) : super(const WordBankState(loading: true)) {
    loadMore();
  }

  Future<void> loadMore() async {
    if (!mounted || state.exhausted) return;
    if (state.words.isNotEmpty && state.loading) return;
    final offset = state.words.length;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _ref.read(wordsRepoProvider)
          .page(limit: kWordPageSize, offset: offset);
      // The fetch outlives the provider whenever the tab is torn down
      // mid-request — a sign-out, or a test that pumps one screen and ends.
      // Writing state then throws, so every post-await write is guarded.
      if (!mounted) return;
      state = state.copyWith(
        words: [...state.words, ...page],
        loading: false,
        // A page shorter than asked for is the end of the list; an exactly
        // full page might be followed by more, so keep the door open.
        exhausted: page.length < kWordPageSize,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: humanError(e));
    }
  }

  Future<void> reload() async {
    if (!mounted) return;
    state = const WordBankState(loading: true);
    await loadMore();
  }
}

final wordBankProvider =
    StateNotifierProvider<WordBankCtrl, WordBankState>((ref) {
  ref.watch(authChangesProvider);
  return WordBankCtrl(ref);
});

final dueCountProvider = FutureProvider<int>(
    (ref) => ref.watch(wordsRepoProvider).dueCount());

/// Recently added words for the home feed.
final recentWordsProvider = Provider<List<Word>>((ref) {
  final all = ref.watch(myWordsProvider).valueOrNull ?? const <Word>[];
  return all.take(5).toList();
});

/// The word of the day (EN-10).
///
/// Drawn from the shared dictionary at the learner's level rather than from
/// their own bank. It used to pick one of their saved words, which made the
/// "add to my dictionary" the PRD asks for meaningless — the word was already
/// there by construction. A day-seeded index keeps it the same word from
/// morning to midnight without storing anything.
final dailyWordProvider = Provider<DictEntry?>((ref) {
  final pool = ref.watch(levelPoolProvider).valueOrNull ?? const <DictEntry>[];
  if (pool.isEmpty) return null;
  final now = DateTime.now();
  return pool[Random(now.year * 10000 + now.month * 100 + now.day)
      .nextInt(pool.length)];
});

// ── Daily progress / quests ────────────────────────────────
final dailyProgressProvider = FutureProvider<DailyProgress>(
    (ref) => ref.watch(profileRepoProvider).today());

class Quest {
  final String id, title;
  final IconData icon;
  final Color tint;
  final int target, current, xp;
  const Quest(this.id, this.title, this.icon, this.tint,
      this.target, this.current, this.xp);
  bool get done => current >= target;
  double get progress => target == 0 ? 0 : (current / target).clamp(0.0, 1.0);
}

final questsProvider = Provider<List<Quest>>((ref) {
  final d = ref.watch(dailyProgressProvider).valueOrNull ?? const DailyProgress();
  final goal = ref.watch(myProfileProvider).valueOrNull?.dailyGoal ?? 10;
  return [
    Quest('q_review', trp('{n} сөз қайталау', {'n': '$goal'}),
        PhosphorIconsFill.arrowsClockwise,
        AppColors.primary, goal, d.wordsReviewed, 40),
    Quest('q_battle', tr('1 баттл жеңу'), PhosphorIconsFill.sword,
        AppColors.red, 1, d.battlesWon, 60),
    Quest('q_words', tr('3 жаңа сөз қосу'), PhosphorIconsFill.plusCircle,
        AppColors.green, 3, d.wordsAdded, 30),
  ];
});

// ── Weekly report ──────────────────────────────────────────
final weekStatsProvider = FutureProvider<List<DayStat>>(
    (ref) => ref.watch(profileRepoProvider).lastWeek());

/// Accuracy per topic, computed from the learner's own answer history so the
/// report never needs a second round trip.
final topicAccuracyProvider = Provider<List<TopicScore>>((ref) {
  final words = ref.watch(myWordsProvider).valueOrNull ?? const <Word>[];
  final correct = <String, int>{};
  final tries = <String, int>{};
  for (final w in words) {
    if (w.attempts == 0) continue;
    correct[w.topic] = (correct[w.topic] ?? 0) + w.correct;
    tries[w.topic] = (tries[w.topic] ?? 0) + w.attempts;
  }
  final out = <TopicScore>[];
  tries.forEach((topic, total) {
    if (total < 3) return; // too little data to be worth a bar
    out.add(TopicScore(topic, (correct[topic] ?? 0) / total, total));
  });
  // Strongest first. Left unsliced: report_screen.dart shows the top few as
  // a "your accuracy" bar chart but also reads the LAST entry as the
  // learner's weakest topic — slicing to 5 here used to silently discard
  // every topic outside the top 5, so "weakest" was really just "5th
  // strongest" for anyone with more than 5 scored topics.
  out.sort((a, b) => b.ratio.compareTo(a.ratio));
  return out;
});

class TopicScore {
  final String topic;
  final double ratio;
  final int attempts;
  const TopicScore(this.topic, this.ratio, this.attempts);
  int get percent => (ratio * 100).round();
}

// ── Content pools ──────────────────────────────────────────
/// Dictionary entries at the learner's level, used to build rounds and to
/// stock the explore catalogue.
final levelPoolProvider = FutureProvider<List<DictEntry>>((ref) async {
  final levels = ref.watch(visibleLevelsProvider);
  return ref.watch(dictRepoProvider).pool(cefr: levels, limit: 150);
});

/// The words behind one themed pack.
final packPoolProvider =
    FutureProvider.family<List<DictEntry>, String>((ref, packId) async {
  final pack = packOf(packId);
  if (pack == null) return const [];
  return ref.watch(dictRepoProvider)
      .pool(cefr: pack.levels, topic: pack.topic, limit: pack.size);
});

// ── Arena ──────────────────────────────────────────────────
final leaderboardScopeProvider = StateProvider<BoardScope>((_) => BoardScope.week);

final leaderboardProvider = FutureProvider<List<BoardRow>>((ref) {
  final scope = ref.watch(leaderboardScopeProvider);
  return ref.watch(boardRepoProvider).leaderboard(scope);
});

final myLeagueProvider = FutureProvider<List<LeagueRow>>(
    (ref) => ref.watch(boardRepoProvider).myLeague());

final tournamentProvider = FutureProvider<Tournament>(
    (ref) => ref.watch(boardRepoProvider).ensureTournament());

final tournamentBoardProvider =
    FutureProvider.family<List<BoardRow>, int>((ref, id) =>
        ref.watch(boardRepoProvider).tournamentBoard(id));

final playedDailyProvider = FutureProvider<bool>(
    (ref) => ref.watch(boardRepoProvider).playedDailyToday());

final dailyBoardProvider = FutureProvider<List<BoardRow>>((ref) {
  final cefr = ref.watch(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
  return ref.watch(boardRepoProvider).dailyBoard(cefr);
});

final friendsProvider = FutureProvider<List<BoardRow>>(
    (ref) => ref.watch(boardRepoProvider).friends());

final battleHistoryProvider = FutureProvider<List<Battle>>(
    (ref) => ref.watch(battleRepoProvider).history());

final pendingInvitesProvider = FutureProvider<List<Battle>>(
    (ref) => ref.watch(battleRepoProvider).pendingInvites());

final unlockedAchievementsProvider = FutureProvider<Set<String>>(
    (ref) => ref.watch(profileRepoProvider).unlockedAchievements());

/// The learner plus their friends, treated as a weekly team. There is no clan
/// table on the server — a "clan" here is simply everybody you have added,
/// racing a shared weekly XP goal.
final teamProvider = FutureProvider<TeamStanding>((ref) async {
  final me = ref.watch(myProfileProvider).valueOrNull;
  final board = ref.watch(boardRepoProvider);
  final friends = await board.friends();

  // The countdown on clan_screen.dart promises a race that resets every
  // Monday — `Profile.xp`/`BoardRow.value` are lifetime totals that never
  // do, so the team total must come from actual weekly XP instead.
  final ids = [if (me != null) me.id, ...friends.map((f) => f.userId)];
  final weekly = await board.weeklyXp(ids);

  final rows = <TeamMember>[
    if (me != null) TeamMember(me.name, weekly[me.id] ?? 0, true),
    ...friends.map((f) => TeamMember(f.name, weekly[f.userId] ?? 0, false)),
  ]..sort((a, b) => b.xp.compareTo(a.xp));
  return TeamStanding(rows);
});

class TeamMember {
  final String name;
  final int xp;
  final bool isMe;
  const TeamMember(this.name, this.xp, this.isMe);
}

class TeamStanding {
  final List<TeamMember> members;
  const TeamStanding(this.members);

  int get total => members.fold(0, (a, m) => a + m.xp);
  int get size => members.length;

  /// A round weekly target that always sits a little above where the team is,
  /// so the bar has somewhere to go.
  int get goal {
    final t = total;
    if (t <= 0) return 1000;
    final step = t < 5000 ? 1000 : 2000;
    return ((t ~/ step) + 1) * step;
  }

  double get progress => goal == 0 ? 0 : (total / goal).clamp(0.0, 1.0);

  double shareOf(TeamMember m) => total == 0 ? 0 : m.xp / total;
}

// ── Live events ────────────────────────────────────────────
final eventsRepoProvider = Provider((_) => EventsRepo());

final activeEventsProvider = FutureProvider<List<AppEvent>>((ref) {
  final cefr = ref.watch(myProfileProvider).valueOrNull?.cefrLevel ?? 'A1';
  return ref.watch(eventsRepoProvider).active(cefr);
});

final eventProgressProvider = FutureProvider<Map<int, EventProgress>>(
    (ref) => ref.watch(eventsRepoProvider).myProgress());

// ── Meta-game (chest, mission path, shop, packs) ───────────
class MetaCtrl extends StateNotifier<MetaState> {
  MetaCtrl() : super(const MetaState()) {
    _restore();
  }

  Future<void> _restore() async {
    state = await MetaStore.instance.load();
  }

  Future<void> _commit(MetaState next) async {
    state = next;
    await MetaStore.instance.save(next);
  }

  /// Opens today's chest and returns the XP it was worth. The reward grows
  /// with the chest streak and lands on a round number every seventh day.
  Future<int> openChest({required int cardIndex}) async {
    if (!state.chestReady) return 0;
    final streak = state.nextChestStreak;
    final base = 40 + streak * 10;
    final bonus = streak % 7 == 0 ? 200 : cardIndex * 15;
    await _commit(state.copyWith(
      chestDay: MetaState.today(),
      chestStreak: streak,
      freezes: cardIndex == 1 ? state.freezes + 1 : state.freezes,
      lives: cardIndex == 2 ? state.lives + 1 : state.lives,
    ));
    return base + bonus;
  }

  Future<void> claimPass(PassReward r) async {
    if (state.passClaimed.contains(r.level)) return;
    var next = state.copyWith(passClaimed: {...state.passClaimed, r.level});
    switch (r.grant) {
      case 'freeze':
        next = next.copyWith(freezes: next.freezes + 1);
      case 'freeze2':
        next = next.copyWith(freezes: next.freezes + 2);
      case 'life':
        next = next.copyWith(lives: next.lives + 1);
      case final String id when id.isNotEmpty:
        next = next.copyWith(owned: {...next.owned, id});
      default:
        break;
    }
    await _commit(next);
  }

  Future<void> unlockPremium() =>
      _commit(state.copyWith(passPremium: true));

  /// Records a purchase. XP is not deducted on the server — the shop spends
  /// against a locally tracked budget so a cosmetic can never eat the XP that
  /// leagues and leaderboards are ranked on.
  Future<void> buy(ShopItem item) async {
    var next = state.copyWith(spent: state.spent + item.price);
    switch (item.id) {
      case 'freeze':
        next = next.copyWith(freezes: next.freezes + 1);
      case 'life':
        next = next.copyWith(lives: next.lives + 1);
      default:
        next = next.copyWith(owned: {...next.owned, item.id});
        if (item.id.startsWith('frame_')) next = next.copyWith(frame: item.id);
    }
    await _commit(next);
  }

  Future<void> wearFrame(String id) => _commit(state.copyWith(frame: id));

  Future<void> useFreeze() => _commit(
      state.copyWith(freezes: (state.freezes - 1).clamp(0, 99)));

  Future<void> useLife() =>
      _commit(state.copyWith(lives: (state.lives - 1).clamp(0, 99)));

  Future<void> bumpPack(String packId, int by) async {
    final packs = Map<String, int>.from(state.packs);
    packs[packId] = (packs[packId] ?? 0) + by;
    await _commit(state.copyWith(packs: packs));
  }

  Future<void> clearStoryTo(int node) async {
    if (node <= state.storyNode) return;
    await _commit(state.copyWith(storyNode: node));
  }

  /// Drops the whole meta-game back to a fresh install. Called on sign-out so
  /// the next account does not inherit the previous person's chest streak,
  /// cosmetics and story progress (EN-47).
  Future<void> reset() async {
    await MetaStore.instance.clear();
    if (!mounted) return;
    state = const MetaState();
  }
}

final metaProvider =
    StateNotifierProvider<MetaCtrl, MetaState>((_) => MetaCtrl());

/// XP the learner may actually spend in the shop.
///
/// Read off the profile rather than local state: spending is tracked server
/// side in `xp_spent`, so the balance survives a reinstall and cannot be
/// edited by the device. `xp` itself is never reduced — leagues rank on it.
final spendableXpProvider = Provider<int>((ref) =>
    ref.watch(myProfileProvider).valueOrNull?.spendableXp ?? 0);

// ── Refresh helper ─────────────────────────────────────────
/// Invalidates everything that changes after a round or a word edit.
void refreshAll(WidgetRef ref) {
  ref.invalidate(myProfileProvider);
  ref.invalidate(myWordsProvider);
  ref.invalidate(dueWordsProvider);
  ref.invalidate(dueCountProvider);
  ref.invalidate(wordCountProvider);
  // The bank holds its own accumulated pages, so invalidating is not enough —
  // it has to be told to fetch page one again.
  ref.read(wordBankProvider.notifier).reload();
  ref.invalidate(dailyProgressProvider);
  ref.invalidate(weekStatsProvider);
  ref.invalidate(myLeagueProvider);
  ref.invalidate(leaderboardProvider);
  ref.invalidate(unlockedAchievementsProvider);
}
