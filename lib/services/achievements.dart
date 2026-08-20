// lib/services/achievements.dart
//
// Evaluates the achievement catalogue against the current profile and unlocks
// anything newly earned. Called after rounds, battles and word additions.

import '../core/constants/game_meta.dart';
import '../data/models/profile.dart';
import '../data/repos/board_repo.dart';
import '../data/repos/profile_repo.dart';

class AchievementService {
  AchievementService._();
  static final AchievementService instance = AchievementService._();

  final _profiles = ProfileRepo();
  final _boards = BoardRepo();

  /// Returns the achievements unlocked by this check, so the caller can show
  /// a celebration for each one.
  Future<List<Achievement>> check(Profile p) async {
    final already = await _profiles.unlockedAchievements();
    final marathonBest = await _boards.myBest('marathon').catchError((_) => 0);

    int metric(String m) => switch (m) {
      'words'       => p.wordsTotal,
      'learned'     => p.wordsLearned,
      'streak'      => p.streak,
      'quizzes'     => p.quizzesDone,
      'battles_won' => p.battlesWon,
      'xp'          => p.xp,
      'elo'         => p.elo,
      'marathon'    => marathonBest,
      _             => 0,
    };

    final fresh = <Achievement>[];
    for (final a in kAchievements) {
      if (already.contains(a.code)) continue;
      if (metric(a.metric) >= a.target) fresh.add(a);
    }

    for (final a in fresh) {
      try {
        await _profiles.unlockAchievement(a.code);
        await _profiles.addXp(a.xp, 'achievement_${a.code}');
      } catch (_) {/* non-fatal */}
    }
    return fresh;
  }

  /// Progress towards every achievement, for the trophy screen.
  Map<String, int> progressFor(Profile p, int marathonBest) => {
    for (final a in kAchievements)
      a.code: switch (a.metric) {
        'words'       => p.wordsTotal,
        'learned'     => p.wordsLearned,
        'streak'      => p.streak,
        'quizzes'     => p.quizzesDone,
        'battles_won' => p.battlesWon,
        'xp'          => p.xp,
        'elo'         => p.elo,
        'marathon'    => marathonBest,
        _             => 0,
      },
  };
}
