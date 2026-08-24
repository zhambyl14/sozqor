// lib/features/arena/rematch_series.dart
//
// Best of three against the same person (EN-21).
//
// "Кек қайтару" already existed and already did something, but what it did was
// throw the opponent away: it popped the finished battle back to the arena,
// which started a fresh matchmaking search. The person you had just played was
// gone, and the one thing a rematch is for — settling it with THAT player —
// was the one thing it could not do.
//
// A series is three games at most against the same two people, with a running
// score, ending in a sentence: "2:1 есебімен жеңдің". It lives here rather
// than inside the battle screen because it has to outlive each individual
// battle — the screen is pushed and popped once per game, and anything kept in
// its state dies with game one.
//
// Ranked games inside a series still settle Elo the ordinary way, one match at
// a time. The series is a frame around real matches, not a different kind of
// match, so nothing about the rating maths changes.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/battle.dart';

/// How many games a series runs to. Three is the number the PRD names, and it
/// is also the smallest number that can produce a decisive 2:1.
const int kSeriesLength = 3;

class SeriesGame {
  /// True when this learner won it; null for a draw.
  final bool? won;
  final int myScore, oppScore;
  const SeriesGame({
    required this.won, required this.myScore, required this.oppScore});
}

/// One run of up to three games against one opponent.
class RematchSeries {
  /// Who it is against. A series is meaningless without this — it is the whole
  /// difference between a rematch and another random match.
  final String opponentId;
  final String opponentName;
  /// ranked | friend | bot. Kept so the next game is started the same way the
  /// first one was.
  final String mode;
  final List<SeriesGame> games;
  /// Set once the other side declines, so the UI stops offering another game
  /// and falls back to ordinary matchmaking (EN-21).
  final bool declined;

  const RematchSeries({
    required this.opponentId,
    required this.opponentName,
    required this.mode,
    this.games = const [],
    this.declined = false,
  });

  int get myWins  => games.where((g) => g.won == true).length;
  int get oppWins => games.where((g) => g.won == false).length;
  int get played  => games.length;

  /// A series ends when somebody cannot be caught, not only when three games
  /// have been played — 2:0 is already decided and a third game is a formality
  /// nobody wants to sit through.
  bool get isDecided =>
      declined ||
      played >= kSeriesLength ||
      myWins > (kSeriesLength - played + oppWins) ||
      oppWins > (kSeriesLength - played + myWins);

  bool get canPlayAnother => !isDecided;

  /// null while the series is still level or unfinished-but-tied.
  bool? get iWonSeries {
    if (!isDecided) return null;
    if (myWins == oppWins) return null;
    return myWins > oppWins;
  }

  /// The line the result screen shows at the end: "2:1".
  String get scoreline => '$myWins:$oppWins';

  RematchSeries withGame(SeriesGame g) =>
      RematchSeries(
        opponentId: opponentId,
        opponentName: opponentName,
        mode: mode,
        games: [...games, g],
        declined: declined,
      );

  RematchSeries asDeclined() => RematchSeries(
        opponentId: opponentId,
        opponentName: opponentName,
        mode: mode,
        games: games,
        declined: true,
      );
}

class RematchCtrl extends StateNotifier<RematchSeries?> {
  RematchCtrl() : super(null);

  /// Begins a series against whoever was on the other side of [finished].
  /// Returns false when the battle has no human opponent to rematch.
  bool start(Battle finished, String uid, String opponentName) {
    final oppId = finished.oppId(uid);
    if (oppId == null && finished.mode != 'bot') return false;
    state = RematchSeries(
      opponentId: oppId ?? 'bot',
      opponentName: opponentName,
      mode: finished.mode,
    );
    return true;
  }

  /// Records a finished game. Ignored when it is not part of the current
  /// series — a stray result from an unrelated battle must not move the score.
  void record(Battle b, String uid) {
    final s = state;
    if (s == null) return;
    final oppId = b.oppId(uid) ?? 'bot';
    if (oppId != s.opponentId) return;

    state = s.withGame(SeriesGame(
      won: b.isDraw ? null : b.winner == uid,
      myScore: b.myScore(uid),
      oppScore: b.oppScore(uid),
    ));
  }

  /// The other side did not take the rematch, so the series stops here and the
  /// arena goes back to ordinary matchmaking.
  void decline() {
    final s = state;
    if (s != null) state = s.asDeclined();
  }

  void clear() => state = null;
}

/// The series in flight, or null when there is none.
///
/// Deliberately not persisted. A rematch is an agreement between two people
/// who are both at their phones right now; one that survived a restart would
/// be an invitation to somebody who has long since walked away.
final rematchProvider =
    StateNotifierProvider<RematchCtrl, RematchSeries?>((_) => RematchCtrl());
