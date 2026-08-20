// lib/data/models/profile.dart
import '../../core/constants/game_meta.dart';
import '../../core/i18n/l10n.dart';

class Profile {
  final String id, username, displayName, avatarEmoji, cefrLevel;
  /// Interface language and study language are independent settings.
  final String uiLang, nativeLang;
  /// Verified through the Telegram bot; never shown to other learners.
  final String? phone;
  final int    xp, coins, streak, bestStreak, elo;
  final int    battlesPlayed, battlesWon, wordsTotal, wordsLearned, quizzesDone;
  final bool   onboarded, darkMode, notifEnabled, isGuest;
  final int    dailyGoal;
  final DateTime? lastActive;

  /// Cosmetics the learner is wearing. Empty means "nothing equipped" — the
  /// id of a row in `cosmetics`, not a colour or a label.
  final String equippedFrame, equippedTitle;

  /// XP already spent in the shop. `xp` itself is never reduced, because
  /// leagues and leaderboards rank on lifetime XP — the shop budget is
  /// (xp - xpSpent), see [spendableXp].
  final int xpSpent;

  const Profile({
    required this.id,
    required this.username,
    this.displayName   = '',
    this.avatarEmoji   = '🦊',
    this.cefrLevel     = 'A1',
    this.uiLang        = 'kk',
    this.nativeLang    = 'kk',
    this.phone,
    this.xp            = 0,
    this.coins         = 0,
    this.streak        = 0,
    this.bestStreak    = 0,
    this.elo           = 1000,
    this.battlesPlayed = 0,
    this.battlesWon    = 0,
    this.wordsTotal    = 0,
    this.wordsLearned  = 0,
    this.quizzesDone   = 0,
    this.onboarded     = false,
    this.isGuest       = false,
    this.darkMode      = false,
    this.notifEnabled  = true,
    this.dailyGoal     = 10,
    this.lastActive,
    this.equippedFrame = '',
    this.equippedTitle = '',
    this.xpSpent       = 0,
  });

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
    id:            m['id'] as String,
    username:      (m['username'] ?? '') as String,
    displayName:   (m['display_name'] ?? '') as String,
    avatarEmoji:   (m['avatar_emoji'] ?? '🦊') as String,
    cefrLevel:     (m['cefr_level'] ?? 'A1') as String,
    uiLang:        (m['ui_lang'] ?? 'kk') as String,
    nativeLang:    (m['native_lang'] ?? 'kk') as String,
    phone:         m['phone']?.toString(),
    xp:            (m['xp'] ?? 0) as int,
    coins:         (m['coins'] ?? 0) as int,
    streak:        (m['streak'] ?? 0) as int,
    bestStreak:    (m['best_streak'] ?? 0) as int,
    elo:           (m['elo'] ?? 1000) as int,
    battlesPlayed: (m['battles_played'] ?? 0) as int,
    battlesWon:    (m['battles_won'] ?? 0) as int,
    wordsTotal:    (m['words_total'] ?? 0) as int,
    wordsLearned:  (m['words_learned'] ?? 0) as int,
    quizzesDone:   (m['quizzes_done'] ?? 0) as int,
    onboarded:     (m['onboarded'] ?? false) as bool,
    isGuest:       (m['is_guest'] ?? false) as bool,
    darkMode:      (m['dark_mode'] ?? false) as bool,
    notifEnabled:  (m['notif_enabled'] ?? true) as bool,
    dailyGoal:     (m['daily_goal'] ?? 10) as int,
    lastActive:    m['last_active'] == null
        ? null : DateTime.tryParse(m['last_active'].toString()),
    // Nullable columns: a learner who never equipped anything has NULL here.
    equippedFrame: (m['equipped_frame'] ?? '').toString(),
    equippedTitle: (m['equipped_title'] ?? '').toString(),
    xpSpent:       ((m['xp_spent'] ?? 0) as num).toInt(),
  );

  /// XP the shop may actually charge. Never negative, even if a price change
  /// leaves someone having spent more than they have earned.
  int get spendableXp => (xp - xpSpent).clamp(0, 1 << 30);

  String get name => displayName.trim().isEmpty ? username : displayName.trim();
  CefrLevel get cefr => cefrOf(cefrLevel);

  /// XP level curve: each level costs 15% more than the last.
  int get levelNumber {
    var lvl = 1, need = 100, pool = xp;
    while (pool >= need && lvl < 200) {
      pool -= need;
      lvl++;
      need = (need * 1.15).round();
    }
    return lvl;
  }

  double get levelProgress {
    var lvl = 1, need = 100, pool = xp;
    while (pool >= need && lvl < 200) {
      pool -= need;
      lvl++;
      need = (need * 1.15).round();
    }
    return need == 0 ? 0 : (pool / need).clamp(0.0, 1.0);
  }

  int get xpToNextLevel {
    var lvl = 1, need = 100, pool = xp;
    while (pool >= need && lvl < 200) {
      pool -= need;
      lvl++;
      need = (need * 1.15).round();
    }
    return need - pool;
  }

  double get winRate =>
      battlesPlayed == 0 ? 0 : battlesWon / battlesPlayed;

  String get rankTitle {
    if (elo >= 1800) return tr('Аңыз');
    if (elo >= 1500) return tr('Гроссмейстер');
    if (elo >= 1300) return tr('Шебер');
    if (elo >= 1150) return tr('Жауынгер');
    if (elo >= 1000) return tr('Ойыншы');
    return tr('Жаңадан');
  }

  Profile copyWith({
    String? displayName, String? avatarEmoji, String? cefrLevel,
    String? uiLang, String? nativeLang,
    bool? onboarded, bool? darkMode, bool? notifEnabled, int? dailyGoal,
    int? xp, int? streak,
    String? equippedFrame, String? equippedTitle, int? xpSpent,
  }) => Profile(
    id: id, username: username,
    displayName:   displayName  ?? this.displayName,
    avatarEmoji:   avatarEmoji  ?? this.avatarEmoji,
    cefrLevel:     cefrLevel    ?? this.cefrLevel,
    uiLang:        uiLang       ?? this.uiLang,
    nativeLang:    nativeLang   ?? this.nativeLang,
    phone:         phone,
    xp:            xp           ?? this.xp,
    coins:         coins,
    streak:        streak       ?? this.streak,
    bestStreak:    bestStreak,
    elo:           elo,
    battlesPlayed: battlesPlayed,
    battlesWon:    battlesWon,
    wordsTotal:    wordsTotal,
    wordsLearned:  wordsLearned,
    quizzesDone:   quizzesDone,
    onboarded:     onboarded    ?? this.onboarded,
    isGuest:       isGuest,
    darkMode:      darkMode     ?? this.darkMode,
    notifEnabled:  notifEnabled ?? this.notifEnabled,
    dailyGoal:     dailyGoal    ?? this.dailyGoal,
    lastActive:    lastActive,
    equippedFrame: equippedFrame ?? this.equippedFrame,
    equippedTitle: equippedTitle ?? this.equippedTitle,
    xpSpent:       xpSpent       ?? this.xpSpent,
  );
}
