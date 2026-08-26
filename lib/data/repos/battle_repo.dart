// lib/data/repos/battle_repo.dart
import '../../core/constants/game_meta.dart';
import '../models/invite.dart';
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
  // ── Friend battles ────────────────────────────────────
  /// Rings a friend. The battle comes back in the `invited` state and plays
  /// for NOBODY until they accept.
  ///
  /// This is the fix for the complaint that a friend battle "started by
  /// itself": the old flow created an ACTIVE battle and dropped the sender
  /// straight into it, so one person's tap began a two-person match and the
  /// friend arrived to find it already over.
  ///
  /// Throws INVITE_ERR:busy when they are mid-match, INVITE_ERR:blocked with
  /// a countdown when they have just turned an invitation down, and
  /// INVITE_ERR:not_friend
  /// when they are not on the list. humanError() turns all three into a
  /// sentence the sender can act on.
  Future<Battle> inviteFriend({
    required String targetUserId,
    required List<Question> questions,
    required String cefr,
  }) async {
    final row = await supa.rpc('invite_friend_battle', params: {
      'p_target': targetUserId,
      'p_questions': questions.map((q) => q.toJson()).toList(),
      'p_cefr': cefr,
      'p_lang': AppLang.current,
    });
    return Battle.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// Yes or no, from the person who was rung. A `false` here — or letting the
  /// fifteen seconds run out, which the overlay reports as a decline — costs
  /// the sender two minutes of silence, so nobody can ring twenty times.
  Future<Battle> respondToInvite(String battleId, bool accept) async {
    final row = await supa.rpc('respond_battle_invite', params: {
      'p_battle': battleId,
      'p_accept': accept,
      'p_lang': AppLang.current,
    });
    return Battle.fromMap(Map<String, dynamic>.from(row as Map));
  }

  /// What is ringing right now, with enough about the caller to draw the
  /// banner without a second request.
  Future<List<BattleInvite>> incomingInvites() async {
    final rows = await supa.rpc('my_battle_invites');
    return (rows as List? ?? const [])
        .map((r) => BattleInvite.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Whether this person can be rung at all. Asked before sending so the
  /// caller is told "they are in a match" rather than watching an invitation
  /// go unanswered for fifteen seconds.
  Future<bool> isBusy(String userId) async {
    try {
      final res = await supa.rpc('user_busy', params: {'p_user': userId});
      return res == true;
    } catch (_) {
      return false;
    }
  }

  // ── Rematch, agreed by both ───────────────────────────
  /// Marks this player's side of a rematch offer.
  ///
  /// Returns the next battle ONLY once the other side has offered too, and
  /// null while it is still one-sided. That null is the whole point: "Кек
  /// қайтару" used to pop back to the arena and start ordinary
  /// matchmaking, so a ranked rematch was against a stranger.
  ///
  /// Throws REMATCH_ERR:series_over once three games are played or one player
  /// is two up. After that a new opponent is found the normal way and it is
  /// not a rematch any more.
  Future<Battle?> offerRematch(String battleId) async {
    final row = await supa.rpc('offer_rematch', params: {'p_battle': battleId});
    if (row is! Map) return null;
    final m = Map<String, dynamic>.from(row);
    // `return null` from a function whose return type is `battles` does NOT
    // reach us as null: PostgREST answers with an object carrying every
    // column set to null. Read literally, that is a battle with no id and no
    // questions — which is exactly what the screen then tried to open, on the
    // one-sided half of every rematch handshake. The id is the tell.
    if (m['id'] == null) return null;
    final b = Battle.fromMap(m);
    if (b.questions.isEmpty) return null;
    return b;
  }

  /// Where the best-of-three stands, read by BOTH clients from the same rows
  /// instead of each keeping a private tally.
  Future<SeriesState?> seriesState(String battleId) async {
    try {
      final row = await supa.rpc('series_state', params: {'p_battle': battleId});
      if (row == null) return null;
      return SeriesState.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      return null;
    }
  }

  // ── Presence ──────────────────────────────────────
  /// The heartbeat. Called every few seconds from the battle screen; the
  /// answer says whether the opponent has gone quiet (pause the clock) and
  /// whether they have been quiet long enough for the win to be claimed.
  Future<BattlePresence?> touch(String battleId) async {
    try {
      final row = await supa.rpc('touch_battle', params: {'p_battle': battleId});
      return BattlePresence.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      return null;
    }
  }

  /// The unfinished match to drop the learner back into when they reopen the
  /// app, so a battle they were in the middle of is not simply lost.
  Future<Battle?> myOpenBattle() async {
    try {
      final row = await supa.rpc('my_open_battle');
      if (row is! Map) return null;
      final m = Map<String, dynamic>.from(row);

      // A function returning a composite type does NOT come back as null when
      // it selects no row — PostgREST hands over an object with every field
      // set to null. Parsed straight, that becomes a Battle with no id and no
      // questions, which is exactly the "Аяқталмаған баттл бар" card that
      // opened onto "Бұл баттлдың сұрақтары бос".
      if (m['id'] == null) return null;

      final b = Battle.fromMap(m);
      // And a battle with nothing to answer is not one worth returning to.
      if (b.questions.isEmpty) return null;
      return b;
    } catch (_) {
      return null;
    }
  }

  // ── After the match ─────────────────────────────────
  /// Who you just played and whether you can add them, in one call so the
  /// end-of-match card can draw both actions without guessing.
  Future<Map<String, dynamic>?> opponentCard(String battleId) async {
    try {
      final row = await supa.rpc('opponent_card', params: {'p_battle': battleId});
      if (row == null) return null;
      return Map<String, dynamic>.from(row as Map);
    } catch (_) {
      return null;
    }
  }

  /// The whole vocabulary of the quick message. Canned on purpose: a phrase
  /// nobody can write cannot be abuse, and tapping is faster than typing.
  Future<List<QuickPhrase>> quickPhrases() async {
    try {
      final rows = await supa.rpc('quick_phrases');
      return (rows as List? ?? const [])
          .map((r) => QuickPhrase.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> sendQuickMessage(String battleId, String phrase) =>
      supa.rpc('send_battle_message',
          params: {'p_battle': battleId, 'p_phrase': phrase});

  Future<List<QuickMessage>> messagesFor(String battleId) async {
    try {
      final rows = await supa.rpc('battle_messages_for',
          params: {'p_battle': battleId});
      return (rows as List? ?? const [])
          .map((r) => QuickMessage.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// The code-sharing flow, unchanged: a battle anybody holding the code can
  /// join. Kept because a group of friends in one room still wants it.
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

  /// Friend battles somebody has just aimed at this user (EN-12 / KK-2).
  ///
  /// A live stream rather than a poll, because an invitation is only worth
  /// anything while the person who sent it is still waiting. Everything the
  /// row cannot express — is it recent, have I already played it, have I
  /// muted this sender — is decided by the caller.
  Stream<List<Battle>> watchInvites() {
    final uid = currentUid;
    if (uid == null) return Stream.value(const []);
    return supa
        .from('battles')
        .stream(primaryKey: ['id'])
        .eq('p2', uid)
        .map((rows) => rows
            .map((r) => Battle.fromMap(Map<String, dynamic>.from(r)))
            // `invited`, not `active`. An active row is a match already under
            // way, and treating one as an invitation is exactly what let the
            // sender start playing before anybody had agreed to anything.
            .where((b) => b.mode == 'friend' && b.isInvited)
            .where((b) => b.inviteSecondsLeft > 0)
            .toList());
  }

  /// Turns down an invitation. Goes through the RPC rather than writing the
  /// row directly, because refusing is what starts the two-minute silence
  /// that stops a friend ringing again the moment they are told no.
  Future<void> declineInvite(String battleId) =>
      respondToInvite(battleId, false).then((_) {});

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

  /// Claims the win when an opponent walks away mid-match (EN-20 / KK-3).
  ///
  /// The server decides, not the caller: it checks that this player really
  /// has submitted, that the opponent still has not, and that the grace
  /// period has run out. Before this, an opponent who closed the app left the
  /// match 'active' for ever and neither rating moved — the literal report in
  /// the PRD. Returns the battle unchanged while the grace period is still
  /// running, so it is safe to call on a timer.
  Future<Battle> claimForfeit(String battleId) async {
    final row = await supa.rpc('claim_battle_forfeit',
        params: {'p_battle': battleId});
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

  /// Invitations that are ringing right now — sent to this user or by them.
  /// An `active` row is a match in progress and belongs on the battle screen,
  /// not in a list of things waiting for an answer.
  Future<List<Battle>> pendingInvites() async {
    final uid = currentUid;
    if (uid == null) return [];
    final rows = await supa
        .from('battles')
        .select()
        .eq('mode', 'friend')
        .eq('status', 'invited')
        .or('p1.eq.$uid,p2.eq.$uid')
        .order('created_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map((r) => Battle.fromMap(Map<String, dynamic>.from(r as Map)))
        .where((b) => b.inviteSecondsLeft > 0)
        .toList();
  }

  /// Friend battles that WERE accepted and then left unfinished. Separate
  /// from [pendingInvites] because the two need different words on screen.
  Future<List<Battle>> unfinishedFriendBattles() async {
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
