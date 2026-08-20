// lib/data/repos/battle_repo.dart
import '../../core/constants/game_meta.dart';
import '../models/battle.dart';
import '../models/question.dart';
import '../supa.dart';
import '../../core/i18n/l10n.dart';

class BattleRepo {
  // ── Bot ────────────────────────────────────────────────
  Future<Battle> startBot({
    required List<Question> questions,
    required String cefr,
    required BotProfile bot,
  }) async {
    final uid = currentUid;
    if (uid == null) throw Exception(tr('Авторизация қажет'));

    final row = await supa.from('battles').insert({
      'mode': 'bot',
      'status': 'active',
      'p1': uid,
      'bot_name': bot.name,
      'bot_avatar': bot.avatar,
      'bot_accuracy': bot.accuracy,
      'bot_speed_ms': bot.speedMs,
      'questions': questions.map((q) => q.toJson()).toList(),
      'cefr': cefr,
      'started_at': DateTime.now().toUtc().toIso8601String(),
    }).select().single();

    return Battle.fromMap(row);
  }

  // ── Ranked matchmaking ─────────────────────────────────
  /// Returns a battle id as soon as an opponent is found, or null while the
  /// caller stays queued. Poll this every couple of seconds.
  Future<String?> findOrQueue({
    required String cefr,
    required List<Question> questions,
  }) async {
    final res = await supa.rpc('find_or_queue_match', params: {
      'p_cefr': cefr,
      'p_questions': questions.map((q) => q.toJson()).toList(),
    });
    return res?.toString();
  }

  Future<void> leaveQueue() async {
    try {
      await supa.rpc('leave_queue');
    } catch (_) {/* best effort */}
  }

  // ── Friend battles ─────────────────────────────────────
  /// Creates a friend battle. With [targetUserId] the battle goes straight to
  /// both players — no invite code to generate, share, or type — and shows up
  /// for the target immediately as a pending invite. Without it, the battle
  /// waits for anyone holding the invite code to join (the share-a-code flow).
  Future<Battle> createFriendBattle({
    required List<Question> questions,
    required String cefr,
    String? targetUserId,
  }) async {
    final row = await supa.rpc('create_friend_battle', params: {
      'p_questions': questions.map((q) => q.toJson()).toList(),
      'p_cefr': cefr,
      if (targetUserId != null) 'p_target': targetUserId,
    });
    return Battle.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<Battle> joinByCode(String code) async {
    final row = await supa.rpc('join_battle_by_code',
        params: {'p_code': code.trim().toUpperCase()});
    if (row == null) throw Exception(tr('Код табылмады'));
    return Battle.fromMap(Map<String, dynamic>.from(row as Map));
  }

  // ── Shared ─────────────────────────────────────────────
  Future<Battle?> byId(String id) async {
    final row = await supa.from('battles').select().eq('id', id).maybeSingle();
    return row == null ? null : Battle.fromMap(row);
  }

  Stream<Battle?> watch(String id) => supa
      .from('battles')
      .stream(primaryKey: ['id'])
      .eq('id', id)
      .map((rows) => rows.isEmpty ? null : Battle.fromMap(rows.first));

  /// [oppScore] carries the locally simulated bot score; it is ignored for
  /// human matches, where the opponent submits their own result.
  Future<Battle> submit({
    required String battleId,
    required int score,
    required int correct,
    int? oppScore,
  }) async {
    final row = await supa.rpc('submit_battle_result', params: {
      'p_battle': battleId,
      'p_score': score,
      'p_correct': correct,
      'p_opp_score': oppScore,
    });
    return Battle.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Recent finished battles for the profile history list.
  Future<List<Battle>> history({int limit = 20}) async {
    final uid = currentUid;
    if (uid == null) return [];
    final rows = await supa
        .from('battles')
        .select()
        .or('p1.eq.$uid,p2.eq.$uid')
        .eq('status', 'finished')
        .order('ended_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => Battle.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Friend battles the user was invited to but has not played yet.
  Future<List<Battle>> pendingInvites() async {
    final uid = currentUid;
    if (uid == null) return [];
    final rows = await supa
        .from('battles')
        .select()
        .eq('mode', 'friend')
        .eq('status', 'active')
        .or('p1.eq.$uid,p2.eq.$uid')
        .order('created_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map((r) => Battle.fromMap(Map<String, dynamic>.from(r as Map)))
        .where((b) => !b.iAmDone(uid))
        .toList();
  }
}
