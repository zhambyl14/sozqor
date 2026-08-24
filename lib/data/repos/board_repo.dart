// lib/data/repos/board_repo.dart
import '../models/battle.dart';
import '../supa.dart';

enum BoardScope { all, week, elo }

class BoardRepo {
  List<BoardRow> _rows(dynamic res) => (res as List? ?? const [])
      .map((r) => BoardRow.fromMap(Map<String, dynamic>.from(r as Map)))
      .toList();

  Future<List<BoardRow>> leaderboard(BoardScope scope, {int limit = 50}) async =>
      _rows(await supa.rpc('leaderboard',
          params: {'p_scope': scope.name, 'p_limit': limit}));

  Future<List<LeagueRow>> myLeague() async {
    final res = await supa.rpc('my_league');
    return (res as List? ?? const [])
        .map((r) => LeagueRow.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ── Arcade scores ──────────────────────────────────────
  /// Returns (score, best, isRecord).
  Future<(int, int, bool)> submitGameScore(
    String game, int score, {Map<String, dynamic> meta = const {}}) async {
    final res = await supa.rpc('submit_game_score', params: {
      'p_game': game, 'p_score': score, 'p_meta': meta,
    });
    final m = Map<String, dynamic>.from(res as Map);
    return ((m['score'] ?? 0) as int,
            (m['best'] ?? 0) as int,
            (m['is_record'] ?? false) as bool);
  }

  Future<List<BoardRow>> gameBoard(String game, {int limit = 50}) async =>
      _rows(await supa.rpc('game_leaderboard',
          params: {'p_game': game, 'p_limit': limit}));

  Future<int> myBest(String game) async {
    final uid = currentUid;
    if (uid == null) return 0;
    final rows = await supa
        .from('game_scores').select('score')
        .eq('user_id', uid).eq('game', game)
        .order('score', ascending: false).limit(1);
    final list = rows as List;
    return list.isEmpty ? 0 : ((list.first as Map)['score'] ?? 0) as int;
  }

  // ── Tournament ─────────────────────────────────────────
  Future<Tournament> ensureTournament() async {
    final row = await supa.rpc('ensure_tournament');
    return Tournament.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<void> submitTournamentRound(int tournamentId, int score) =>
      supa.rpc('submit_tournament_round',
          params: {'p_tournament': tournamentId, 'p_score': score});

  Future<List<BoardRow>> tournamentBoard(int id, {int limit = 50}) async =>
      _rows(await supa.rpc('tournament_board',
          params: {'p_tournament': id, 'p_limit': limit}));

  Future<int> myTournamentScore(int id) async {
    final uid = currentUid;
    if (uid == null) return 0;
    final row = await supa.from('tournament_entries')
        .select('score').eq('tournament_id', id).eq('user_id', uid).maybeSingle();
    return (row?['score'] ?? 0) as int;
  }

  // ── Global daily challenge ─────────────────────────────
  Future<bool> playedDailyToday() async {
    final uid = currentUid;
    if (uid == null) return false;
    final day = DateTime.now().toIso8601String().substring(0, 10);
    final row = await supa.from('daily_results')
        .select('user_id').eq('day', day).eq('user_id', uid).maybeSingle();
    return row != null;
  }

  /// Returns (rank, players).
  Future<(int, int)> submitDaily({
    required String cefr,
    required int score,
    required int correct,
    required int total,
    required int ms,
  }) async {
    final res = await supa.rpc('submit_daily_result', params: {
      'p_cefr': cefr, 'p_score': score,
      'p_correct': correct, 'p_total': total, 'p_ms': ms,
    });
    final m = Map<String, dynamic>.from(res as Map);
    return ((m['rank'] ?? 0) as int, (m['players'] ?? 1) as int);
  }

  Future<List<BoardRow>> dailyBoard(String cefr, {int limit = 50}) async =>
      _rows(await supa.rpc('daily_board',
          params: {'p_cefr': cefr, 'p_limit': limit}));

  // ── Friends ────────────────────────────────────────────
  Future<List<BoardRow>> friends() async =>
      _rows(await supa.rpc('my_friends'));

  /// Finds people by handle (EN-16). The server requires two characters and
  /// skips guest accounts, so this can no longer be used to page through
  /// everybody who has ever installed the app.
  Future<List<BoardRow>> searchUsers(String query) async =>
      _rows(await supa.rpc('search_users',
          params: {'p_query': query, 'p_limit': 20}));

  /// Asks somebody to be friends (EN-15 / KK-2).
  ///
  /// This used to write `status: 'accepted'` straight into `friendships` from
  /// the client, so anybody could make themselves anybody's friend with no
  /// say in it — and that roster is what feeds the battle-invite surface and
  /// the team standing. The decision now belongs to the person being asked.
  ///
  /// Returns what the server did: 'pending' (asked), 'friends' (they had
  /// already asked, so this accepted it), or 'blocked'.
  Future<String> sendFriendRequest(String userId) async {
    final res = await supa.rpc('send_friend_request', params: {
      'p_user': userId,
    });
    return (res ?? 'pending').toString();
  }

  /// Answers a request that was sent to this user. [id] is the row id, which
  /// [friendRequests] carries in `value`.
  Future<String> respondToRequest(int id, {required bool accept}) async {
    final res = await supa.rpc('respond_friend_request', params: {
      'p_id': id, 'p_accept': accept,
    });
    return (res ?? '').toString();
  }

  /// Requests waiting on an answer from this user. `value` is the row id.
  Future<List<BoardRow>> friendRequests() async =>
      _rows(await supa.rpc('my_friend_requests'));

  /// Requests this user has sent and nobody has answered yet, so the button
  /// can say "sent" rather than offer to send again.
  Future<List<BoardRow>> sentRequests() async =>
      _rows(await supa.rpc('my_sent_requests'));

  Future<void> removeFriend(String userId) async {
    final uid = currentUid;
    if (uid == null) return;
    await supa.from('friendships').delete()
        .or('and(requester.eq.$uid,addressee.eq.$userId),'
            'and(requester.eq.$userId,addressee.eq.$uid)');
  }

  /// XP each of [userIds] has earned since the start of the current week
  /// (Monday 00:00 UTC), computed from `xp_log` rather than the lifetime
  /// total on `profiles.xp` — the only number a "this week's team race"
  /// can honestly show. Missing entries default to 0, not absence.
  Future<Map<String, int>> weeklyXp(List<String> userIds) async {
    if (userIds.isEmpty) return const {};
    final rows = await supa.rpc('team_weekly_xp', params: {'p_user_ids': userIds});
    return {
      for (final r in (rows as List? ?? const []))
        (r['user_id'] ?? '').toString(): (r['xp'] ?? 0) as int,
    };
  }
}
