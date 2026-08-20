// lib/data/repos/events_repo.dart
import '../models/app_event.dart';
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
