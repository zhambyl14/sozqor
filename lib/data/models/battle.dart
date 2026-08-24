// lib/data/models/battle.dart
import 'question.dart';
import '../../core/i18n/l10n.dart';

enum BattleMode { ranked, bot, friend }

extension BattleModeX on BattleMode {
  String get id => name;
  static BattleMode fromId(String v) =>
      BattleMode.values.firstWhere((m) => m.name == v, orElse: () => BattleMode.bot);
}

class Battle {
  final String id, mode, status;
  final String p1;
  final String? p2, winner, inviteCode, botName, botAvatar;
  final double? botAccuracy;
  final int?    botSpeedMs;
  final List<Question> questions;
  final int  p1Score, p2Score, p1Correct, p2Correct;
  final bool p1Done, p2Done, isDraw;
  final int  p1EloDelta, p2EloDelta;
  final String cefr;
  final DateTime createdAt;
  /// When the match began and ended. Both are nullable: a battle that is
  /// still waiting has no start, and one that never settled has no end. The
  /// reopened result screen needs them to show a duration (EN-28).
  final DateTime? startedAt, endedAt;

  const Battle({
    required this.id,
    required this.mode,
    required this.status,
    required this.p1,
    required this.questions,
    required this.createdAt,
    this.p2,
    this.winner,
    this.inviteCode,
    this.botName,
    this.botAvatar,
    this.botAccuracy,
    this.botSpeedMs,
    this.p1Score = 0,
    this.p2Score = 0,
    this.p1Correct = 0,
    this.p2Correct = 0,
    this.p1Done = false,
    this.p2Done = false,
    this.isDraw = false,
    this.p1EloDelta = 0,
    this.p2EloDelta = 0,
    this.cefr = 'A1',
    this.startedAt,
    this.endedAt,
  });

  factory Battle.fromMap(Map<String, dynamic> m) => Battle(
    id:        m['id'].toString(),
    mode:      (m['mode'] ?? 'bot').toString(),
    status:    (m['status'] ?? 'waiting').toString(),
    p1:        (m['p1'] ?? '').toString(),
    p2:        m['p2']?.toString(),
    winner:    m['winner']?.toString(),
    inviteCode:m['invite_code']?.toString(),
    botName:   m['bot_name']?.toString(),
    botAvatar: m['bot_avatar']?.toString(),
    botAccuracy: m['bot_accuracy'] == null
        ? null : double.tryParse('${m['bot_accuracy']}'),
    botSpeedMs: m['bot_speed_ms'] is int ? m['bot_speed_ms'] as int : null,
    questions: (m['questions'] as List? ?? const [])
        .map((e) => Question.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    p1Score:   (m['p1_score'] ?? 0) as int,
    p2Score:   (m['p2_score'] ?? 0) as int,
    p1Correct: (m['p1_correct'] ?? 0) as int,
    p2Correct: (m['p2_correct'] ?? 0) as int,
    p1Done:    (m['p1_done'] ?? false) as bool,
    p2Done:    (m['p2_done'] ?? false) as bool,
    isDraw:    (m['is_draw'] ?? false) as bool,
    p1EloDelta:(m['p1_elo_delta'] ?? 0) as int,
    p2EloDelta:(m['p2_elo_delta'] ?? 0) as int,
    cefr:      (m['cefr'] ?? 'A1').toString(),
    createdAt: DateTime.tryParse('${m['created_at']}') ?? DateTime.now(),
    startedAt: DateTime.tryParse('${m['started_at']}'),
    endedAt:   DateTime.tryParse('${m['ended_at']}'),
  );

  bool amHost(String uid) => p1 == uid;
  int  myScore(String uid)   => amHost(uid) ? p1Score : p2Score;
  int  oppScore(String uid)  => amHost(uid) ? p2Score : p1Score;
  bool iAmDone(String uid)   => amHost(uid) ? p1Done : p2Done;
  bool oppIsDone(String uid) => amHost(uid) ? p2Done : p1Done;
  int  myEloDelta(String uid)=> amHost(uid) ? p1EloDelta : p2EloDelta;
  String? oppId(String uid)  => amHost(uid) ? p2 : p1;

  bool get isFinished => status == 'finished';
  bool get isWaiting  => status == 'waiting';
}

/// A leaderboard / friend / search row returned by the board_row RPCs.
class BoardRow {
  final String userId, username, displayName, avatarEmoji, cefrLevel;
  final int value, rank;

