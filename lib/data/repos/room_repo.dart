// lib/data/repos/room_repo.dart
//
// Private battles for three or four friends (EN-44 / KK-2).
//
// `battles` has p1 and p2 and nothing else, so every head-to-head mode in this
// app is structurally two people. A room is the missing shape: a host, a code,
// a roster with a ready flag on each member, and one question set everybody
// plays.
//
// Every write is an RPC. A client that could UPDATE room_members directly
// could set its own score, and the ready flag exists precisely so that one
// person cannot start the game for everybody.

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supa.dart';

/// Thrown when the room RPCs are not on the server yet.
class RoomsUnavailable implements Exception {
  const RoomsUnavailable();
}

class RoomMember {
  final String userId, name, avatarEmoji;
  final bool ready, done, isHost, isMe;
  final int score, correct;

  const RoomMember({
    required this.userId,
    required this.name,
    this.avatarEmoji = '🦊',
    this.ready = false,
    this.done = false,
    this.isHost = false,
    this.isMe = false,
    this.score = 0,
    this.correct = 0,
  });

  factory RoomMember.fromMap(Map<String, dynamic> m) => RoomMember(
    userId:      (m['user_id'] ?? '').toString(),
    name:        (m['name'] ?? '').toString(),
    avatarEmoji: (m['avatar_emoji'] ?? '🦊').toString(),
    ready:       (m['ready'] ?? false) as bool,
    done:        (m['done'] ?? false) as bool,
    isHost:      (m['is_host'] ?? false) as bool,
    isMe:        (m['is_me'] ?? false) as bool,
    score:       ((m['score'] ?? 0) as num).toInt(),
    correct:     ((m['correct'] ?? 0) as num).toInt(),
  );
}

class RoomState {
  final String id, code, status, cefr;
  final bool iAmHost, allReady;
  final int maxPlayers, playerCount;
  final List<RoomMember> members;
  /// Empty until the room is running — there is no reason to ship the answers
  /// to a lobby that has not started.
  final List<dynamic> questions;

  const RoomState({
    required this.id,
    this.code = '',
    this.status = 'waiting',
    this.cefr = 'A1',
    this.iAmHost = false,
    this.allReady = false,
    this.maxPlayers = 4,
    this.playerCount = 0,
    this.members = const [],
    this.questions = const [],
  });

  static RoomState? fromMap(Map<String, dynamic>? m) {
    if (m == null || m['id'] == null) return null;
    return RoomState(
      id:          m['id'].toString(),
      code:        (m['code'] ?? '').toString(),
      status:      (m['status'] ?? 'waiting').toString(),
      cefr:        (m['cefr'] ?? 'A1').toString(),
      iAmHost:     (m['i_am_host'] ?? false) as bool,
      allReady:    (m['all_ready'] ?? false) as bool,
      maxPlayers:  ((m['max_players'] ?? 4) as num).toInt(),
      playerCount: ((m['player_count'] ?? 0) as num).toInt(),
      members: [
        for (final r in (m['members'] as List? ?? const []))
          RoomMember.fromMap(Map<String, dynamic>.from(r as Map)),
      ],
      questions: (m['questions'] as List? ?? const []),
    );
  }

  bool get isWaiting  => status == 'waiting';
  bool get isRunning  => status == 'running';
  bool get isFinished => status == 'finished';

  /// EN-44 is explicit that the battle starts only once everybody is ready,
  /// and this is what the host's button reads. The server checks it again.
  bool get canStart => isWaiting && allReady && playerCount >= 2;

  /// Members still to mark themselves ready, so the lobby can name who is
  /// holding it up rather than just refusing to start.
  List<RoomMember> get waitingOn =>
      members.where((m) => !m.ready).toList();

  /// Final placing, best first.
  List<RoomMember> get placing =>
      [...members]..sort((a, b) => b.score.compareTo(a.score));
}

class RoomRepo {
  static bool _isMissing(Object e) {
    if (e is! PostgrestException) return false;
    final code = e.code ?? '';
    if (code == 'PGRST202' || code == 'PGRST203' || code == '42883') return true;
    final m = e.message.toLowerCase();
    return m.contains('could not find the function') ||
        m.contains('does not exist');
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      if (_isMissing(e)) throw const RoomsUnavailable();
      rethrow;
    }
  }

  static RoomState? _state(dynamic v) =>
      RoomState.fromMap(v is Map ? Map<String, dynamic>.from(v) : null);

  Future<RoomState?> create({
    required String cefr,
    required List<Map<String, dynamic>> questions,
    int maxPlayers = 4,
  }) =>
      _guard(() async => _state(await supa.rpc('create_room', params: {
            'p_cefr': cefr,
            'p_questions': questions,
            'p_max': maxPlayers,
          })));

  Future<RoomState?> join(String code) =>
      _guard(() async => _state(
          await supa.rpc('join_room', params: {'p_code': code.trim()})));

  Future<RoomState?> state(String roomId) =>
      _guard(() async => _state(
          await supa.rpc('room_state', params: {'p_room': roomId})));

  Future<RoomState?> setReady(String roomId, bool ready) =>
      _guard(() async => _state(await supa.rpc('set_ready', params: {
            'p_room': roomId, 'p_ready': ready,
          })));

  Future<RoomState?> start(String roomId) =>
      _guard(() async => _state(
          await supa.rpc('start_room', params: {'p_room': roomId})));

  Future<void> leave(String roomId) => _guard(() async {
    await supa.rpc('leave_room', params: {'p_room': roomId});
  });

  Future<RoomState?> submit(String roomId, int score, int correct) =>
      _guard(() async => _state(await supa.rpc('submit_room_score', params: {
            'p_room': roomId, 'p_score': score, 'p_correct': correct,
          })));

  /// The roster, live. A lobby where you cannot see somebody join is not a
  /// lobby, so this is a stream rather than a poll — the row-level payload is
  /// ignored and the full state re-read, because `room_state` folds in the
  /// profiles and the ready summary that the raw rows do not carry.
  Stream<List<Map<String, dynamic>>> watchMembers(String roomId) => supa
      .from('room_members')
      .stream(primaryKey: ['room_id', 'user_id'])
      .eq('room_id', roomId);
}
