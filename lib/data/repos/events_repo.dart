// lib/data/repos/events_repo.dart
//
// EN-27: an event has to be visibly progressing, and it has to pay out.
//
// Three things were missing rather than broken. `event_progress` rows were
// only created by `bump_event`, so an event a learner had not yet touched had
// no row and therefore no progress bar — it looked inert until the moment it
// suddenly did not. `claim_event_prize` existed on the server and nothing in
// the app ever called it, so the XP and the prize item an event promised were
// unreachable. And `event_board` existed too, so "personal contribution"
// could always have been answered and never was.

import '../models/app_event.dart';
import '../models/battle.dart';
import '../supa.dart';

class EventsRepo {
  Future<List<AppEvent>> active(String cefr) async {
    final rows = await supa.rpc('active_events', params: {'p_cefr': cefr});
    return (rows as List? ?? const [])
        .map((r) => AppEvent.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<Map<int, EventProgress>> myProgress() async {
    final uid = currentUid;
    if (uid == null) return {};
    final rows = await supa
        .from('event_progress').select().eq('user_id', uid);
    return {
      for (final r in rows as List)
        ((r as Map)['event_id'] ?? 0) as int:
            EventProgress.fromMap(Map<String, dynamic>.from(r)),
    };
  }

  /// Joins an event so it has a progress row from the moment it is looked at.
  ///
  /// Without this a bar only appears after the first bump, which is what made
  /// an event look like it was doing nothing until it abruptly was.
  Future<EventProgress?> join(int eventId) async {
    try {
      final row = await supa.rpc('join_event', params: {'p_event': eventId});
      return row == null
          ? null
          : EventProgress.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      return null;
    }
  }

  /// Collects the XP and the cosmetic an event promised. The RPC has existed
  /// since events shipped and nothing has ever called it.
  Future<int> claimPrize(int eventId) async {
    final res = await supa.rpc('claim_event_prize', params: {
      'p_event': eventId,
    });
    if (res is Map) return ((res['xp'] ?? 0) as num).toInt();
    return ((res ?? 0) as num).toInt();
  }

  /// Who is doing best in an event. EN-27 asks for personal contribution and
  /// this is the only honest way to place it — against everyone else's.
  Future<List<BoardRow>> board(int eventId, {int limit = 30}) async {
    final rows = await supa.rpc('event_board', params: {
      'p_event': eventId, 'p_limit': limit,
    });
    return [
      for (final r in (rows as List? ?? const []))
        BoardRow.fromMap(Map<String, dynamic>.from(r as Map)),
    ];
  }

  Future<EventProgress?> bump(int eventId, {int by = 1}) async {
    try {
      final row = await supa.rpc('bump_event',
          params: {'p_event': eventId, 'p_by': by});
      return row == null
          ? null
          : EventProgress.fromMap(Map<String, dynamic>.from(row as Map));
    } catch (_) {
      return null;
    }
  }

  /// Advances every running event whose metric matches [metric].
  Future<void> bumpByMetric(String cefr, String metric, {int by = 1}) async {
    try {
      final events = await active(cefr);
      final progress = await myProgress();
      for (final e in events) {
        if (progress[e.id]?.completed == true) continue;
        final matches = switch (metric) {
          'words'    => e.kind == 'quest' || e.kind == 'topic_pack',
          'battles'  => e.kind == 'challenge',
          'rounds'   => e.kind == 'tournament' || e.kind == 'season',
          _          => false,
        };
        if (matches) await bump(e.id, by: by);
      }
    } catch (_) {/* events are a bonus, never a blocker */}
  }
}
