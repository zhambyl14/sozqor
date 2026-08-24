// lib/services/meta_store.dart
//
// Local home for the 4.0 meta-game: the daily chest, the mission path, the
// shop, streak freezes and word-pack progress.
//
// All of it lives in a single SharedPreferences key rather than in Postgres.
// That is deliberate — none of these are competitive or shared, the app must
// keep working offline, and the project runs on a free tier where every extra
// table is another migration to keep in step. XP itself still comes from the
// server profile; this store only records what the learner has *done with* it.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One purchasable / unlockable thing in the shop.
class ShopItem {
  final String id, title, subtitle;
  final int price;
  /// Consumables can be bought many times; cosmetics only once.
  final bool consumable;

  const ShopItem(this.id, this.title, this.subtitle, this.price,
      {this.consumable = false});
}

const List<ShopItem> kShopItems = [
  ShopItem('frame_gold', 'Алтын жиек', 'Аватар жиегі', 1200),
  ShopItem('theme_night', 'Түнгі тақырып', 'Қараңғы интерфейс', 900),
  ShopItem('freeze', 'Серия мұздатқыш', 'Серияны 1 күн сақтайды', 350,
      consumable: true),
  ShopItem('life', 'Қосымша жан', 'Марафонда +1 жан', 250, consumable: true),
  ShopItem('frame_eagle', 'Қыран жиегі', 'Профиль жиегі', 1800),
];

ShopItem? shopItemOf(String id) {
  for (final i in kShopItems) {
    if (i.id == id) return i;
  }
  return null;
}

/// A snapshot of everything the meta-game knows. Immutable so Riverpod can
/// diff it cheaply.
class MetaState {
  /// `yyyy-MM-dd` of the last chest the learner opened.
  final String chestDay;
  /// How many days in a row a chest has been opened.
  final int chestStreak;
  /// Streak freezes and marathon lives in stock.
  final int freezes, lives;
  /// Mission-path levels whose reward has been collected.
  final Set<int> passClaimed;
  final bool passPremium;
  /// Cosmetics owned, and the frame currently worn.
  final Set<String> owned;
  final String frame;
  /// How many words of each pack have been trained.
  final Map<String, int> packs;
  /// Highest word-path node the learner has cleared.
  final int storyNode;
  /// XP spent in the shop — subtracted from the profile total when pricing.
  final int spent;

  const MetaState({
    this.chestDay = '',
    this.chestStreak = 0,
    this.freezes = 0,
    this.lives = 0,
    this.passClaimed = const {},
    this.passPremium = false,
    this.owned = const {},
    this.frame = '',
    this.packs = const {},
    this.storyNode = 0,
    this.spent = 0,
  });

  static String today() => DateTime.now().toIso8601String().substring(0, 10);

  static String _yesterday() => DateTime.now()
      .subtract(const Duration(days: 1))
      .toIso8601String()
      .substring(0, 10);

  /// True when a fresh chest is waiting.
  bool get chestReady => chestDay != today();

  /// The chest streak the *next* open will produce.
  int get nextChestStreak =>
      chestDay == _yesterday() ? chestStreak + 1 : 1;

  bool owns(String id) => owned.contains(id);

  MetaState copyWith({
    String? chestDay,
    int? chestStreak,
    int? freezes,
    int? lives,
    Set<int>? passClaimed,
    bool? passPremium,
    Set<String>? owned,
    String? frame,
    Map<String, int>? packs,
    int? storyNode,
    int? spent,
  }) => MetaState(
    chestDay:    chestDay    ?? this.chestDay,
    chestStreak: chestStreak ?? this.chestStreak,
    freezes:     freezes     ?? this.freezes,
    lives:       lives       ?? this.lives,
    passClaimed: passClaimed ?? this.passClaimed,
    passPremium: passPremium ?? this.passPremium,
    owned:       owned       ?? this.owned,
    frame:       frame       ?? this.frame,
    packs:       packs       ?? this.packs,
    storyNode:   storyNode   ?? this.storyNode,
    spent:       spent       ?? this.spent,
  );

  Map<String, dynamic> toJson() => {
    'chestDay': chestDay,
    'chestStreak': chestStreak,
    'freezes': freezes,
    'lives': lives,
    'passClaimed': passClaimed.toList(),
    'passPremium': passPremium,
    'owned': owned.toList(),
    'frame': frame,
    'packs': packs,
    'storyNode': storyNode,
    'spent': spent,
  };

