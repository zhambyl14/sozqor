// lib/data/models/app_event.dart

import '../../core/i18n/l10n.dart';

/// A live event pushed from the server — new seasonal challenges, topic packs
/// and quests can appear without shipping a new build.
class AppEvent {
  final int id;
  final String slug, title, subtitle, emoji, kind;
  final String? topic;
  final int xpReward, target;
  final DateTime startsAt, endsAt;

  const AppEvent({
    required this.id,
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.kind,
    required this.xpReward,
    required this.target,
    required this.startsAt,
    required this.endsAt,
    this.topic,
  });

  factory AppEvent.fromMap(Map<String, dynamic> m) {
    final payload = Map<String, dynamic>.from(
        (m['payload'] as Map?) ?? const {});
    return AppEvent(
      id:       (m['id'] ?? 0) as int,
      slug:     (m['slug'] ?? '').toString(),
      title:    (m['title'] ?? '').toString(),
      subtitle: (m['subtitle'] ?? '').toString(),
      emoji:    (m['emoji'] ?? '🎉').toString(),
      kind:     (m['kind'] ?? 'challenge').toString(),
      topic:    m['topic']?.toString(),
      xpReward: (m['xp_reward'] ?? 200) as int,
      target:   int.tryParse('${payload['target'] ?? 10}') ?? 10,
      startsAt: DateTime.tryParse('${m['starts_at']}') ?? DateTime.now(),
      endsAt:   DateTime.tryParse('${m['ends_at']}') ??
                DateTime.now().add(const Duration(days: 30)),
    );
  }

  Duration get remaining {
    final d = endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  String get remainingLabel {
    final r = remaining;
    if (r.inDays > 0) return trp('{p1} күн қалды', {'p1': '${r.inDays}'});
    if (r.inHours > 0) return trp('{p1} сағат қалды', {'p1': '${r.inHours}'});
    return trp('{p1} минут қалды', {'p1': '${r.inMinutes}'});
  }
}

class EventProgress {
  final int eventId, progress, target;
  final bool completed;
  const EventProgress({
    required this.eventId,
    required this.progress,
    required this.target,
    required this.completed,
  });

  factory EventProgress.fromMap(Map<String, dynamic> m) => EventProgress(
    eventId:   (m['event_id'] ?? 0) as int,
    progress:  (m['progress'] ?? 0) as int,
    target:    (m['target'] ?? 1) as int,
    completed: (m['completed'] ?? false) as bool,
  );

  double get ratio => target == 0 ? 0 : (progress / target).clamp(0.0, 1.0);
}