  const BoardRow({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarEmoji,
    required this.cefrLevel,
    required this.value,
    required this.rank,
  });

  factory BoardRow.fromMap(Map<String, dynamic> m) => BoardRow(
    userId:      (m['user_id'] ?? '').toString(),
    username:    (m['username'] ?? '').toString(),
    displayName: (m['display_name'] ?? '').toString(),
    avatarEmoji: (m['avatar_emoji'] ?? '🦊').toString(),
    cefrLevel:   (m['cefr_level'] ?? 'A1').toString(),
    value:       (m['value'] ?? 0) as int,
    rank:        (m['rank'] ?? 0) as int,
  );

  String get name => displayName.trim().isEmpty ? username : displayName.trim();
}

/// One standings row inside the caller's weekly league.
class LeagueRow {
  final int leagueId, tier, xp, rank;
  final String userId, username, displayName, avatarEmoji;
  final bool isMe;

  const LeagueRow({
    required this.leagueId,
    required this.tier,
    required this.xp,
    required this.rank,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.avatarEmoji,
    required this.isMe,
  });

  factory LeagueRow.fromMap(Map<String, dynamic> m) => LeagueRow(
    leagueId:    (m['league_id'] ?? 0) as int,
    tier:        (m['tier'] ?? 0) as int,
    xp:          (m['xp'] ?? 0) as int,
    rank:        (m['rank'] ?? 0) as int,
    userId:      (m['user_id'] ?? '').toString(),
    username:    (m['username'] ?? '').toString(),
    displayName: (m['display_name'] ?? '').toString(),
    avatarEmoji: (m['avatar_emoji'] ?? '🦊').toString(),
    isMe:        (m['is_me'] ?? false) as bool,
  );

  String get name => displayName.trim().isEmpty ? username : displayName.trim();
}

class Tournament {
  final int id;
  final String title, emoji;
  final DateTime startsAt, endsAt;
  final int xpReward;

  const Tournament({
    required this.id,
    required this.title,
    required this.emoji,
    required this.startsAt,
    required this.endsAt,
    required this.xpReward,
  });

  factory Tournament.fromMap(Map<String, dynamic> m) => Tournament(
    id:       (m['id'] ?? 0) as int,
    title:    (m['title'] ?? tr('Турнир')).toString(),
    emoji:    (m['emoji'] ?? '🏆').toString(),
    startsAt: DateTime.tryParse('${m['starts_at']}') ?? DateTime.now(),
    endsAt:   DateTime.tryParse('${m['ends_at']}') ??
              DateTime.now().add(const Duration(days: 1)),
    xpReward: (m['xp_reward'] ?? 300) as int,
  );

  Duration get remaining {
    final d = endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }
}

class DailyProgress {
  final int wordsAdded, quizzesDone, wordsReviewed, correctCount;
  final int battlesPlayed, battlesWon, xpEarned;
  final List<String> claimed;

  const DailyProgress({
    this.wordsAdded = 0,
    this.quizzesDone = 0,
    this.wordsReviewed = 0,
    this.correctCount = 0,
    this.battlesPlayed = 0,
    this.battlesWon = 0,
    this.xpEarned = 0,
    this.claimed = const [],
  });

  factory DailyProgress.fromMap(Map<String, dynamic> m) => DailyProgress(
    wordsAdded:    (m['words_added'] ?? 0) as int,
    quizzesDone:   (m['quizzes_done'] ?? 0) as int,
    wordsReviewed: (m['words_reviewed'] ?? 0) as int,
    correctCount:  (m['correct_count'] ?? 0) as int,
    battlesPlayed: (m['battles_played'] ?? 0) as int,
    battlesWon:    (m['battles_won'] ?? 0) as int,
    xpEarned:      (m['xp_earned'] ?? 0) as int,
    claimed:       (m['claimed'] as List? ?? const [])
                     .map((e) => e.toString()).toList(),
  );
}