  factory MetaState.fromJson(Map<String, dynamic> m) => MetaState(
    chestDay:    (m['chestDay'] ?? '').toString(),
    chestStreak: (m['chestStreak'] as num?)?.toInt() ?? 0,
    freezes:     (m['freezes'] as num?)?.toInt() ?? 0,
    lives:       (m['lives'] as num?)?.toInt() ?? 0,
    passClaimed: ((m['passClaimed'] as List?) ?? const [])
        .map((e) => (e as num).toInt()).toSet(),
    passPremium: (m['passPremium'] ?? false) as bool,
    owned: ((m['owned'] as List?) ?? const [])
        .map((e) => e.toString()).toSet(),
    frame: (m['frame'] ?? '').toString(),
    packs: ((m['packs'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt())),
    storyNode: (m['storyNode'] as num?)?.toInt() ?? 0,
    spent:     (m['spent'] as num?)?.toInt() ?? 0,
  );
}

/// Reads and writes [MetaState]. Every failure is swallowed: the meta-game is
/// a bonus layer and must never be able to stop the app from starting.
class MetaStore {
  MetaStore._();
  static final MetaStore instance = MetaStore._();

  static const _key = 'sozqor_meta_v4';

  Future<MetaState> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const MetaState();
      return MetaState.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return const MetaState();
    }
  }

  Future<void> save(MetaState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {
      // a device that cannot persist still gets a working session
    }
  }

  /// Wipes the meta-game on sign-out.
  ///
  /// Everything in here is per-person — chest streak, freezes, lives, mission
  /// claims, owned cosmetics, the worn frame, pack progress, story node — but
  /// it is stored per-device under one key with no account in it. Signing out
  /// and into a different account used to inherit all of it, which is a large
  /// part of why logging out looked like it had not worked (EN-47).
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {/* nothing to lose that was not already lost */}
  }
}

// ── Mission path ──────────────────────────────────────────────────────────

/// One reward on the mission path (the season "battle pass").
class PassReward {
  final int level;
  final String title;
  final bool premium;
  /// XP handed out when this level is claimed; 0 for pure cosmetics.
  final int xp;
  /// A consumable granted alongside the XP.
  final String? grant;

  const PassReward(this.level, this.title, {
    this.premium = false, this.xp = 0, this.grant});
}

const List<PassReward> kPassRewards = [
  PassReward(1,  '50 XP',            xp: 50),
  PassReward(2,  'Мұздатқыш',        grant: 'freeze'),
  PassReward(3,  '100 XP',           xp: 100),
  PassReward(4,  'Қосымша жан',      grant: 'life'),
  PassReward(5,  '150 XP',           xp: 150),
  PassReward(6,  'Мұздатқыш × 2',    grant: 'freeze2'),
  PassReward(7,  'Алтын жиек',       premium: true, grant: 'frame_gold'),
  PassReward(8,  '300 XP',           xp: 300),
  PassReward(9,  'Мұздатқыш × 2',    grant: 'freeze2'),
  PassReward(10, 'Қыран жиегі',      premium: true, grant: 'frame_eagle'),
  PassReward(11, '400 XP',           xp: 400),
  PassReward(12, 'Түнгі тақырып',    premium: true, grant: 'theme_night'),
];

/// Season level from lifetime XP: 400 XP per level, capped at the last reward.
int passLevelFor(int xp) =>
    (xp ~/ 400).clamp(0, kPassRewards.last.level);

/// How far through the current season level the learner is. Once the last
/// reward level is reached there is no next level to progress toward, so the
/// bar reads as complete instead of moving toward a level that never pays out.
double passProgressFor(int xp) {
  if (passLevelFor(xp) >= kPassRewards.last.level) return 1.0;
  return ((xp % 400) / 400).clamp(0.0, 1.0);
}

int passXpToNext(int xp) {
  if (passLevelFor(xp) >= kPassRewards.last.level) return 0;
  return 400 - (xp % 400);
}

// ── Word packs ────────────────────────────────────────────────────────────

/// A themed set of words pulled out of the shared dictionary by topic + level.
class WordPack {
  final String id, title, subtitle, topic;
  final List<String> levels;
  final int size;

  const WordPack(this.id, this.title, this.subtitle, this.topic, this.levels,
      this.size);
}

const List<WordPack> kWordPacks = [
  WordPack('movies', 'Фильм сөздері', 'Диалогтан алынған лексика',
      'communication', ['B1', 'B2'], 64),
  WordPack('ielts', 'IELTS 6.5+', 'Академиялық лексика',
      'school', ['B2', 'C1'], 120),
  WordPack('songs', 'Ән мәтіндері', 'Поп-музыка тілі',
      'emotions', ['A2', 'B1'], 48),
  WordPack('tech', 'Tech & IT', 'Мамандық сөздері',
      'tech', ['B1', 'B2'], 90),
  WordPack('travel', 'Саяхат', 'Әуежай, қонақүй, жол',
      'travel', ['A2', 'B1'], 56),
  WordPack('food', 'Ас мәзірі', 'Кафе мен базар тілі',
      'food', ['A1', 'A2'], 52),
];

WordPack? packOf(String id) {
  for (final p in kWordPacks) {
    if (p.id == id) return p;
  }
  return null;
}
